#!/bin/sh
set -eu

: "${EDICT_REPO:?set EDICT_REPO to the compatible Edict checkout}"
: "${ECHO_REPO:?set ECHO_REPO to the compatible Echo checkout}"

command -v jq >/dev/null

./tests/build.sh

runtime_root=.build/runtime-tests
rm -rf "$runtime_root"
mkdir -p "$runtime_root"

package_file=.build/application/executable-operation-package.cbor
verification_report_file=.build/application/verification-report.cbor
lawpack_manifest_file=vendor/causal-cell/manifest.cbor
expected_package_sha256=67dc6d23e223e78b6aa774a2f57c86db2eff4981ea793975d39c66f731f02fd1
expected_verification_report_sha256=8a5153b4ec25ebe979f0ceab373d03969e30a64d7973b3a83e3c84877c5aa564
expected_lawpack_manifest_sha256=7bb901c984a92ed50795f8b5f7efe8d0648124574fa82250c6373a30e94333c9

sha256_file() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "runtime witness requires sha256sum or shasum" >&2
    return 1
  fi
}

run_case() {
  case_name=$1
  input_file=$2
  case_root="$runtime_root/$case_name"
  mkdir -p "$case_root"
  ./tests/run.sh \
    "$input_file" \
    "$case_root/wal" \
    >"$case_root/witness.json"
}

assert_common_witness() {
  witness=$1
  package_sha256=$(sha256_file "$package_file")
  verification_report_sha256=$(sha256_file "$verification_report_file")
  lawpack_manifest_sha256=$(sha256_file "$lawpack_manifest_file")
  test "$package_sha256" = "$expected_package_sha256"
  test "$verification_report_sha256" = "$expected_verification_report_sha256"
  test "$lawpack_manifest_sha256" = "$expected_lawpack_manifest_sha256"
  jq -e \
    --arg package_sha256 "$package_sha256" \
    --arg verification_report_sha256 "$verification_report_sha256" \
    --arg lawpack_manifest_sha256 "$lawpack_manifest_sha256" \
    '
    .operation == "examples.hello_echo@1.createGreeting"
    and .artifacts.package.algorithm == "sha256"
    and .artifacts.package.digestHex == $package_sha256
    and .artifacts.verificationReport.algorithm == "sha256"
    and .artifacts.verificationReport.digestHex == $verification_report_sha256
    and .artifacts.lawpackManifest.algorithm == "sha256"
    and .artifacts.lawpackManifest.digestHex == $lawpack_manifest_sha256
    and .submission.walCommittedBeforeAck == true
    and .scheduler.actionCount == 1
    and .recovery.pendingActionRecovered == true
    and .recovery.actionRecovered == true
    and .recovery.tickRecovered == true
    and .recovery.stateRecovered == true
    and .recovery.outcomeRecovered == true
    and .recovery.receiptRecovered == true
    and .recovery.mutatedInitialStateRefusal == "echo-operation-execution-mismatch/action-basis"
    and .duplicate.obstruction == "causal.cell@1.AlreadyExists"
    and (.causalSite.worldlineId | test("^[0-9a-f]{64}$"))
    and (.causalSite.warpId | test("^[0-9a-f]{64}$"))
    and (.causalSite.nodeId | test("^[0-9a-f]{64}$"))
    and (.causalSite.submissionId | test("^[0-9a-f]{64}$"))
    and (.causalSite.tickCommitId | test("^[0-9a-f]{64}$"))
    and (.causalSite.receiptDigest | test("^[0-9a-f]{64}$"))
    and .causalSite.commitGlobalTick > 0
    and .causalSite.worldlineTickAfter == 1
  ' "$witness" >/dev/null
}

# Golden path: exact compiler output enters the generic durable runner.
run_case golden tests/create-greeting.json
golden_witness="$runtime_root/golden/witness.json"
assert_common_witness "$golden_witness"
jq -e '
  .causalSite.basis == "u0"
  and .causalSite.nodeKey == "greeting"
  and .state.valueUtf8 == "Hello Echo"
' "$golden_witness" >/dev/null

# Identical source, closure, input, and empty-WAL basis produce identical evidence.
# Persisted-WAL replay occurs inside each generic runner invocation and is
# asserted by the recovery fields above.
run_case deterministic-rerun tests/create-greeting.json
cmp "$golden_witness" "$runtime_root/deterministic-rerun/witness.json"

# The witness is portable evidence and must not disclose checkout paths.
edict_repo_root=$(CDPATH='' cd -- "$EDICT_REPO" && pwd -P)
echo_repo_root=$(CDPATH='' cd -- "$ECHO_REPO" && pwd -P)
project_root=$(pwd -P)
if grep -F \
  -e "$edict_repo_root" \
  -e "$echo_repo_root" \
  -e "$project_root" \
  "$golden_witness" \
  >/dev/null
then
  echo "runtime witness disclosed a host checkout path" >&2
  exit 1
fi

# Compiler output remains generated and untracked; Edict is the only source language.
for generated_artifact in \
  .build/application/executable-operation-package.cbor \
  .build/application/verification-report.cbor
do
  if git ls-files --error-unmatch "$generated_artifact" >/dev/null 2>&1; then
    echo "compiler output must not become a handwritten tracked package" >&2
    exit 1
  fi
done
test "$(git ls-files src)" = "src/hello_echo.edict"

# Known failure: malformed typed input fails before a passing witness exists.
malformed_input="$runtime_root/malformed-input.json"
printf '%s\n' '{"basis":"u0","key":"missing-value"}' >"$malformed_input"
if ./tests/run.sh \
  "$malformed_input" \
  "$runtime_root/malformed-wal" \
  >"$runtime_root/malformed.stdout" \
  2>"$runtime_root/malformed.stderr"
then
  echo "malformed operation input unexpectedly passed" >&2
  exit 1
fi
test ! -s "$runtime_root/malformed.stdout"
grep -F "operation input fields do not match the target configuration" \
  "$runtime_root/malformed.stderr" >/dev/null

# Boundary: the exact configured replacement limit passes; one byte over refuses.
jq -n --arg value "$(jq -nr '"x" * 256')" \
  '{basis:"boundary",key:"maximum",value:$value}' \
  >"$runtime_root/maximum-input.json"
run_case maximum "$runtime_root/maximum-input.json"
assert_common_witness "$runtime_root/maximum/witness.json"
test "$(jq -r '.state.valueUtf8 | length' "$runtime_root/maximum/witness.json")" -eq 256

jq -n --arg value "$(jq -nr '"x" * 257')" \
  '{basis:"boundary",key:"too-large",value:$value}' \
  >"$runtime_root/oversized-input.json"
if ./tests/run.sh \
  "$runtime_root/oversized-input.json" \
  "$runtime_root/oversized-wal" \
  >"$runtime_root/oversized.stdout" \
  2>"$runtime_root/oversized.stderr"
then
  echo "oversized operation input unexpectedly passed" >&2
  exit 1
fi
test ! -s "$runtime_root/oversized.stdout"
grep -F "operation replacement exceeds the configured byte bound" \
  "$runtime_root/oversized.stderr" >/dev/null

# Fixed-seed property cases preserve typed input through durable recovery.
property_seed=69603
property_ordinal=0
for property_value in \
  "seed-$property_seed-alpha" \
  "seed-$property_seed-spaces and punctuation: []{}" \
  "seed-$property_seed-unicode-Ω"
do
  property_ordinal=$((property_ordinal + 1))
  property_name="property-$property_ordinal"
  property_input="$runtime_root/$property_name-input.json"
  jq -n \
    --arg basis "$property_name" \
    --arg key "key-$property_ordinal" \
    --arg value "$property_value" \
    '{basis:$basis,key:$key,value:$value}' \
    >"$property_input"
  run_case "$property_name" "$property_input"
  property_witness="$runtime_root/$property_name/witness.json"
  assert_common_witness "$property_witness"
  jq -e \
    --arg basis "$property_name" \
    --arg key "key-$property_ordinal" \
    --arg value "$property_value" \
    '.causalSite.basis == $basis
      and .causalSite.nodeKey == $key
      and .state.valueUtf8 == $value' \
    "$property_witness" >/dev/null
done

# Bounded stress: eight isolated worldlines each complete the full recovery proof.
stress_count=8
stress_ordinal=1
while test "$stress_ordinal" -le "$stress_count"; do
  stress_name="stress-$stress_ordinal"
  stress_input="$runtime_root/$stress_name-input.json"
  jq -n \
    --arg basis "$stress_name" \
    --arg key "greeting-$stress_ordinal" \
    --arg value "Hello Echo $stress_ordinal" \
    '{basis:$basis,key:$key,value:$value}' \
    >"$stress_input"
  run_case "$stress_name" "$stress_input"
  assert_common_witness "$runtime_root/$stress_name/witness.json"
  stress_ordinal=$((stress_ordinal + 1))
done

printf '%s\n' "runtime witness suite passed: 1 golden, 1 deterministic rerun, 2 refusals, 1 boundary, 3 fixed-seed property, 8 stress"
