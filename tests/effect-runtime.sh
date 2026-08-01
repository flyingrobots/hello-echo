#!/bin/sh
set -eu

: "${EDICT_REPO:?set EDICT_REPO to the compatible Edict checkout}"
: "${ECHO_REPO:?set ECHO_REPO to the compatible Echo checkout}"

command -v jq >/dev/null

if ! test -x ./tests/effect-build.sh; then
  echo "Hello Effect build boundary is not implemented" >&2
  exit 2
fi
if ! test -x ./tests/effect-run.sh; then
  echo "Hello Effect runtime boundary is not implemented" >&2
  exit 2
fi

./tests/effect-build.sh

effect_root=.build/effect-tests
rm -rf "$effect_root"
mkdir -p "$effect_root"

# Producer checkout paths may be relative at the public shell boundary. The
# generated Cargo manifest must contain their canonical targets, not paths that
# Cargo would reinterpret relative to the nested build directory.
relative_repo_links="$effect_root/relative-repos"
mkdir -p "$relative_repo_links"
ln -s "$EDICT_REPO" "$relative_repo_links/edict"
ln -s "$ECHO_REPO" "$relative_repo_links/echo"
EDICT_REPO="$relative_repo_links/edict" \
ECHO_REPO="$relative_repo_links/echo" \
./tests/effect-build.sh
rm -rf "$relative_repo_links"

core_file=.build/effect/application/core.cbor
target_ir_file=.build/effect/application/target-ir.cbor
expected_core="$EDICT_REPO/fixtures/lawpack/workspace-snapshot/observe-workspace.core.cbor"
expected_target_ir="$EDICT_REPO/fixtures/lawpack/workspace-snapshot/observe-workspace.target-ir.cbor"

test -s "$core_file"
test -s "$target_ir_file"
cmp "$core_file" "$expected_core"
cmp "$target_ir_file" "$expected_target_ir"
test ! -e .build/effect/application/executable-operation-package.cbor
test ! -e .build/effect/application/verification-report.cbor

hex_bytes() {
  printf '%s' "$1" | od -An -tx1 | tr -d ' \n'
}

make_case() {
  case_file=$1
  worldline_byte=$2
  requested_path=$3
  expected_bytes_hex=$4
  max_settlement_bytes=$5
  permitted_path=$6
  jq -n \
    --argjson worldline_byte "$worldline_byte" \
    --arg requested_path "$requested_path" \
    --arg expected_bytes_hex "$expected_bytes_hex" \
    --argjson max_settlement_bytes "$max_settlement_bytes" \
    --arg permitted_path "$permitted_path" \
    '{
      worldlineByte: $worldline_byte,
      intent: "observe",
      scope: ("scope-" + ($worldline_byte | tostring)),
      requestedPaths: [$requested_path],
      expectedFiles: [{
        path: $requested_path,
        bytesHex: $expected_bytes_hex
      }],
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
  ./tests/effect-run.sh \
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
    and .compiler.operation == "workspace.snapshot.observe@1"
    and .compiler.intent == "observe"
  ' "$report_file" >/dev/null
}

# A write phase must run under a fresh Echo-derived writer epoch. Hello Echo
# supplies no epoch identity, so the reported epoch proves the producer chained
# it to the persisted predecessor rather than reusing a static fencing identity
# across host restarts.
assert_first_writer_epoch() {
  report_file=$1
  jq -e '
    (.writerEpoch.epochId | test("^[0-9a-f]{64}$"))
    and .writerEpoch.previousEpochId == null
    and .writerEpoch.previousEpochFinalCommitDigest == null
    and .writerEpoch.startedAtLsn == 0
  ' "$report_file" >/dev/null
}

# Each later write phase is a separate host process. Its epoch must be new and
# must name the previous epoch and that epoch's final commit digest.
assert_chained_writer_epoch() {
  report_file=$1
  previous_report=$2
  jq -e \
    --slurpfile previous "$previous_report" \
    '
      (.writerEpoch.epochId | test("^[0-9a-f]{64}$"))
      and (.writerEpoch.previousEpochFinalCommitDigest | test("^[0-9a-f]{64}$"))
      and .writerEpoch.epochId != $previous[0].writerEpoch.epochId
      and .writerEpoch.previousEpochId == $previous[0].writerEpoch.epochId
      and .writerEpoch.startedAtLsn > $previous[0].writerEpoch.startedAtLsn
    ' \
    "$report_file" >/dev/null
}

# Read-only phases take no writer lease and therefore acquire no epoch.
assert_no_writer_epoch() {
  report_file=$1
  jq -e '.writerEpoch == null' "$report_file" >/dev/null
}

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
  value=$3
  requested_path=$4
  max_settlement_bytes=$5
  case_root="$effect_root/$case_name"
  workspace_root="$case_root/workspace"
  wal_dir="$case_root/wal"
  case_file="$case_root/request.json"
  mkdir -p "$workspace_root/$(dirname "$requested_path")"
  printf '%s' "$value" >"$workspace_root/$requested_path"
  make_case \
    "$case_file" \
    "$worldline_byte" \
    "$requested_path" \
    "$(hex_bytes "$value")" \
    "$max_settlement_bytes" \
    "$requested_path"
  run_phase request "$case_file" "$wal_dir" "$case_root/request-report.json"
  run_phase claim "$case_file" "$wal_dir" "$case_root/claim-report.json"
  run_phase \
    settle \
    "$case_file" \
    "$wal_dir" \
    "$case_root/settlement-report.json" \
    "$workspace_root"
  assert_posture "$case_root/request-report.json" request requested 1
  assert_posture "$case_root/claim-report.json" claim claimed 2
  assert_posture "$case_root/settlement-report.json" settle settled 3
  jq -e \
    --arg requested_path "$requested_path" \
    --arg expected_bytes_hex "$(hex_bytes "$value")" \
    '.settlement.kind == "succeeded"
      and .settlement.observation.status == "succeeded"
      and .settlement.observation.files == [{
        path: $requested_path,
        bytesHex: $expected_bytes_hex
      }]
      and (.settlement.commitDigest | test("^[0-9a-f]{64}$"))
      and (.settlement.resultDigest | test("^[0-9a-f]{64}$"))' \
    "$case_root/settlement-report.json" >/dev/null
}

# Golden path. The target file is absent while request and claim are durably
# recorded; it becomes readable only before the separately invoked settlement
# process.
golden_root="$effect_root/golden"
golden_workspace="$golden_root/workspace"
golden_wal="$golden_root/wal"
golden_case="$golden_root/request.json"
golden_path=notes/evidence.txt
golden_value='observed value A'
mkdir -p "$golden_workspace/notes"
make_case \
  "$golden_case" \
  41 \
  "$golden_path" \
  "$(hex_bytes "$golden_value")" \
  65536 \
  "$golden_path"

run_phase request "$golden_case" "$golden_wal" "$golden_root/request-report.json"
assert_posture "$golden_root/request-report.json" request requested 1
test ! -e "$golden_workspace/$golden_path"

# The first write phase opens the epoch chain on a fresh WAL, and Echo persists
# the ledger and the writer lease that fence it.
assert_first_writer_epoch "$golden_root/request-report.json"
test -s "$golden_wal/writer-epochs.ecwal"
test -e "$golden_wal/writer-epoch.lock"

project_root=$(pwd -P)
(
  cd "$effect_root"
  EFFECT_CORE_FILE=.build/effect/application/core.cbor \
    EFFECT_TARGET_IR_FILE=.build/effect/application/target-ir.cbor \
    "$project_root/tests/effect-run.sh" \
    inspect \
    .build/effect-tests/golden/request.json \
    .build/effect-tests/golden/wal \
    >"$project_root/$golden_root/relative-artifact-report.json"
)
assert_posture "$golden_root/relative-artifact-report.json" inspect requested 1

run_phase inspect "$golden_case" "$golden_wal" "$golden_root/request-recovery.json"
assert_posture "$golden_root/request-recovery.json" inspect requested 1
assert_no_writer_epoch "$golden_root/request-recovery.json"

run_phase claim "$golden_case" "$golden_wal" "$golden_root/claim-report.json"
assert_posture "$golden_root/claim-report.json" claim claimed 2
assert_chained_writer_epoch \
  "$golden_root/claim-report.json" \
  "$golden_root/request-report.json"
test ! -e "$golden_workspace/$golden_path"

run_phase inspect "$golden_case" "$golden_wal" "$golden_root/claim-recovery.json"
assert_posture "$golden_root/claim-recovery.json" inspect claimed 2
assert_no_writer_epoch "$golden_root/claim-recovery.json"

printf '%s' "$golden_value" >"$golden_workspace/$golden_path"
run_phase \
  settle \
  "$golden_case" \
  "$golden_wal" \
  "$golden_root/settlement-report.json" \
  "$golden_workspace"
golden_settlement="$golden_root/settlement-report.json"
assert_posture "$golden_settlement" settle settled 3
assert_chained_writer_epoch "$golden_settlement" "$golden_root/claim-report.json"

# No writer epoch is reused anywhere in the ordered golden path, and the
# retained ledger stays bounded rather than growing per restart.
test "$(
  jq -r '.writerEpoch.epochId' \
    "$golden_root/request-report.json" \
    "$golden_root/claim-report.json" \
    "$golden_settlement" |
    sort -u |
    wc -l |
    tr -d ' '
)" = 3
test "$(wc -c <"$golden_wal/writer-epochs.ecwal" | tr -d ' ')" -le 4096

jq -e \
  --arg path "$golden_path" \
  --arg bytes_hex "$(hex_bytes "$golden_value")" \
  '.settlement.kind == "succeeded"
    and .settlement.observation.status == "succeeded"
    and .settlement.observation.files == [{
      path: $path,
      bytesHex: $bytes_hex
    }]
    and .ordering.requestCommit < .ordering.claimCommit
    and .ordering.claimCommit < .ordering.settlementCommit
    and .publication.settlementCommittedBeforeResult == true' \
  "$golden_settlement" >/dev/null

# A retained exact candidate reconciles to the original fact without WAL
# growth; a valid kind-only mutation obstructs without another commit.
run_phase retry "$golden_case" "$golden_wal" "$golden_root/retry-report.json" exact
jq -e '
  .phase == "retry"
  and .retry == "idempotent"
  and .posture == "settled"
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
  echo "conflicting settlement retry unexpectedly passed" >&2
  exit 1
fi
jq -e '
  .phase == "retry"
  and .retry == "obstructed"
  and .obstruction == "conflictingSettlement"
  and .wal.commitCountBefore == 3
  and .wal.commitCountAfter == 3
' "$golden_root/conflict-report.json" >/dev/null

# The runtime-owned permitted aperture is bound into the durable request. A
# caller cannot broaden it between claim recovery and adapter construction.
aperture_root="$effect_root/aperture-substitution"
aperture_case="$aperture_root/request.json"
aperture_tampered="$aperture_root/tampered-request.json"
aperture_path=secret.txt
mkdir -p "$aperture_root/workspace"
printf '%s' 'secret' >"$aperture_root/workspace/$aperture_path"
make_case \
  "$aperture_case" \
  71 \
  "$aperture_path" \
  "$(hex_bytes 'secret')" \
  65536 \
  allowed.txt
run_phase \
  request \
  "$aperture_case" \
  "$aperture_root/wal" \
  "$aperture_root/request-report.json"
run_phase \
  claim \
  "$aperture_case" \
  "$aperture_root/wal" \
  "$aperture_root/claim-report.json"
jq --arg path "$aperture_path" '.permittedPaths = [$path]' \
  "$aperture_case" >"$aperture_tampered"
if run_phase \
  settle \
  "$aperture_tampered" \
  "$aperture_root/wal" \
  "$aperture_root/tampered-report.json" \
  "$aperture_root/workspace"
then
  echo "post-claim aperture substitution unexpectedly passed" >&2
  exit 1
fi
run_phase \
  inspect \
  "$aperture_case" \
  "$aperture_root/wal" \
  "$aperture_root/recovery-report.json"
assert_posture "$aperture_root/recovery-report.json" inspect claimed 2

# Replay accepts no workspace-root argument. Removing the complete root makes
# accidental adapter re-entry impossible while the retained value remains A.
mv "$golden_workspace" "$golden_root/world-after-settlement"
run_phase replay "$golden_case" "$golden_wal" "$golden_root/replay-report.json"
assert_posture "$golden_root/replay-report.json" replay settled 3
jq -e \
  --arg bytes_hex "$(hex_bytes "$golden_value")" \
  '.settlement.observation.files[0].bytesHex == $bytes_hex
    and .publication.replayedFromRetainedSettlement == true' \
  "$golden_root/replay-report.json" >/dev/null

# A fresh request on another worldline observes the changed world B.
fresh_value='observed value B'
complete_success_case fresh-world 42 "$fresh_value" "$golden_path" 65536
fresh_settlement="$effect_root/fresh-world/settlement-report.json"
jq -e \
  --arg bytes_hex "$(hex_bytes "$fresh_value")" \
  --arg golden_request "$(jq -r '.requestId' "$golden_settlement")" \
  '.requestId != $golden_request
    and .settlement.observation.files[0].bytesHex == $bytes_hex' \
  "$fresh_settlement" >/dev/null

# Explicit ambiguity is retained as outcomeUnknown rather than collapsed to
# failed, and recovers without inventing a file result.
unknown_root="$effect_root/outcome-unknown"
unknown_case="$unknown_root/request.json"
mkdir -p "$unknown_root/workspace"
make_case \
  "$unknown_case" \
  43 \
  ambiguous.txt \
  "$(hex_bytes 'not observed')" \
  65536 \
  ambiguous.txt
run_phase request "$unknown_case" "$unknown_root/wal" "$unknown_root/request-report.json"
run_phase claim "$unknown_case" "$unknown_root/wal" "$unknown_root/claim-report.json"
rm -rf "$unknown_root/workspace"
run_phase \
  unknown \
  "$unknown_case" \
  "$unknown_root/wal" \
  "$unknown_root/unknown-report.json"
assert_posture "$unknown_root/unknown-report.json" unknown settled 3
jq -e '
  .settlement.kind == "outcomeUnknown"
  and .settlement.observation.status == "outcomeUnknown"
  and .settlement.observation.files == []
' "$unknown_root/unknown-report.json" >/dev/null
run_phase replay "$unknown_case" "$unknown_root/wal" "$unknown_root/replay-report.json"
jq -e '.settlement.kind == "outcomeUnknown"' \
  "$unknown_root/replay-report.json" >/dev/null

assert_rejected_case() {
  case_name=$1
  worldline_byte=$2
  requested_path=$3
  permitted_path=$4
  refusal=$5
  setup_kind=$6
  case_root="$effect_root/$case_name"
  workspace_root="$case_root/workspace"
  case_file="$case_root/request.json"
  mkdir -p "$workspace_root"
  case "$setup_kind" in
    symlink)
      printf '%s' 'outside' >"$case_root/outside.txt"
      ln -s "$case_root/outside.txt" "$workspace_root/$requested_path"
      ;;
    regular)
      printf '%s' 'secret' >"$workspace_root/$requested_path"
      ;;
    stale)
      printf '%s' 'changed after request' >"$workspace_root/$requested_path"
      ;;
    absent) ;;
    *)
      echo "unknown rejected-case setup: $setup_kind" >&2
      exit 2
      ;;
  esac
  make_case \
    "$case_file" \
    "$worldline_byte" \
    "$requested_path" \
    "$(hex_bytes 'secret')" \
    65536 \
    "$permitted_path"
  run_phase request "$case_file" "$case_root/wal" "$case_root/request-report.json"
  run_phase claim "$case_file" "$case_root/wal" "$case_root/claim-report.json"
  run_phase \
    settle \
    "$case_file" \
    "$case_root/wal" \
    "$case_root/settlement-report.json" \
    "$workspace_root"
  assert_posture "$case_root/settlement-report.json" settle settled 3
  jq -e \
    --arg refusal "$refusal" \
    '.settlement.kind == "rejected"
      and .settlement.observation.status == "rejected"
      and .settlement.observation.refusal == $refusal
      and .settlement.observation.files == []' \
    "$case_root/settlement-report.json" >/dev/null
}

# Known failures: unauthorized, parent-escaped, and symlink paths obstruct
# without exposing target bytes.
assert_rejected_case unauthorized 44 secret.txt allowed.txt unauthorized-path regular
assert_rejected_case parent-escape 45 ../secret.txt allowed.txt invalid-path absent
assert_rejected_case symlink 46 link.txt link.txt symlink-refused symlink
assert_rejected_case stale-basis 70 stale.txt stale.txt stale-basis stale

# Boundary: first observe the exact encoding size for this path and value, then
# prove that exact bound passes while one byte less produces a typed rejection.
complete_success_case boundary-probe 47 boundary exact.txt 65536
boundary_result_bytes=$(
  jq -r \
    '.settlement.canonicalResultByteCount' \
    "$effect_root/boundary-probe/settlement-report.json"
)
complete_success_case exact-boundary 48 boundary exact.txt "$boundary_result_bytes"

under_root="$effect_root/under-boundary"
under_case="$under_root/request.json"
mkdir -p "$under_root/workspace"
printf '%s' 'boundary' >"$under_root/workspace/exact.txt"
make_case \
  "$under_case" \
  49 \
  exact.txt \
  "$(hex_bytes 'boundary')" \
  "$((boundary_result_bytes - 1))" \
  exact.txt
run_phase request "$under_case" "$under_root/wal" "$under_root/request-report.json"
run_phase claim "$under_case" "$under_root/wal" "$under_root/claim-report.json"
run_phase \
  settle \
  "$under_case" \
  "$under_root/wal" \
  "$under_root/settlement-report.json" \
  "$under_root/workspace"
jq -e '
  .settlement.kind == "rejected"
  and .settlement.observation.refusal == "settlement-budget-exceeded"
' "$under_root/settlement-report.json" >/dev/null

# A substituted compiler artifact fails before the first WAL commit.
mutated_core="$effect_root/mutated-core.cbor"
cp "$core_file" "$mutated_core"
printf '\000' | dd of="$mutated_core" bs=1 seek=0 conv=notrunc 2>/dev/null
mutated_root="$effect_root/mutated-artifact"
mkdir -p "$mutated_root"
make_case \
  "$mutated_root/request.json" \
  50 \
  source.txt \
  "$(hex_bytes 'source')" \
  65536 \
  source.txt
if env EFFECT_CORE_FILE="$mutated_core" ./tests/effect-run.sh \
  request \
  "$mutated_root/request.json" \
  "$mutated_root/wal" \
  >"$mutated_root/report.json"
then
  echo "substituted compiler artifact unexpectedly passed" >&2
  exit 1
fi
jq -e '
  .phase == "request"
  and .obstruction == "compilerArtifactRejected"
  and .wal.commitCount == 0
' "$mutated_root/report.json" >/dev/null

# Compiler-owned artifacts are re-admitted at every phase boundary. If they
# diverge after request admission, the later phase must return the same typed
# obstruction without appending to the existing WAL.
post_request_mutation_root="$effect_root/post-request-mutated-artifact"
mkdir -p "$post_request_mutation_root"
make_case \
  "$post_request_mutation_root/request.json" \
  73 \
  source.txt \
  "$(hex_bytes 'source')" \
  65536 \
  source.txt
run_phase \
  request \
  "$post_request_mutation_root/request.json" \
  "$post_request_mutation_root/wal" \
  "$post_request_mutation_root/request-report.json"
if env EFFECT_CORE_FILE="$mutated_core" ./tests/effect-run.sh \
  claim \
  "$post_request_mutation_root/request.json" \
  "$post_request_mutation_root/wal" \
  >"$post_request_mutation_root/claim-report.json"
then
  echo "post-request substituted compiler artifact unexpectedly passed" >&2
  exit 1
fi
jq -e '
  .phase == "claim"
  and .obstruction == "compilerArtifactRejected"
  and .wal.commitCount == 1
' "$post_request_mutation_root/claim-report.json" >/dev/null

# Invalid runtime request data is not misreported as a compiler artifact
# substitution and also fails before the first WAL commit.
invalid_request_root="$effect_root/invalid-request"
mkdir -p "$invalid_request_root"
make_case \
  "$invalid_request_root/request.json" \
  72 \
  source.txt \
  "$(hex_bytes 'source')" \
  1 \
  source.txt
if run_phase \
  request \
  "$invalid_request_root/request.json" \
  "$invalid_request_root/wal" \
  "$invalid_request_root/report.json"
then
  echo "invalid runtime request unexpectedly passed" >&2
  exit 1
fi
jq -e '
  .phase == "request"
  and .obstruction == "requestRejected"
  and .wal.commitCount == 0
' "$invalid_request_root/report.json" >/dev/null

# Fixed-seed property corpus.
property_seed=70110
property_ordinal=0
for property_value in \
  "seed-$property_seed-alpha" \
  "seed-$property_seed-spaces and punctuation: []{}" \
  "seed-$property_seed-unicode-Ω"
do
  property_ordinal=$((property_ordinal + 1))
  complete_success_case \
    "property-$property_ordinal" \
    "$((51 + property_ordinal))" \
    "$property_value" \
    "property-$property_ordinal.txt" \
    65536
done

# Bounded stress: eight isolated request/claim/settlement worldlines.
stress_count=8
stress_ordinal=1
while test "$stress_ordinal" -le "$stress_count"; do
  complete_success_case \
    "stress-$stress_ordinal" \
    "$((60 + stress_ordinal))" \
    "stress-$stress_ordinal-value" \
    "stress-$stress_ordinal.txt" \
    65536
  stress_ordinal=$((stress_ordinal + 1))
done

# The standalone proof must not smuggle checkout paths into retained evidence.
if grep -R -F \
  -e "$(CDPATH='' cd -- "$EDICT_REPO" && pwd -P)" \
  -e "$(CDPATH='' cd -- "$ECHO_REPO" && pwd -P)" \
  "$effect_root"/*/*.json \
  >/dev/null
then
  echo "Hello Effect witness disclosed a producer checkout path" >&2
  exit 1
fi

printf '%s\n' \
  "Hello Effect suite passed: 1 ordered golden, 1 relative artifact path, 1 retry, 1 conflict, 1 aperture substitution, 1 replay, 1 fresh world, 1 rootless unknown, 4 refusals, 1 boundary probe, 2 boundaries, 2 artifact refusals, 1 request refusal, 3 fixed-seed property, 8 stress"
