#!/bin/sh
set -eu

: "${EDICT_REPO:?set EDICT_REPO to the compatible Edict checkout}"
: "${ECHO_REPO:?set ECHO_REPO to the compatible Echo checkout}"

command -v jq >/dev/null

EDICT_REPO=$(CDPATH='' cd -- "$EDICT_REPO" && pwd -P)
ECHO_REPO=$(CDPATH='' cd -- "$ECHO_REPO" && pwd -P)

test -f "$EDICT_REPO/crates/edict-cli/Cargo.toml"
test -f "$ECHO_REPO/crates/warp-core/Cargo.toml"

fixture_source="$EDICT_REPO/fixtures/lawpack/workspace-patch"
cmp patch/src/apply-validated-patch.edict "$fixture_source/apply-validated-patch.edict"
for artifact in \
  manifest.cbor \
  manifest.sha256 \
  exports.cbor \
  exports.sha256 \
  adapter.cbor \
  adapter.sha256 \
  request-profile-configuration.cbor \
  request-profile-configuration.sha256 \
  input-schema.cbor \
  input-schema.sha256 \
  settlement-schema.cbor \
  settlement-schema.sha256 \
  reconciliation-law.cbor \
  reconciliation-law.sha256
do
  cmp "patch/vendor/workspace-patch/$artifact" "$fixture_source/$artifact"
done

# Every external-action resource identity in the compiler source must resolve to
# a vendored artifact whose generator-owned digest sidecar carries that exact
# identity. An unresolved or sentinel identity fails the build closed.
for resource in input-schema settlement-schema reconciliation-law
do
  identity=$(tr -d '[:space:]' <"patch/vendor/workspace-patch/$resource.sha256")
  case "$identity" in
    sha256:????????????????????????????????????????????????????????????????) ;;
    *)
      echo "resource $resource has a malformed identity digest" >&2
      exit 1
      ;;
  esac
  case "$identity" in
    *0000000000000000|*1111111111111111|*2222222222222222|*3333333333333333|\
    *4444444444444444|*5555555555555555|*6666666666666666|*7777777777777777|\
    *8888888888888888|*9999999999999999)
      echo "resource $resource still pins a sentinel identity digest" >&2
      exit 1
      ;;
  esac
  grep -qF "$identity" patch/src/apply-validated-patch.edict || {
    echo "compiler source does not pin the vendored $resource identity" >&2
    exit 1
  }
done

# The compiler source must not retain any unresolved schema reference.
if grep -nE 'digest "sha256:(0{64}|1{64}|2{64}|3{64}|4{64}|5{64}|6{64}|7{64}|8{64}|9{64})"' \
  patch/src/apply-validated-patch.edict
then
  echo "compiler source retains a sentinel schema digest" >&2
  exit 1
fi

mkdir -p .build/patch
provider_source="$ECHO_REPO/schemas/edict-provider/package/v1"
test -f "$provider_source/provider-manifest.echo.json"
test -f "$provider_source/generated/primary/target-profile.echo-dpo.cbor"
if find "$provider_source" -type l -print -quit | grep -q .; then
  echo "provider package must not contain symlinks" >&2
  exit 1
fi
rm -rf .build/patch/echo-provider
mkdir -p .build/patch/echo-provider
cp -RL "$provider_source/." .build/patch/echo-provider/
test ! -d .build/patch/echo-provider/.git
if find .build/patch/echo-provider -type l -print -quit | grep -q .; then
  echo "copied provider package must not contain symlinks" >&2
  exit 1
fi

rm -rf .build/patch/application
cargo run \
  --quiet \
  --manifest-path "$EDICT_REPO/Cargo.toml" \
  -p edict-cli \
  --bin edict \
  <tests/patch-build-request.jsonl

test -s .build/patch/application/core.cbor
test -s .build/patch/application/target-ir.cbor
cmp \
  .build/patch/application/core.cbor \
  "$fixture_source/apply-validated-patch.core.cbor"
cmp \
  .build/patch/application/target-ir.cbor \
  "$fixture_source/apply-validated-patch.target-ir.cbor"
test ! -e .build/patch/application/executable-operation-package.cbor
test ! -e .build/patch/application/verification-report.cbor

project_root=$(pwd -P)
escaped_echo_repo=$(
  jq -Rn --arg value "$ECHO_REPO" '$value' |
    sed -e 's/^"//' -e 's/"$//' -e 's/[\\&|]/\\&/g'
)
escaped_project_root=$(
  jq -Rn --arg value "$project_root" '$value' |
    sed -e 's/^"//' -e 's/"$//' -e 's/[\\&|]/\\&/g'
)
mkdir -p .build/patch/host
sed \
  -e "s|@ECHO_REPO@|$escaped_echo_repo|g" \
  -e "s|@PROJECT_ROOT@|$escaped_project_root|g" \
  patch-host/Cargo.toml.template \
  >.build/patch/host/Cargo.toml
cargo build \
  --quiet \
  --manifest-path .build/patch/host/Cargo.toml \
  --target-dir .build/patch/host-target
test -x .build/patch/host-target/debug/hello-effect-patch-host
