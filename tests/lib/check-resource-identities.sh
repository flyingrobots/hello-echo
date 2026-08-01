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

# Reads the digest one slot declares.
#
# The digest may sit on the coordinate line or on a following line, so this
# searches from the coordinate onward. It stops at the next coordinate or at
# the end of the request declaration, so a slot that declares no digest reports
# nothing rather than silently inheriting the next slot's.
#
# A coordinate must not match inside a longer one: workspace.patch.input@1 is a
# prefix of a hypothetical workspace.patch.input@10, so the character after the
# match may not be a digit.
declared_identity() {
  awk -v coordinate="$1" '
    function digest_in(text,   start) {
      if (match(text, /digest "[^"]*"/)) {
        return substr(text, RSTART + 8, RLENGTH - 9)
      }
      return ""
    }
    function names_slot(line,   at, tail) {
      at = index(line, coordinate)
      if (at == 0) {
        return 0
      }
      tail = substr(line, at + length(coordinate), 1)
      return tail !~ /[0-9]/
    }
    !seen && names_slot($0) {
      seen = 1
      found = digest_in(substr($0, index($0, coordinate) + length(coordinate)))
      if (found != "") {
        print found
        exit
      }
      next
    }
    seen {
      # Another coordinate, or the terminator, ends this declaration.
      if ($0 ~ /@[0-9]+/ || index($0, ";") > 0) {
        found = digest_in($0)
        if (found != "") {
          print found
        }
        exit
      }
      found = digest_in($0)
      if (found != "") {
        print found
        exit
      }
    }
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
  # Read the sidecar as one line, stripping only the trailing line terminator.
  # Deleting all whitespace would silently compact a malformed identity such as
  # "sha256:ab cd..." into a well-formed one and accept it.
  # read returns non-zero on a final line with no terminator, which set -e
  # would treat as a failure, so its status is discarded and the value printed
  # unconditionally.
  identity=$(IFS= read -r line <"$sidecar" || true; printf '%s' "$line")
  # A sidecar carrying more than one line is not a canonical identity either.
  if test "$(wc -l <"$sidecar" | tr -d ' ')" -gt 1; then
    echo "resource $resource has a multi-line identity sidecar" >&2
    exit 1
  fi

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
  # A sentinel is a placeholder character repeated to fill the field. Detect it
  # structurally, by removing every occurrence of the first character and
  # asking whether anything is left, rather than by enumerating the fills seen
  # so far: the patch closure used all-9/8/7 and the observation closure used
  # all-b/c/d, so any enumeration is a list of yesterday's placeholders.
  #
  # This cannot tell a placeholder from a genuine digest that happens to be
  # uniform, and would reject one. Sixteen of the 2^256 possible digests are
  # uniform, so that is a probability near 10^-76, against a producer
  # regression to placeholders that has already happened twice. If it ever does
  # fire on real generator output, regenerating the artifact resolves it.
  # Recomputing the identity locally is not an option: it is a canonical
  # resource identity owned by the generator, not a hash of the file bytes.
  first=${body%"${body#?}"}
  if test -z "$(printf '%s' "$body" | tr -d "$first")"; then
    echo "resource $resource still pins a sentinel identity digest" >&2
    exit 1
  fi

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
