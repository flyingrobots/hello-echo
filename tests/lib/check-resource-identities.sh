#!/bin/sh
set -eu

# Usage: check-resource-identities.sh <namespace> <vendor-dir> <source-file>
#
# Proves that every external-action schema slot in a compiler source pins the
# exact identity of the vendored artifact that slot names.
#
# The identity a slot declares is what Edict resolves against the artifact
# supplied through `externalActionResources`. Checking only that an identity
# appears somewhere in the source would accept a source whose slots are wired
# to each other's artifacts, so each slot is compared to its own sidecar.
#
# Exercised by tests/resource-identity-guard.sh.

namespace=$1
vendor=$2
source_file=$3

test -d "$vendor"
test -f "$source_file"

# Reads the digest a slot declares. The coordinate names the slot and the
# digest follows it on a later line, so this takes the first digest after the
# coordinate and stops.
declared_identity() {
  awk -v coordinate="$1" '
    seen {
      if (match($0, /digest "[^"]*"/)) {
        print substr($0, RSTART + 8, RLENGTH - 9)
        exit
      }
      next
    }
    index($0, coordinate) > 0 { seen = 1 }
  ' "$2"
}

for slot in input:input-schema settlement:settlement-schema reconcile:reconciliation-law
do
  kind=${slot%%:*}
  resource=${slot#*:}
  coordinate="$namespace.$kind@1"
  sidecar="$vendor/$resource.sha256"

  if ! test -f "$sidecar"; then
    echo "resource $resource has no vendored identity sidecar" >&2
    exit 1
  fi
  identity=$(tr -d '[:space:]' <"$sidecar")

  # Only a lowercase 64-character hexadecimal body can name a SHA-256 artifact.
  # A character-blind length check would accept sha256:gggg... as an identity.
  #
  # The character class is written out rather than as the range [!0-9a-f]
  # because a bracket range is resolved by the collating sequence of the
  # current locale. Under en_US.UTF-8 the range a-f collates case-insensitively
  # and admits uppercase, so a range would accept two spellings of one identity.
  case "$identity" in
    sha256:*) body=${identity#sha256:} ;;
    *) body='' ;;
  esac
  case "$body" in
    *[!0123456789abcdef]*) body='' ;;
  esac
  if test "${#body}" -ne 64; then
    echo "resource $resource has a malformed identity digest" >&2
    exit 1
  fi
  case "$identity" in
    *0000000000000000|*1111111111111111|*2222222222222222|*3333333333333333|\
    *4444444444444444|*5555555555555555|*6666666666666666|*7777777777777777|\
    *8888888888888888|*9999999999999999)
      echo "resource $resource still pins a sentinel identity digest" >&2
      exit 1
      ;;
  esac

  declared=$(declared_identity "$coordinate" "$source_file")
  if test -z "$declared"; then
    echo "compiler source declares no digest for $coordinate" >&2
    exit 1
  fi
  if test "$declared" != "$identity"; then
    echo "$coordinate pins $declared but $resource is $identity" >&2
    exit 1
  fi
done
