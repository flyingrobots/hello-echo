#!/bin/sh
set -eu

: "${EDICT_REPO:?set EDICT_REPO to the compatible Edict checkout}"
: "${ECHO_REPO:?set ECHO_REPO to the compatible Echo checkout}"

command -v jq >/dev/null
# The witness binds the reported content digests to the witnessed bytes, which
# needs the same hash the adapter uses.
command -v b3sum >/dev/null
# The binary property cases hash from hex, because a binary body cannot survive
# a shell variable.
command -v xxd >/dev/null

if ! test -x ./tests/patch-build.sh; then
  echo "Hello Effect patch build boundary is not implemented" >&2
  exit 2
fi
if ! test -x ./tests/patch-run.sh; then
  echo "Hello Effect patch runtime boundary is not implemented" >&2
  exit 2
fi

./tests/patch-build.sh

patch_root=.build/patch-tests
rm -rf "$patch_root"
mkdir -p "$patch_root"

core_file=.build/patch/application/core.cbor
target_ir_file=.build/patch/application/target-ir.cbor
expected_core="$EDICT_REPO/fixtures/lawpack/workspace-patch/apply-validated-patch.core.cbor"
expected_target_ir="$EDICT_REPO/fixtures/lawpack/workspace-patch/apply-validated-patch.target-ir.cbor"

test -s "$core_file"
test -s "$target_ir_file"
cmp "$core_file" "$expected_core"
cmp "$target_ir_file" "$expected_target_ir"
test ! -e .build/patch/application/executable-operation-package.cbor
test ! -e .build/patch/application/verification-report.cbor

hex_bytes() {
  printf '%s' "$1" | od -An -tx1 | tr -d ' \n'
}

# The content digest the adapter reports for a given file body.
content_digest() {
  printf '%s' "$1" | b3sum --no-names | tr -d ' \n'
}

# The same, for a body supplied as hex on stdin. A binary body cannot survive a
# shell variable, which is why the property cases carry hex.
hex_digest() {
  xxd -r -p | b3sum --no-names | tr -d ' \n'
}

make_case() {
  case_file=$1
  worldline_byte=$2
  path=$3
  before_hex=$4
  replacement_hex=$5
  permitted_path=$6
  max_settlement_bytes=$7
  jq -n \
    --argjson worldline_byte "$worldline_byte" \
    --arg path "$path" \
    --arg before_hex "$before_hex" \
    --arg replacement_hex "$replacement_hex" \
    --arg permitted_path "$permitted_path" \
    --argjson max_settlement_bytes "$max_settlement_bytes" \
    '{
      worldlineByte: $worldline_byte,
      intent: "applyValidated",
      proposal: {
        path: $path,
        replacementBytesHex: $replacement_hex
      },
      observation: {
        path: $path,
        bytesHex: $before_hex
      },
      permittedPaths: [$permitted_path],
      maxSettlementBytes: $max_settlement_bytes
    }' >"$case_file"
}

run_phase() {
  phase=$1
  case_file=$2
  wal_dir=$3
  report_file=$4
  shift 4
  ./tests/patch-run.sh \
    "$phase" \
    "$case_file" \
    "$wal_dir" \
    "$@" >"$report_file"
}

assert_identity() {
  report_file=$1
  jq -e '
    (.requestId | test("^[0-9a-f]{64}$"))
    and (.compiler.coreDigest | test("^sha256:[0-9a-f]{64}$"))
    and (.compiler.targetIrDigest | test("^sha256:[0-9a-f]{64}$"))
    and .compiler.operation == "workspace.patch.applyValidated@1"
    and .compiler.intent == "applyValidated"
  ' "$report_file" >/dev/null
}

# Writer-epoch assertions are shared by both runtime witnesses and are
# themselves covered by tests/writer-epoch-assertions.sh.
. tests/lib/writer-epoch-assertions.sh

assert_posture() {
  report_file=$1
  phase=$2
  posture=$3
  commits=$4
  jq -e \
    --arg phase "$phase" \
    --arg posture "$posture" \
    --argjson commits "$commits" \
    '.phase == $phase
      and .posture == $posture
      and .wal.commitCount == $commits' \
    "$report_file" >/dev/null
  assert_identity "$report_file"
}

complete_success_case() {
  case_name=$1
  worldline_byte=$2
  before=$3
  replacement=$4
  path=$5
  max_settlement_bytes=$6
  case_root="$patch_root/$case_name"
  workspace_root="$case_root/workspace"
  wal_dir="$case_root/wal"
  case_file="$case_root/request.json"
  mkdir -p "$workspace_root/$(dirname "$path")"
  printf '%s' "$before" >"$workspace_root/$path"
  make_case \
    "$case_file" \
    "$worldline_byte" \
    "$path" \
    "$(hex_bytes "$before")" \
    "$(hex_bytes "$replacement")" \
    "$path" \
    "$max_settlement_bytes"
  run_phase request "$case_file" "$wal_dir" "$case_root/request-report.json"
  run_phase claim "$case_file" "$wal_dir" "$case_root/claim-report.json"
  run_phase apply "$case_file" "$wal_dir" "$case_root/settlement-report.json" "$workspace_root"
  assert_posture "$case_root/request-report.json" request requested 1
  assert_posture "$case_root/claim-report.json" claim claimed 2
  assert_posture "$case_root/settlement-report.json" apply settled 3
  test "$(cat "$workspace_root/$path")" = "$replacement"
  jq -e \
    --arg path "$path" \
    --arg before_digest "$(content_digest "$before")" \
    --arg after_digest "$(content_digest "$replacement")" \
    '.settlement.kind == "succeeded"
      and .settlement.patch.status == "succeeded"
      and .settlement.patch.path == $path
      and .settlement.patch.beforeContentDigest == $before_digest
      and .settlement.patch.afterContentDigest == $after_digest
      and (.settlement.patch.resultingBasis | test("^[0-9a-f]{64}$"))
      and (.settlement.attemptId | test("^[0-9a-f]{64}$"))
      and (.settlement.basisDigest | test("^[0-9a-f]{64}$"))
      and (.settlement.externalEvidenceDigest | test("^[0-9a-f]{64}$"))
      and .settlement.basisDigest == .settlement.patch.requestBasis
      and .settlement.externalEvidenceDigest == .settlement.patch.evidence
      and .settlement.patch.evidence == .settlement.patch.resultingBasis
      and .settlement.patch.obstruction == null
      and (.settlement.commitDigest | test("^[0-9a-f]{64}$"))
      and (.settlement.resultDigest | test("^[0-9a-f]{64}$"))
      and .ordering.requestCommit < .ordering.claimCommit
      and .ordering.claimCommit < .ordering.settlementCommit
      and .publication.settlementCommittedBeforeResult == true' \
    "$case_root/settlement-report.json" >/dev/null
}

# Golden path: proposal data and compiler artifacts are admitted before the
# separately invoked adapter mutates the workspace.
golden_root="$patch_root/golden"
golden_workspace="$golden_root/workspace"
golden_wal="$golden_root/wal"
golden_case="$golden_root/request.json"
golden_path=notes/greeting.txt
golden_before='hello'
golden_replacement='hello from a validated patch'
mkdir -p "$golden_workspace/notes"
printf '%s' "$golden_before" >"$golden_workspace/$golden_path"
make_case \
  "$golden_case" \
  81 \
  "$golden_path" \
  "$(hex_bytes "$golden_before")" \
  "$(hex_bytes "$golden_replacement")" \
  "$golden_path" \
  65536

run_phase request "$golden_case" "$golden_wal" "$golden_root/request-report.json"
assert_posture "$golden_root/request-report.json" request requested 1
test "$(cat "$golden_workspace/$golden_path")" = "$golden_before"

# The first write phase opens the epoch chain on a fresh WAL, and Echo persists
# the ledger and the writer lease that fence it.
assert_first_writer_epoch "$golden_root/request-report.json"
test -s "$golden_wal/writer-epochs.ecwal"
test -e "$golden_wal/writer-epoch.lock"

run_phase inspect "$golden_case" "$golden_wal" "$golden_root/request-recovery.json"
assert_posture "$golden_root/request-recovery.json" inspect requested 1
assert_no_writer_epoch "$golden_root/request-recovery.json"

run_phase claim "$golden_case" "$golden_wal" "$golden_root/claim-report.json"
assert_posture "$golden_root/claim-report.json" claim claimed 2
assert_chained_writer_epoch \
  "$golden_root/claim-report.json" \
  "$golden_root/request-report.json"
test "$(cat "$golden_workspace/$golden_path")" = "$golden_before"

run_phase inspect "$golden_case" "$golden_wal" "$golden_root/claim-recovery.json"
assert_posture "$golden_root/claim-recovery.json" inspect claimed 2
assert_no_writer_epoch "$golden_root/claim-recovery.json"

run_phase \
  apply \
  "$golden_case" \
  "$golden_wal" \
  "$golden_root/settlement-report.json" \
  "$golden_workspace"
golden_settlement="$golden_root/settlement-report.json"
assert_posture "$golden_settlement" apply settled 3
assert_chained_writer_epoch "$golden_settlement" "$golden_root/claim-report.json"
test "$(cat "$golden_workspace/$golden_path")" = "$golden_replacement"

# No writer epoch is reused anywhere in the ordered golden path.
test "$(
  jq -r '.writerEpoch.epochId' \
    "$golden_root/request-report.json" \
    "$golden_root/claim-report.json" \
    "$golden_settlement" |
    sort -u |
    wc -l |
    tr -d ' '
)" = 3

# Retained epoch state must stay bounded across restarts rather than growing
# with each one. A size ceiling checked after a handful of epochs cannot show
# that, because an append-only ledger also fits any ceiling early on. This
# drives many fresh write phases on one WAL, each a separate host process
# taking a new epoch, and requires the ledger to stop changing size.
ledger_root="$patch_root/ledger-plateau"
mkdir -p "$ledger_root/workspace/notes"
printf 'hello' >"$ledger_root/workspace/notes/ledger.txt"
ledger_wal="$ledger_root/wal"
ledger_sizes="$ledger_root/sizes"
: >"$ledger_sizes"
ledger_worldline=100
while test "$ledger_worldline" -lt 116
do
  make_case \
    "$ledger_root/request-$ledger_worldline.json" \
    "$ledger_worldline" \
    notes/ledger.txt \
    "$(hex_bytes hello)" \
    "$(hex_bytes "patched by $ledger_worldline")" \
    notes/ledger.txt \
    65536
  run_phase \
    request \
    "$ledger_root/request-$ledger_worldline.json" \
    "$ledger_wal" \
    "$ledger_root/report-$ledger_worldline.json"
  wc -c <"$ledger_wal/writer-epochs.ecwal" | tr -d ' ' >>"$ledger_sizes"
  ledger_worldline=$((ledger_worldline + 1))
done

# Sixteen distinct epochs were taken on this WAL.
test "$(
  jq -sr '[.[].writerEpoch.epochId] | unique | length' \
    "$ledger_root"/report-*.json
)" = 16

# The final eight observations must all be the same size. An append-only
# ledger would still be growing by then.
ledger_plateau=$(tail -n 8 "$ledger_sizes" | sort -u | wc -l | tr -d ' ')
if test "$ledger_plateau" -ne 1; then
  echo "retained writer-epoch ledger did not stop growing across restarts" >&2
  tail -n 8 "$ledger_sizes" >&2
  exit 1
fi

# Exact retry is effect-free; a conflicting retry obstructs without WAL growth.
run_phase retry "$golden_case" "$golden_wal" "$golden_root/retry-report.json" exact
jq -e '
  .phase == "retry"
  and .retry == "idempotent"
  and .posture == "settled"
  and .writerEpoch == null
  and .wal.commitCountBefore == 3
  and .wal.commitCountAfter == 3
  and .settlement.commitDigest == .retryCommitDigest
' "$golden_root/retry-report.json" >/dev/null

if run_phase \
  retry \
  "$golden_case" \
  "$golden_wal" \
  "$golden_root/conflict-report.json" \
  conflict-kind
then
  echo "conflicting patch settlement retry unexpectedly passed" >&2
  exit 1
fi
jq -e '
  .phase == "retry"
  and .retry == "obstructed"
  and .obstruction == "conflictingSettlement"
  and .writerEpoch == null
  and .wal.commitCountBefore == 3
  and .wal.commitCountAfter == 3
' "$golden_root/conflict-report.json" >/dev/null

# The permitted aperture is part of request identity. A caller cannot broaden
# it after the request and claim are durable.
aperture_root="$patch_root/aperture-substitution"
aperture_workspace="$aperture_root/workspace"
aperture_case="$aperture_root/request.json"
aperture_tampered="$aperture_root/tampered-request.json"
mkdir -p "$aperture_workspace"
printf '%s' secret >"$aperture_workspace/secret.txt"
make_case \
  "$aperture_case" \
  109 \
  secret.txt \
  "$(hex_bytes secret)" \
  "$(hex_bytes replaced)" \
  allowed.txt \
  65536
run_phase request "$aperture_case" "$aperture_root/wal" "$aperture_root/request-report.json"
run_phase claim "$aperture_case" "$aperture_root/wal" "$aperture_root/claim-report.json"
jq '.permittedPaths = ["secret.txt"]' "$aperture_case" >"$aperture_tampered"
if ./tests/patch-run.sh \
  apply \
  "$aperture_tampered" \
  "$aperture_root/wal" \
  "$aperture_workspace" \
  >"$aperture_root/tampered-report.json" \
  2>"$aperture_root/tampered-error.txt"
then
  echo "post-claim patch aperture substitution unexpectedly passed" >&2
  exit 1
fi
test ! -s "$aperture_root/tampered-report.json"
test "$(cat "$aperture_root/tampered-error.txt")" = \
  "claim recovery failed: MissingRequest"
run_phase inspect "$aperture_case" "$aperture_root/wal" "$aperture_root/recovery-report.json"
assert_posture "$aperture_root/recovery-report.json" inspect claimed 2
test "$(cat "$aperture_workspace/secret.txt")" = secret

# Replay accepts no workspace authority and cannot reapply the settled patch.
post_settlement='changed after settlement'
printf '%s' "$post_settlement" >"$golden_workspace/$golden_path"
run_phase replay "$golden_case" "$golden_wal" "$golden_root/replay-report.json"
assert_posture "$golden_root/replay-report.json" replay settled 3
test "$(cat "$golden_workspace/$golden_path")" = "$post_settlement"
jq -e '
  .publication.replayedFromRetainedSettlement == true
  and .settlement.patch.status == "succeeded"
' "$golden_root/replay-report.json" >/dev/null

# A crash after mutation but before settlement is reconciled from the observed
# postcondition. The reconciler does not manufacture a witnessed pre-state.
reconcile_root="$patch_root/reconcile-success"
reconcile_workspace="$reconcile_root/workspace"
reconcile_case="$reconcile_root/request.json"
reconcile_path=src/reconcile.txt
mkdir -p "$reconcile_workspace/src"
printf '%s' before >"$reconcile_workspace/$reconcile_path"
make_case \
  "$reconcile_case" \
  82 \
  "$reconcile_path" \
  "$(hex_bytes before)" \
  "$(hex_bytes after)" \
  "$reconcile_path" \
  65536
run_phase request "$reconcile_case" "$reconcile_root/wal" "$reconcile_root/request-report.json"
run_phase claim "$reconcile_case" "$reconcile_root/wal" "$reconcile_root/claim-report.json"
printf '%s' after >"$reconcile_workspace/$reconcile_path"
run_phase \
  reconcile \
  "$reconcile_case" \
  "$reconcile_root/wal" \
  "$reconcile_root/reconcile-report.json" \
  "$reconcile_workspace"
assert_posture "$reconcile_root/reconcile-report.json" reconcile settled 3
jq -e \
  --arg after_digest "$(content_digest after)" \
  '
  .settlement.kind == "succeeded"
  and .settlement.patch.beforeContentDigest == null
  and .settlement.patch.afterContentDigest == $after_digest
  and .settlement.basisDigest == .settlement.patch.requestBasis
  and .settlement.externalEvidenceDigest == .settlement.patch.evidence
  and .settlement.patch.evidence == .settlement.patch.resultingBasis
' "$reconcile_root/reconcile-report.json" >/dev/null
test "$(cat "$reconcile_workspace/$reconcile_path")" = after

# A crash whose postcondition is neither the requested before nor after state
# settles as outcomeUnknown and preserves the externally observed bytes.
unknown_root="$patch_root/outcome-unknown"
unknown_workspace="$unknown_root/workspace"
unknown_case="$unknown_root/request.json"
mkdir -p "$unknown_workspace"
printf '%s' before >"$unknown_workspace/ambiguous.txt"
make_case \
  "$unknown_case" \
  83 \
  ambiguous.txt \
  "$(hex_bytes before)" \
  "$(hex_bytes intended)" \
  ambiguous.txt \
  65536
run_phase request "$unknown_case" "$unknown_root/wal" "$unknown_root/request-report.json"
run_phase claim "$unknown_case" "$unknown_root/wal" "$unknown_root/claim-report.json"
printf '%s' ambiguous >"$unknown_workspace/ambiguous.txt"
run_phase \
  reconcile \
  "$unknown_case" \
  "$unknown_root/wal" \
  "$unknown_root/reconcile-report.json" \
  "$unknown_workspace"
assert_posture "$unknown_root/reconcile-report.json" reconcile settled 3
jq -e '
  .settlement.kind == "outcomeUnknown"
  and .settlement.patch.status == "outcomeUnknown"
  and .settlement.patch.obstruction == "postcondition-not-observed"
  and (.settlement.attemptId | test("^[0-9a-f]{64}$"))
  and .settlement.basisDigest == .settlement.patch.requestBasis
  and .settlement.externalEvidenceDigest == .settlement.patch.evidence
' "$unknown_root/reconcile-report.json" >/dev/null
test "$(cat "$unknown_workspace/ambiguous.txt")" = ambiguous

# This is the one settlement family where the declared replacement and the
# observed post-state differ: the request asks for one thing and the crash
# leaves another. In every success case those two byte strings are identical,
# so only here can a test tell which of them the retained evidence describes.
#
# Echo derives this evidence by wrapping the observed basis in a further
# domain-separated hash. Recomputing that would rebuild producer logic in the
# consumer. The property is pinned instead: the evidence must vary with the
# observed bytes and must not vary with the declared replacement. A producer
# deriving it from the declared replacement fails the first check; one ignoring
# the observation fails the second.
unknown_evidence_for() {
  probe_root="$patch_root/unknown-evidence-$1"
  probe_workspace="$probe_root/workspace"
  mkdir -p "$probe_workspace"
  printf '%s' before >"$probe_workspace/ambiguous.txt"
  make_case \
    "$probe_root/request.json" \
    "$4" \
    ambiguous.txt \
    "$(hex_bytes before)" \
    "$(hex_bytes "$2")" \
    ambiguous.txt \
    65536
  run_phase request "$probe_root/request.json" "$probe_root/wal" "$probe_root/req.json"
  run_phase claim "$probe_root/request.json" "$probe_root/wal" "$probe_root/clm.json"
  printf '%s' "$3" >"$probe_workspace/ambiguous.txt"
  run_phase \
    reconcile \
    "$probe_root/request.json" \
    "$probe_root/wal" \
    "$probe_root/settle.json" \
    "$probe_workspace"
  jq -e '.settlement.kind == "outcomeUnknown"' "$probe_root/settle.json" >/dev/null
  jq -r '.settlement.patch.evidence' "$probe_root/settle.json"
}

# Same declared replacement, different observed post-states.
evidence_observed_one=$(unknown_evidence_for one intended observedOne 97)
evidence_observed_two=$(unknown_evidence_for two intended observedTwo 98)
test "$evidence_observed_one" != "$evidence_observed_two"

# Different declared replacement, same observed post-state.
evidence_other_request=$(unknown_evidence_for three requested observedOne 99)
test "$evidence_other_request" = "$evidence_observed_one"

# In an outcomeUnknown settlement `beforeContentDigest` carries the digest of
# the bytes that were actually observed, not of the declared pre-state: the
# reconciler has no witnessed pre-state to report, so the field describes what
# it found. Pinning it here records that reading, which the field name alone
# does not convey.
jq -e \
  --arg observed_digest "$(content_digest ambiguous)" \
  --arg declared_digest "$(content_digest before)" \
  '.settlement.patch.beforeContentDigest == $observed_digest
    and .settlement.patch.beforeContentDigest != $declared_digest' \
  "$unknown_root/reconcile-report.json" >/dev/null

assert_rejected_case() {
  case_name=$1
  worldline_byte=$2
  path=$3
  permitted_path=$4
  before=$5
  replacement=$6
  refusal=$7
  setup_kind=$8
  case_root="$patch_root/$case_name"
  workspace_root="$case_root/workspace"
  case_file="$case_root/request.json"
  mkdir -p "$workspace_root/$(dirname "$path" 2>/dev/null || printf '.')"
  case "$setup_kind" in
    regular)
      printf '%s' "$before" >"$workspace_root/$path"
      ;;
    stale)
      printf '%s' changed >"$workspace_root/$path"
      ;;
    symlink)
      printf '%s' outside >"$case_root/outside.txt"
      ln -s "$case_root/outside.txt" "$workspace_root/$path"
      ;;
    absent) ;;
    *)
      echo "unknown patch refusal setup: $setup_kind" >&2
      exit 2
      ;;
  esac
  make_case \
    "$case_file" \
    "$worldline_byte" \
    "$path" \
    "$(hex_bytes "$before")" \
    "$(hex_bytes "$replacement")" \
    "$permitted_path" \
    65536
  run_phase request "$case_file" "$case_root/wal" "$case_root/request-report.json"
  run_phase claim "$case_file" "$case_root/wal" "$case_root/claim-report.json"
  run_phase \
    apply \
    "$case_file" \
    "$case_root/wal" \
    "$case_root/settlement-report.json" \
    "$workspace_root"
  assert_posture "$case_root/settlement-report.json" apply settled 3
  jq -e \
    --arg refusal "$refusal" \
    '.settlement.kind == "rejected"
      and .settlement.patch.status == "rejected"
      and .settlement.patch.obstruction == $refusal
      and .settlement.patch.afterContentDigest == null
      and .settlement.patch.resultingBasis == null' \
    "$case_root/settlement-report.json" >/dev/null
}

# Known failure modes obstruct before mutation.
assert_rejected_case stale-basis 84 stale.txt stale.txt before after stale-basis stale
assert_rejected_case unauthorized 85 secret.txt allowed.txt secret replaced unauthorized-path regular
assert_rejected_case symlink 87 link.txt link.txt before after symlink-refused symlink
assert_rejected_case ci-workflow 88 .github/workflows/ci.yml allowed.txt before after ci-workflow-refused regular

test "$(cat "$patch_root/stale-basis/workspace/stale.txt")" = changed
test "$(cat "$patch_root/unauthorized/workspace/secret.txt")" = secret
test "$(cat "$patch_root/symlink/outside.txt")" = outside
test -L "$patch_root/symlink/workspace/link.txt"
test "$(cat "$patch_root/ci-workflow/workspace/.github/workflows/ci.yml")" = before

# Parent escape is rejected while deterministically validating proposal data,
# before a request can enter the WAL or an adapter can receive authority.
parent_root="$patch_root/parent-escape"
mkdir -p "$parent_root"
make_case \
  "$parent_root/request.json" \
  86 \
  ../secret.txt \
  "$(hex_bytes absent)" \
  "$(hex_bytes replaced)" \
  allowed.txt \
  65536
if run_phase \
  request \
  "$parent_root/request.json" \
  "$parent_root/wal" \
  "$parent_root/request-report.json"
then
  echo "parent-escaped patch proposal unexpectedly passed" >&2
  exit 1
fi
jq -e '
  .phase == "request"
  and .obstruction == "requestRejected"
  and .wal.commitCount == 0
' "$parent_root/request-report.json" >/dev/null

# Model output is closed-schema data. Extra authority-shaped fields cannot be
# smuggled through the proposal and fail before the first WAL commit.
malformed_root="$patch_root/malformed-proposal"
mkdir -p "$malformed_root"
make_case \
  "$malformed_root/request.json" \
  110 \
  source.txt \
  "$(hex_bytes source)" \
  "$(hex_bytes target)" \
  source.txt \
  65536
jq '.proposal.command = "git push --force"' \
  "$malformed_root/request.json" >"$malformed_root/tampered-request.json"
if run_phase \
  request \
  "$malformed_root/tampered-request.json" \
  "$malformed_root/wal" \
  "$malformed_root/request-report.json"
then
  echo "proposal with an undeclared field unexpectedly passed" >&2
  exit 1
fi
jq -e '
  .phase == "request"
  and .obstruction == "requestRejected"
  and .wal.commitCount == 0
' "$malformed_root/request-report.json" >/dev/null

# Replacement-size boundary. The host advertises a 65,536-byte file cap, but
# the encoded patch carries the path, the expected content digest, and canonical
# framing inside the same bounded request carrier, so the reachable replacement
# size is smaller and depends on the path. A replacement the host accepts must
# either be admitted or refused for a stated reason, never accepted here and
# then rejected as an indistinguishable malformed request.
oversize_root="$patch_root/oversize-replacement"
mkdir -p "$oversize_root/workspace/notes"
printf 'hello' >"$oversize_root/workspace/notes/big.txt"
oversize_hex=$(
  awk 'BEGIN { while (i++ < 65536) printf "41" }'
)
make_case \
  "$oversize_root/request.json" \
  93 \
  notes/big.txt \
  "$(hex_bytes hello)" \
  "$oversize_hex" \
  notes/big.txt \
  65536
if run_phase \
  request \
  "$oversize_root/request.json" \
  "$oversize_root/wal" \
  "$oversize_root/report.json"
then
  echo "a replacement above the encodable ceiling was admitted" >&2
  exit 1
fi
# The refusal must name the budget, not masquerade as a malformed request.
jq -e '
  .phase == "request"
  and .obstruction == "replacementExceedsRequestBudget"
  and .wal.commitCount == 0
' "$oversize_root/report.json" >/dev/null
# A refusal must leave the workspace alone, not merely skip the WAL commit.
test "$(cat "$oversize_root/workspace/notes/big.txt")" = hello

# The retained workspace-root evidence must describe the witnessed post-state,
# not merely agree with itself. The three fields the success assertion compares
# (evidence, externalEvidenceDigest, resultingBasis) would all pass if a
# producer replaced them with one arbitrary value.
#
# Echo derives a basis by domain-separated hashing over the path and bytes.
# Recomputing that here would rebuild producer logic in the consumer, which is
# the boundary this witness exists to hold. Instead the host is asked for the
# same value twice by two independent routes: a second patch that declares the
# first patch's post-state as its own observed pre-state derives a request
# basis over those exact bytes, and that must equal the resulting basis the
# first settlement retained.
basis_root="$patch_root/resulting-basis"
basis_workspace="$basis_root/workspace"
basis_path=notes/basis.txt
basis_before='basis before'
basis_after='basis after'
basis_final='basis final'
mkdir -p "$basis_workspace/notes"
printf '%s' "$basis_before" >"$basis_workspace/$basis_path"

make_case \
  "$basis_root/first.json" \
  95 \
  "$basis_path" \
  "$(hex_bytes "$basis_before")" \
  "$(hex_bytes "$basis_after")" \
  "$basis_path" \
  65536
run_phase request "$basis_root/first.json" "$basis_root/wal1" "$basis_root/first-request.json"
run_phase claim "$basis_root/first.json" "$basis_root/wal1" "$basis_root/first-claim.json"
run_phase \
  apply \
  "$basis_root/first.json" \
  "$basis_root/wal1" \
  "$basis_root/first-settlement.json" \
  "$basis_workspace"
assert_posture "$basis_root/first-settlement.json" apply settled 3
test "$(cat "$basis_workspace/$basis_path")" = "$basis_after"

# The workspace now holds the first post-state. The second patch observes it.
make_case \
  "$basis_root/second.json" \
  96 \
  "$basis_path" \
  "$(hex_bytes "$basis_after")" \
  "$(hex_bytes "$basis_final")" \
  "$basis_path" \
  65536
run_phase request "$basis_root/second.json" "$basis_root/wal2" "$basis_root/second-request.json"
run_phase claim "$basis_root/second.json" "$basis_root/wal2" "$basis_root/second-claim.json"
run_phase \
  apply \
  "$basis_root/second.json" \
  "$basis_root/wal2" \
  "$basis_root/second-settlement.json" \
  "$basis_workspace"
assert_posture "$basis_root/second-settlement.json" apply settled 3

# One basis over (path, basis_after), reached two ways.
test "$(
  jq -r '.settlement.patch.requestBasis' "$basis_root/second-settlement.json"
)" = "$(
  jq -r '.settlement.patch.resultingBasis' "$basis_root/first-settlement.json"
)"

# And the two settlements must not share a basis, so the equality above is not
# satisfied by a constant.
test "$(
  jq -r '.settlement.patch.resultingBasis' "$basis_root/second-settlement.json"
)" != "$(
  jq -r '.settlement.patch.resultingBasis' "$basis_root/first-settlement.json"
)"

# An oversized observation is a different fault from an oversized replacement.
# Reporting both as a replacement-budget refusal would name the wrong input.
oversize_before_root="$patch_root/oversize-observation"
mkdir -p "$oversize_before_root/workspace/notes"
printf 'hello' >"$oversize_before_root/workspace/notes/before.txt"
oversize_before_hex=$(
  awk 'BEGIN { while (i++ < 65537) printf "42" }'
)
make_case \
  "$oversize_before_root/request.json" \
  94 \
  notes/before.txt \
  "$oversize_before_hex" \
  "$(hex_bytes small)" \
  notes/before.txt \
  65536
if run_phase \
  request \
  "$oversize_before_root/request.json" \
  "$oversize_before_root/wal" \
  "$oversize_before_root/report.json"
then
  echo "an observation above the file budget was admitted" >&2
  exit 1
fi
jq -e '
  .phase == "request"
  and .obstruction == "observationExceedsFileBudget"
  and .wal.commitCount == 0
' "$oversize_before_root/report.json" >/dev/null
test "$(cat "$oversize_before_root/workspace/notes/before.txt")" = hello

# Settlement-size boundary: the request-only settlement floor (the encoded
# result size, never below the host minimum) succeeds; one byte less refuses
# before mutation.
complete_success_case boundary-probe 89 before boundary exact.txt 65536
boundary_result_bytes=$(
  jq -r '.settlement.canonicalResultByteCount' \
    "$patch_root/boundary-probe/settlement-report.json"
)
case "$boundary_result_bytes" in
  '' | *[!0-9]*)
    echo "settlement report omitted numeric canonicalResultByteCount" >&2
    exit 1
    ;;
esac
boundary_floor=$boundary_result_bytes
if test "$boundary_floor" -lt 1024; then
  boundary_floor=1024
fi
complete_success_case exact-boundary 90 before boundary exact.txt "$boundary_floor"

under_root="$patch_root/under-boundary"
mkdir -p "$under_root/workspace"
printf '%s' before >"$under_root/workspace/exact.txt"
make_case \
  "$under_root/request.json" \
  91 \
  exact.txt \
  "$(hex_bytes before)" \
  "$(hex_bytes boundary)" \
  exact.txt \
  "$((boundary_floor - 1))"
if run_phase \
  request \
  "$under_root/request.json" \
  "$under_root/wal" \
  "$under_root/request-report.json"
then
  echo "under-floor patch request unexpectedly passed" >&2
  exit 1
fi
jq -e '
  .phase == "request"
  and .obstruction == "requestRejected"
  and .wal.commitCount == 0
' "$under_root/request-report.json" >/dev/null
test "$(cat "$under_root/workspace/exact.txt")" = before

# A substituted compiler artifact fails before the first WAL commit, and the
# same substitution after request admission cannot append another fact.
mutated_core="$patch_root/mutated-core.cbor"
cp "$core_file" "$mutated_core"
printf '\000' | dd of="$mutated_core" bs=1 seek=0 conv=notrunc 2>/dev/null
if cmp -s "$core_file" "$mutated_core"; then
  echo "compiler-artifact substitution fixture did not alter the artifact" >&2
  exit 1
fi
mutated_root="$patch_root/mutated-artifact"
mkdir -p "$mutated_root"
make_case \
  "$mutated_root/request.json" \
  92 \
  source.txt \
  "$(hex_bytes source)" \
  "$(hex_bytes target)" \
  source.txt \
  65536
if env PATCH_CORE_FILE="$mutated_core" ./tests/patch-run.sh \
  request \
  "$mutated_root/request.json" \
  "$mutated_root/wal" \
  >"$mutated_root/report.json"
then
  echo "substituted patch compiler artifact unexpectedly passed" >&2
  exit 1
fi
jq -e '
  .phase == "request"
  and .obstruction == "compilerArtifactRejected"
  and .wal.commitCount == 0
' "$mutated_root/report.json" >/dev/null

post_request_root="$patch_root/post-request-mutated-artifact"
mkdir -p "$post_request_root"
make_case \
  "$post_request_root/request.json" \
  93 \
  source.txt \
  "$(hex_bytes source)" \
  "$(hex_bytes target)" \
  source.txt \
  65536
run_phase \
  request \
  "$post_request_root/request.json" \
  "$post_request_root/wal" \
  "$post_request_root/request-report.json"
if env PATCH_CORE_FILE="$mutated_core" ./tests/patch-run.sh \
  claim \
  "$post_request_root/request.json" \
  "$post_request_root/wal" \
  >"$post_request_root/claim-report.json"
then
  echo "post-request patch artifact substitution unexpectedly passed" >&2
  exit 1
fi
jq -e '
  .phase == "claim"
  and .obstruction == "compilerArtifactRejected"
  and .wal.commitCount == 1
' "$post_request_root/claim-report.json" >/dev/null

# Fixed-seed property corpus, including non-text replacement bytes.
property_seed=71111
property_ordinal=0
for replacement_hex in \
  "$(hex_bytes "seed-$property_seed-alpha")" \
  "$(hex_bytes "seed-$property_seed-unicode-Ω")" \
  0001027fff
do
  property_ordinal=$((property_ordinal + 1))
  case_root="$patch_root/property-$property_ordinal"
  mkdir -p "$case_root/workspace"
  printf '%s' before >"$case_root/workspace/value.bin"
  make_case \
    "$case_root/request.json" \
    "$((93 + property_ordinal))" \
    value.bin \
    "$(hex_bytes before)" \
    "$replacement_hex" \
    value.bin \
    65536
  run_phase request "$case_root/request.json" "$case_root/wal" "$case_root/request-report.json"
  run_phase claim "$case_root/request.json" "$case_root/wal" "$case_root/claim-report.json"
  run_phase \
    apply \
    "$case_root/request.json" \
    "$case_root/wal" \
    "$case_root/settlement-report.json" \
    "$case_root/workspace"
  assert_posture "$case_root/settlement-report.json" apply settled 3
  test "$(od -An -tx1 "$case_root/workspace/value.bin" | tr -d ' \n')" = "$replacement_hex"
  # Binary bodies are where a hash that stops at an embedded NUL would still
  # write the right bytes, so the reported digests are bound here too.
  jq -e \
    --arg before_digest "$(printf '%s' "$before_hex" | hex_digest)" \
    --arg after_digest "$(printf '%s' "$replacement_hex" | hex_digest)" \
    '.settlement.patch.beforeContentDigest == $before_digest
      and .settlement.patch.afterContentDigest == $after_digest' \
    "$case_root/settlement-report.json" >/dev/null
done

# Bounded stress: eight isolated request/claim/apply worldlines.
stress_count=8
stress_ordinal=1
while test "$stress_ordinal" -le "$stress_count"; do
  complete_success_case \
    "stress-$stress_ordinal" \
    "$((100 + stress_ordinal))" \
    "before-$stress_ordinal" \
    "after-$stress_ordinal" \
    "stress-$stress_ordinal.txt" \
    65536
  stress_ordinal=$((stress_ordinal + 1))
done

# Retained evidence must not disclose host checkout paths.
edict_repo_root=$(CDPATH='' cd -- "$EDICT_REPO" && pwd -P)
echo_repo_root=$(CDPATH='' cd -- "$ECHO_REPO" && pwd -P)
project_root=$(pwd -P)
set +e
grep -R -F \
  -e "$edict_repo_root" \
  -e "$echo_repo_root" \
  -e "$project_root" \
  --include='*.json' \
  "$patch_root" \
  >/dev/null
leak_status=$?
set -e
if test "$leak_status" -gt 1; then
  echo "Hello Effect patch witness leak check failed to run" >&2
  exit 1
fi
if test "$leak_status" -eq 0; then
  echo "Hello Effect patch witness disclosed a producer checkout path" >&2
  exit 1
fi

printf '%s\n' \
  "Hello Effect patch suite passed: 1 ordered golden, 1 retry, 1 conflict, 1 aperture substitution, 1 replay, 2 reconciliation outcomes, 5 refusals, 1 malformed proposal, 1 boundary probe, 2 boundaries, 2 artifact refusals, 3 fixed-seed property, 8 stress"
