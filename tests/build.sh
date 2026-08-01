#!/bin/sh
set -eu

: "${EDICT_REPO:?set EDICT_REPO to the compatible Edict checkout}"
: "${ECHO_REPO:?set ECHO_REPO to the compatible Echo checkout}"

# The producer pair is pinned in-repository, not chosen by the caller.
./tests/producer-lock.sh

test -f "$EDICT_REPO/crates/edict-cli/Cargo.toml"
test -f "$ECHO_REPO/Cargo.toml"

capability_source="$EDICT_REPO/fixtures/lawpack/causal-cell"
for artifact in \
  manifest.cbor \
  exports.cbor \
  adapter.cbor \
  echo-operation-configuration.cbor
do
  test -f "$capability_source/$artifact"
  cmp "vendor/causal-cell/$artifact" "$capability_source/$artifact"
done

mkdir -p .build
provider_source="$ECHO_REPO/schemas/edict-provider/package/v1"
test -f "$provider_source/provider-manifest.echo.json"
test -f "$provider_source/components/lowerer.echo-dpo.component.wasm"
test -f "$provider_source/components/verifier.echo-dpo.component.wasm"
if find "$provider_source" -type l -print -quit | grep -q .; then
  echo "provider package must not contain symlinks" >&2
  exit 1
fi
rm -rf .build/echo-provider
mkdir -p .build/echo-provider
cp -RL "$provider_source/." .build/echo-provider/
test ! -d .build/echo-provider/.git
if find .build/echo-provider -type l -print -quit | grep -q .; then
  echo "copied provider package must not contain symlinks" >&2
  exit 1
fi

rm -rf .build/application
cargo run \
  --quiet \
  --manifest-path "$EDICT_REPO/Cargo.toml" \
  -p edict-cli \
  --bin edict \
  < tests/build-request.jsonl

test -s .build/application/executable-operation-package.cbor
test -s .build/application/verification-report.cbor
