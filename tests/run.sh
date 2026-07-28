#!/bin/sh
set -eu

: "${ECHO_REPO:?set ECHO_REPO to the compatible Echo checkout}"

input_file=${1:?usage: tests/run.sh INPUT_JSON WAL_DIRECTORY}
wal_dir=${2:?usage: tests/run.sh INPUT_JSON WAL_DIRECTORY}

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)

case "$input_file" in
  /*) ;;
  *) input_file="$project_root/$input_file" ;;
esac

case "$wal_dir" in
  /*) ;;
  *) wal_dir="$project_root/$wal_dir" ;;
esac

package="$project_root/.build/application/executable-operation-package.cbor"
verification_report="$project_root/.build/application/verification-report.cbor"
lawpack_manifest="$project_root/vendor/causal-cell/manifest.cbor"
lawpack_adapter="$project_root/vendor/causal-cell/adapter.cbor"
target_configuration="$project_root/vendor/causal-cell/echo-operation-configuration.cbor"

test -s "$package"
test -s "$verification_report"
test -s "$lawpack_manifest"
test -s "$lawpack_adapter"
test -s "$target_configuration"
test -f "$input_file"

mkdir -p "$(dirname "$wal_dir")"

cargo run \
  --quiet \
  --manifest-path "$ECHO_REPO/Cargo.toml" \
  -p xtask \
  -- \
  run-edict-operation \
  --package "$package" \
  --verification-report "$verification_report" \
  --lawpack-manifest "$lawpack_manifest" \
  --lawpack-adapter "$lawpack_adapter" \
  --target-configuration "$target_configuration" \
  --input "$input_file" \
  --wal-dir "$wal_dir" \
  --json
