#!/bin/sh
set -eu

# Requires the selected producer checkouts to be exactly the commits this
# repository pins.
#
# The compatible producer pair was an operator convention: the witnesses took
# whatever EDICT_REPO and ECHO_REPO pointed at. A consumer sitting on a stale
# producer was undetectable, which is what made the advance to Edict df80f92a
# and Echo c354d531 look like a repository failure rather than a pin change.

: "${EDICT_REPO:?set EDICT_REPO to the compatible Edict checkout}"
: "${ECHO_REPO:?set ECHO_REPO to the compatible Echo checkout}"

command -v jq >/dev/null
command -v git >/dev/null

lock=producers.lock.json
test -f "$lock"

test "$(jq -r '.version' "$lock")" = 1

check_producer() {
  name=$1
  checkout=$2
  expected=$(jq -r ".$name.commit" "$lock")
  case "$expected" in
    ????????????????????????????????????????) ;;
    *)
      echo "$lock does not pin a full $name commit" >&2
      exit 1
      ;;
  esac
  actual=$(git -C "$checkout" rev-parse HEAD)
  if test "$actual" != "$expected"; then
    echo "$name checkout is $actual but $lock pins $expected" >&2
    exit 1
  fi
  # A commit id says nothing about the working tree. Uncommitted edits to the
  # producer leave rev-parse reporting the pinned commit while the build
  # compiles different sources, so the run would claim a pin it is not
  # honouring. The vendored artifact comparisons do not cover this: they check
  # the fixtures, not the compiler and host crates the build actually uses.
  if test -n "$(git -C "$checkout" status --porcelain)"; then
    echo "$name checkout has uncommitted changes and is not the pinned $expected" >&2
    git -C "$checkout" status --porcelain >&2
    exit 1
  fi
}

check_producer edict "$EDICT_REPO"
check_producer echo "$ECHO_REPO"
