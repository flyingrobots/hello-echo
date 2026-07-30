#!/bin/sh
set -eu

if test "$#" -lt 3; then
  echo "usage: tests/patch-run.sh PHASE REQUEST_JSON WAL_DIRECTORY [PHASE_ARGUMENT]" >&2
  exit 2
fi

project_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
phase=$1
request_file=$2
wal_dir=$3
shift 3

case "$request_file" in
  /*) ;;
  *) request_file="$project_root/$request_file" ;;
esac
case "$wal_dir" in
  /*) ;;
  *) wal_dir="$project_root/$wal_dir" ;;
esac

core_file=${PATCH_CORE_FILE:-"$project_root/.build/patch/application/core.cbor"}
target_ir_file=${PATCH_TARGET_IR_FILE:-"$project_root/.build/patch/application/target-ir.cbor"}
case "$core_file" in
  /*) ;;
  *) core_file="$project_root/$core_file" ;;
esac
case "$target_ir_file" in
  /*) ;;
  *) target_ir_file="$project_root/$target_ir_file" ;;
esac

exec "$project_root/.build/patch/host-target/debug/hello-effect-patch-host" \
  "$phase" \
  "$request_file" \
  "$wal_dir" \
  "$core_file" \
  "$target_ir_file" \
  "$@"
