#!/bin/sh
set -eu

# Hermetic test of tests/lib/writer-epoch-assertions.sh.
#
# Both runtime witnesses rely on those assertions to prove that each write
# phase runs under a fresh, durably chained writer epoch. An assertion that has
# never been shown to reject a bad report proves nothing, so this feeds them
# reports mutated to carry exactly the defects the assertions exist to catch.
#
# No producer checkout, no host binary, and no cargo: this runs anywhere.

command -v jq >/dev/null

. tests/lib/writer-epoch-assertions.sh

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

first=57645ea6d8294d4177531f813035c926d051bae68c0ce6d0a74afc08bf612d55
second=a3b974bd428109b96ea26087630b9562c51a08f7ac498d93bb04c253ee6bb85a
commit=3aa349ca0d266dc02cc80fc40fd68e3082fe278bdd5afc6b38f633a05b383e09
other=8bd0f1c2e4a6957038d1b5c7e9f2a4b6c8d0e2f4a6b8c0d2e4f60718293a4b5c

cat >"$work/request.json" <<EOF
{"phase":"request","wal":{"commitCount":1,"lastCommitDigest":"$commit"},
 "writerEpoch":{"epochId":"$first","previousEpochId":null,
 "previousEpochFinalCommitDigest":null,"startedAtLsn":0}}
EOF
cat >"$work/claim.json" <<EOF
{"phase":"claim","wal":{"commitCount":2,"lastCommitDigest":"$other"},
 "writerEpoch":{"epochId":"$second","previousEpochId":"$first",
 "previousEpochFinalCommitDigest":"$commit","startedAtLsn":1}}
EOF
cat >"$work/inspect.json" <<'EOF'
{"phase":"inspect","writerEpoch":null}
EOF

# Derives a mutated claim report by applying a jq edit to the valid one.
mutate() {
  jq "$2" "$work/claim.json" >"$work/mutant.json"
  if assert_chained_writer_epoch "$work/mutant.json" "$work/request.json" \
    2>/dev/null
  then
    printf 'FAIL assertion accepted: %s\n' "$1" >&2
    exit 1
  fi
  printf 'ok   rejected: %s\n' "$1"
}

# Controls. If these fail the assertions are simply broken, not strict.
assert_first_writer_epoch "$work/request.json"
printf 'ok   accepted: first epoch on a fresh WAL\n'
assert_chained_writer_epoch "$work/claim.json" "$work/request.json"
printf 'ok   accepted: claim chained to request\n'
assert_no_writer_epoch "$work/inspect.json"
printf 'ok   accepted: read-only phase reports no epoch\n'

# The defect this PR fixed: a host that reuses one static epoch across
# restarts reports the same id in consecutive write phases.
mutate "reused epoch id" \
  '.writerEpoch.epochId = "'"$first"'"'

# The old call site passed previous_epoch_id: None, so nothing linked an epoch
# to its predecessor.
mutate "no predecessor linkage" \
  '.writerEpoch.previousEpochId = null
   | .writerEpoch.previousEpochFinalCommitDigest = null'

# Predecessor named without the commit digest that closes it.
mutate "predecessor named but no final commit digest" \
  '.writerEpoch.previousEpochFinalCommitDigest = null'

# An epoch chained to some other epoch than the one that actually preceded it.
mutate "predecessor is not the preceding epoch" \
  '.writerEpoch.previousEpochId = "'"$second"'"'

# A successor must own LSNs after its predecessor.
mutate "start LSN does not advance" \
  '.writerEpoch.startedAtLsn = 0'
mutate "start LSN moves backwards" \
  '.writerEpoch.startedAtLsn = -1'

# A write phase that reports no epoch at all must not read as chained.
mutate "write phase reports no epoch" \
  '.writerEpoch = null'

# A well-formed digest that is not the predecessor's actual final commit. The
# shape check alone accepts this, so only comparing the value catches a
# producer that links the right epoch id to the wrong commit.
mutate "predecessor final commit digest is well-formed but wrong" \
  '.writerEpoch.previousEpochFinalCommitDigest = "'"$other"'"'

# jq orders across types, so "oops" > 0 and {} > 0 are both true. A start LSN
# replaced by malformed data would satisfy a bare > comparison.
mutate "start LSN is a string" \
  '.writerEpoch.startedAtLsn = "oops"'
mutate "start LSN is an object" \
  '.writerEpoch.startedAtLsn = {}'
mutate "start LSN is absent" \
  'del(.writerEpoch.startedAtLsn)'

# A malformed identity is not an epoch.
mutate "epoch id is not a digest" \
  '.writerEpoch.epochId = "not-a-digest"'

# jq reads a missing property as null, so an assertion written only as
# "== null" also passes when the host stops emitting the field. A report that
# omits the evidence entirely must fail rather than read as proof of absence.
jq 'del(.writerEpoch)' "$work/inspect.json" >"$work/absent.json"
if assert_no_writer_epoch "$work/absent.json" 2>/dev/null; then
  echo 'FAIL assertion accepted: report omitting writerEpoch entirely' >&2
  exit 1
fi
printf 'ok   rejected: report omitting writerEpoch entirely\n'

# A read-only phase that acquired a lease would be a silent authority
# escalation, so the null assertion must not accept a populated epoch.
if assert_no_writer_epoch "$work/claim.json" 2>/dev/null; then
  echo 'FAIL assertion accepted: read-only check passed a populated epoch' >&2
  exit 1
fi
printf 'ok   rejected: read-only check against a populated epoch\n'

# The first-epoch assertion must not accept an epoch that already has a
# predecessor, which would hide a WAL that was not actually fresh.
if assert_first_writer_epoch "$work/claim.json" 2>/dev/null; then
  echo 'FAIL assertion accepted: first-epoch check passed a chained epoch' >&2
  exit 1
fi
printf 'ok   rejected: first-epoch check against a chained epoch\n'

echo "writer epoch assertions: all cases passed"
