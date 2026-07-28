#!/bin/sh
set -eu

mkdir -p .build/application
stale_artifact=.build/application/stale-artifact
touch "$stale_artifact"

./tests/build.sh

if test -e "$stale_artifact"; then
  echo "build retained stale application output" >&2
  exit 1
fi
