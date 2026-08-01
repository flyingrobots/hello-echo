#!/bin/sh
set -eu

: "${EDICT_REPO:?set EDICT_REPO to the compatible Edict checkout}"
: "${ECHO_REPO:?set ECHO_REPO to the compatible Echo checkout}"

command -v jq >/dev/null

EDICT_REPO=$(CDPATH='' cd -- "$EDICT_REPO" && pwd -P)
ECHO_REPO=$(CDPATH='' cd -- "$ECHO_REPO" && pwd -P)

test -f "$EDICT_REPO/crates/edict-cli/Cargo.toml"
test -f "$ECHO_REPO/crates/warp-core/Cargo.toml"

fixture_source="$EDICT_REPO/fixtures/lawpack/workspace-snapshot"
cmp effect/src/observe-workspace.edict "$fixture_source/observe-workspace.edict"
for artifact in \
  manifest.cbor \
  exports.cbor \
  adapter.cbor \
  request-profile-configuration.cbor \
  input-schema.cbor \
  input-schema.sha256 \
  settlement-schema.cbor \
  settlement-schema.sha256 \
  reconciliation-law.cbor \
  reconciliation-law.sha256
do
  cmp "effect/vendor/workspace-snapshot/$artifact" "$fixture_source/$artifact"
done

# Every external-action schema slot in the compiler source must pin the exact
# identity of the vendored artifact that slot names. A cross-wired, unresolved,
# or sentinel identity fails the build closed.
tests/lib/check-resource-identities.sh \
  workspace.snapshot \
  effect/vendor/workspace-snapshot \
  effect/src/observe-workspace.edict

mkdir -p .build/effect
provider_source="$ECHO_REPO/schemas/edict-provider/package/v1"
test -f "$provider_source/provider-manifest.echo.json"
test -f "$provider_source/generated/primary/target-profile.echo-dpo.cbor"
if find "$provider_source" -type l -print -quit | grep -q .; then
  echo "provider package must not contain symlinks" >&2
  exit 1
fi
rm -rf .build/effect/echo-provider
mkdir -p .build/effect/echo-provider
cp -RL "$provider_source/." .build/effect/echo-provider/
test ! -d .build/effect/echo-provider/.git
if find .build/effect/echo-provider -type l -print -quit | grep -q .; then
  echo "copied provider package must not contain symlinks" >&2
  exit 1
fi

rm -rf .build/effect/application
cargo run \
  --quiet \
  --manifest-path "$EDICT_REPO/Cargo.toml" \
  -p edict-cli \
  --bin edict \
  <tests/effect-build-request.jsonl

test -s .build/effect/application/core.cbor
test -s .build/effect/application/target-ir.cbor
cmp \
  .build/effect/application/core.cbor \
  "$fixture_source/observe-workspace.core.cbor"
cmp \
  .build/effect/application/target-ir.cbor \
  "$fixture_source/observe-workspace.target-ir.cbor"
test ! -e .build/effect/application/executable-operation-package.cbor
test ! -e .build/effect/application/verification-report.cbor

project_root=$(pwd -P)
escaped_echo_repo=$(
  jq -Rn --arg value "$ECHO_REPO" '$value' |
    sed -e 's/^"//' -e 's/"$//' -e 's/[\\&|]/\\&/g'
)
escaped_project_root=$(
  jq -Rn --arg value "$project_root" '$value' |
    sed -e 's/^"//' -e 's/"$//' -e 's/[\\&|]/\\&/g'
)
mkdir -p .build/effect/host
sed \
  -e "s|@ECHO_REPO@|$escaped_echo_repo|g" \
  -e "s|@PROJECT_ROOT@|$escaped_project_root|g" \
  effect-host/Cargo.toml.template \
  >.build/effect/host/Cargo.toml
cargo build \
  --quiet \
  --manifest-path .build/effect/host/Cargo.toml \
  --target-dir .build/effect/host-target
test -x .build/effect/host-target/debug/hello-effect-host
