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

# A sidecar whose identity is the right shape and length but not hexadecimal.
# Only 0-9a-f can name a SHA-256 artifact, so anything else is not an identity.
write_vendor "$work/nonhex" \
  sha256:gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg \
  "$good_settlement" "$good_reconcile"
write_source "$work/nonhex.edict" \
  sha256:gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg \
  "$good_settlement" "$good_reconcile"
expect_reject "$work/nonhex" "$work/nonhex.edict" "non-hexadecimal identity"

# Uppercase is not the canonical form the generator emits, so accepting it
# would let two spellings of one identity both pass.
upper=sha256:111111111111111111111111111111111111111111111111111111111111111A
write_vendor "$work/upper" "$upper" "$good_settlement" "$good_reconcile"
write_source "$work/upper.edict" "$upper" "$good_settlement" "$good_reconcile"
expect_reject "$work/upper" "$work/upper.edict" "uppercase hexadecimal identity"

# A truncated identity must not be accepted by a length-blind check.
write_vendor "$work/short" sha256:abc "$good_settlement" "$good_reconcile"
write_source "$work/short.edict" sha256:abc "$good_settlement" "$good_reconcile"
expect_reject "$work/short" "$work/short.edict" "truncated identity"

# Sentinel identities: a placeholder repeated to fill the field. The generator
# emitted all-9/8/7 for the patch closure and all-b/c/d for the observation
# closure before Edict owned real artifacts, so both digit and letter fills
# must be caught rather than an enumerated list of the ones already seen.
for fill in 0 7 8 9 a b c d e f
do
  sentinel="sha256:$(
    i=0
    while test "$i" -lt 64; do printf '%s' "$fill"; i=$((i + 1)); done
  )"
  write_vendor "$work/sentinel" "$sentinel" "$good_settlement" "$good_reconcile"
  write_source "$work/sentinel.edict" "$sentinel" "$good_settlement" "$good_reconcile"
  expect_reject "$work/sentinel" "$work/sentinel.edict" "sentinel identity of all $fill"
done

# A slot may carry its digest on the coordinate line. The guard must read that
# slot's own digest rather than skipping past it and taking the next slot's,
# which would reject a valid closure with a misleading mismatch.
cat >"$work/inline.edict" <<EOF
intent applyValidated(input: ApplyPatchInput)
{
  request pending: ExternalActionRequest<Bytes<max=65536>> =
    patch(input.patch)
    input schema workspace.patch.input@1 digest "$good_input"
    settlement schema workspace.patch.settlement@1 digest "$good_settlement"
    reconcile workspace.patch.reconcile@1 digest "$good_reconcile";
  return pending;
}
EOF
expect_accept "$work/good" "$work/inline.edict" "digests on the coordinate lines"

# A slot that declares no digest at all must fail, not silently inherit the
# next slot's digest.
cat >"$work/missing.edict" <<EOF
intent applyValidated(input: ApplyPatchInput)
{
  request pending: ExternalActionRequest<Bytes<max=65536>> =
    patch(input.patch)
    input schema workspace.patch.input@1
    settlement schema workspace.patch.settlement@1
      digest "$good_settlement"
    reconcile workspace.patch.reconcile@1
      digest "$good_reconcile";
  return pending;
}
EOF
expect_reject "$work/good" "$work/missing.edict" "input slot declares no digest"

# A sidecar carrying whitespace inside the identity is not a canonical
# identity. Normalizing it away before validation would accept malformed
# generator output whenever the source happens to carry the compacted value.
mkdir -p "$work/spaced"
printf 'sha256:1111111111111111111111111111111111111111 111111111111111111111112\n' \
  >"$work/spaced/input-schema.sha256"
printf '%s\n' "$good_settlement" >"$work/spaced/settlement-schema.sha256"
printf '%s\n' "$good_reconcile" >"$work/spaced/reconciliation-law.sha256"
write_source "$work/spaced.edict" "$good_input" "$good_settlement" "$good_reconcile"
expect_reject "$work/spaced" "$work/spaced.edict" "whitespace inside the sidecar identity"

# A sidecar carrying a second identity is not canonical. Counting newlines is
# not enough to see this: a two-line file whose final line has no terminator
# contains one newline character, so a line count reports it as single-line.
mkdir -p "$work/twoline"
printf '%s\n%s' "$good_input" \
  sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef \
  >"$work/twoline/input-schema.sha256"
printf '%s\n' "$good_settlement" >"$work/twoline/settlement-schema.sha256"
printf '%s\n' "$good_reconcile" >"$work/twoline/reconciliation-law.sha256"
write_source "$work/twoline.edict" "$good_input" "$good_settlement" "$good_reconcile"
expect_reject "$work/twoline" "$work/twoline.edict" "sidecar carrying a second identity"

# The same, with the trailing terminator present.
mkdir -p "$work/twoline2"
printf '%s\n%s\n' "$good_input" \
  sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef \
  >"$work/twoline2/input-schema.sha256"
printf '%s\n' "$good_settlement" >"$work/twoline2/settlement-schema.sha256"
printf '%s\n' "$good_reconcile" >"$work/twoline2/reconciliation-law.sha256"
write_source "$work/twoline2.edict" "$good_input" "$good_settlement" "$good_reconcile"
expect_reject "$work/twoline2" "$work/twoline2.edict" "sidecar with a terminated second identity"

# Trailing content that is not a whole line must also fail.
mkdir -p "$work/trailing"
printf '%s\n \n' "$good_input" >"$work/trailing/input-schema.sha256"
printf '%s\n' "$good_settlement" >"$work/trailing/settlement-schema.sha256"
printf '%s\n' "$good_reconcile" >"$work/trailing/reconciliation-law.sha256"
write_source "$work/trailing.edict" "$good_input" "$good_settlement" "$good_reconcile"
expect_reject "$work/trailing" "$work/trailing.edict" "sidecar with trailing content"

# A trailing newline is the one permitted terminator and must still be accepted.
mkdir -p "$work/nonewline"
printf '%s' "$good_input" >"$work/nonewline/input-schema.sha256"
printf '%s\n' "$good_settlement" >"$work/nonewline/settlement-schema.sha256"
printf '%s\n' "$good_reconcile" >"$work/nonewline/reconciliation-law.sha256"
write_source "$work/nonewline.edict" "$good_input" "$good_settlement" "$good_reconcile"
expect_accept "$work/nonewline" "$work/nonewline.edict" "sidecar without a trailing newline"

# A vendor directory missing a sidecar entirely must fail. Without a case the
# guard's dedicated branch for it is an unproven claim, which is the thing this
# file exists to prevent.
mkdir -p "$work/nosidecar"
printf '%s\n' "$good_settlement" >"$work/nosidecar/settlement-schema.sha256"
printf '%s\n' "$good_reconcile" >"$work/nosidecar/reconciliation-law.sha256"
write_source "$work/nosidecar.edict" "$good_input" "$good_settlement" "$good_reconcile"
expect_reject "$work/nosidecar" "$work/nosidecar.edict" "vendor directory missing a sidecar"

# An empty sidecar is present but names nothing.
mkdir -p "$work/emptysidecar"
: >"$work/emptysidecar/input-schema.sha256"
printf '%s\n' "$good_settlement" >"$work/emptysidecar/settlement-schema.sha256"
printf '%s\n' "$good_reconcile" >"$work/emptysidecar/reconciliation-law.sha256"
write_source "$work/emptysidecar.edict" "$good_input" "$good_settlement" "$good_reconcile"
expect_reject "$work/emptysidecar" "$work/emptysidecar.edict" "empty identity sidecar"

# A NUL byte is not a line terminator. The shell drops it from the value read,
# so a byte count alone reads the file as identity-plus-terminator.
mkdir -p "$work/nul"
printf '%s\0' "$good_input" >"$work/nul/input-schema.sha256"
printf '%s\n' "$good_settlement" >"$work/nul/settlement-schema.sha256"
printf '%s\n' "$good_reconcile" >"$work/nul/reconciliation-law.sha256"
write_source "$work/nul.edict" "$good_input" "$good_settlement" "$good_reconcile"
expect_reject "$work/nul" "$work/nul.edict" "sidecar terminated by a NUL byte"

# A slot with no digest whose successor declares one inline must not adopt it.
# Sharing an identity between two resources makes the substitution invisible to
# a comparison that only checks the value it found.
mkdir -p "$work/adopt"
printf '%s\n' "$good_input" >"$work/adopt/input-schema.sha256"
printf '%s\n' "$good_input" >"$work/adopt/settlement-schema.sha256"
printf '%s\n' "$good_reconcile" >"$work/adopt/reconciliation-law.sha256"
cat >"$work/adopt.edict" <<EOF
intent applyValidated(input: ApplyPatchInput)
{
    input schema workspace.patch.input@1
    settlement schema workspace.patch.settlement@1 digest "$good_input"
    reconcile workspace.patch.reconcile@1
      digest "$good_reconcile";
}
EOF
expect_reject "$work/adopt" "$work/adopt.edict" "slot adopting its successor's inline digest"

# A commented coordinate is not a declaration. If it were treated as one it
# would shadow the live slot below it, and a cross-wired live slot would pass.
cat >"$work/comment.edict" <<EOF
intent applyValidated(input: ApplyPatchInput)
{
    // workspace.patch.input@1 digest "$good_input"
    input schema workspace.patch.input@1
      digest "$good_settlement"
    settlement schema workspace.patch.settlement@1
      digest "$good_settlement"
    reconcile workspace.patch.reconcile@1
      digest "$good_reconcile";
}
EOF
expect_reject "$work/good" "$work/comment.edict" "commented coordinate shadowing a cross-wired slot"

# The same comment above a correctly wired slot must still be accepted.
cat >"$work/comment-ok.edict" <<EOF
intent applyValidated(input: ApplyPatchInput)
{
    // workspace.patch.input@1 digest "$good_settlement"
    input schema workspace.patch.input@1
      digest "$good_input"
    settlement schema workspace.patch.settlement@1
      digest "$good_settlement"
    reconcile workspace.patch.reconcile@1
      digest "$good_reconcile";
}
EOF
expect_accept "$work/good" "$work/comment-ok.edict" "comment above a correctly wired slot"

# A coordinate outside its own clause does not declare the slot.
cat >"$work/bareword.edict" <<EOF
intent applyValidated(input: ApplyPatchInput)
{
    requires workspace.patch.input@1
      digest "$good_settlement"
    input schema workspace.patch.input@1
      digest "$good_input"
    settlement schema workspace.patch.settlement@1
      digest "$good_settlement"
    reconcile workspace.patch.reconcile@1
      digest "$good_reconcile";
}
EOF
expect_accept "$work/good" "$work/bareword.edict" "coordinate outside its clause is not the slot"

# Two clauses packed onto one line. The successor's digest must not satisfy the
# slot that declares none, even when both resources share an identity, which is
# what makes the substitution invisible to a value comparison.
mkdir -p "$work/oneline"
printf '%s\n' "$good_input" >"$work/oneline/input-schema.sha256"
printf '%s\n' "$good_input" >"$work/oneline/settlement-schema.sha256"
printf '%s\n' "$good_reconcile" >"$work/oneline/reconciliation-law.sha256"
cat >"$work/oneline.edict" <<EOF
intent applyValidated(input: ApplyPatchInput)
{
    input schema workspace.patch.input@1 settlement schema workspace.patch.settlement@1 digest "$good_input"
    reconcile workspace.patch.reconcile@1
      digest "$good_reconcile";
}
EOF
expect_reject "$work/oneline" "$work/oneline.edict" "two clauses on one line donating a digest"

echo "resource identity guard: all cases passed"
