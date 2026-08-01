#!/bin/sh
set -eu

# Hermetic test of tests/lib/check-resource-identities.sh.
#
# The build boundaries trust that guard to prove every external-action schema
# identity in a compiler source resolves to the vendored artifact it names. A
# guard that has never been shown to reject a bad input proves nothing, so this
# exercises it against crafted closures.
#
# No producer checkout, no network, and no cargo: this runs anywhere.

guard=tests/lib/check-resource-identities.sh
test -x "$guard"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

good_input=sha256:1111111111111111111111111111111111111111111111111111111111111112
good_settlement=sha256:2222222222222222222222222222222222222222222222222222222222222223
good_reconcile=sha256:3333333333333333333333333333333333333333333333333333333333333334

# Writes a vendor directory whose sidecars carry the three given identities.
write_vendor() {
  vendor=$1
  mkdir -p "$vendor"
  printf '%s\n' "$2" >"$vendor/input-schema.sha256"
  printf '%s\n' "$3" >"$vendor/settlement-schema.sha256"
  printf '%s\n' "$4" >"$vendor/reconciliation-law.sha256"
}

# Writes a compiler source that pins the three given identities to the input,
# settlement, and reconcile slots in that order.
write_source() {
  source_file=$1
  cat >"$source_file" <<EOF
intent applyValidated(input: ApplyPatchInput)
{
  request pending: ExternalActionRequest<Bytes<max=65536>> =
    patch(input.patch)
    input schema workspace.patch.input@1
      digest "$2"
    settlement schema workspace.patch.settlement@1
      digest "$3"
    authority input.authority
    basis input.basis
    reconcile workspace.patch.reconcile@1
      digest "$4";
  return pending;
}
EOF
}

passes() {
  "$guard" workspace.patch "$1" "$2" >/dev/null 2>&1
}

expect_accept() {
  if passes "$1" "$2"; then
    printf 'ok   accepted: %s\n' "$3"
  else
    printf 'FAIL rejected a valid closure: %s\n' "$3" >&2
    exit 1
  fi
}

expect_reject() {
  if passes "$1" "$2"; then
    printf 'FAIL accepted an invalid closure: %s\n' "$3" >&2
    exit 1
  else
    printf 'ok   rejected: %s\n' "$3"
  fi
}

# Control: a closure whose every slot names its own vendored artifact.
write_vendor "$work/good" "$good_input" "$good_settlement" "$good_reconcile"
write_source "$work/good.edict" "$good_input" "$good_settlement" "$good_reconcile"
expect_accept "$work/good" "$work/good.edict" "matching identities"

# Cross-wiring: every identity is present in the source and every one resolves
# to a real vendored artifact, but the input and settlement slots are swapped.
# A guard that only asks whether a digest appears somewhere in the file cannot
# see this.
write_source "$work/crosswired.edict" \
  "$good_settlement" "$good_input" "$good_reconcile"
expect_reject "$work/good" "$work/crosswired.edict" "input and settlement slots swapped"

# Rotation across all three slots, so no slot keeps its own identity.
write_source "$work/rotated.edict" \
  "$good_settlement" "$good_reconcile" "$good_input"
expect_reject "$work/good" "$work/rotated.edict" "all three slots rotated"

# A slot pinned to a digest that names no vendored artifact at all.
write_source "$work/foreign.edict" \
  "$good_input" \
  sha256:4444444444444444444444444444444444444444444444444444444444444445 \
  "$good_reconcile"
expect_reject "$work/good" "$work/foreign.edict" "settlement slot pins a foreign identity"

echo "resource identity guard: all cases passed"
