#!/bin/sh
# Shared writer-epoch assertions for the runtime witnesses.
#
# Source this file; it defines functions and runs nothing on its own.
#
# Echo owns writer-epoch derivation and fencing. These assertions are how the
# witnesses prove a host consumed that contract rather than minting an epoch
# identity of its own. Exercised by tests/writer-epoch-assertions.sh.

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
    and (.writerEpoch.startedAtLsn | type) == "number"
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
      and .writerEpoch.previousEpochFinalCommitDigest
          == $previous[0].wal.lastCommitDigest
      and (.writerEpoch.startedAtLsn | type) == "number"
      and ($previous[0].writerEpoch.startedAtLsn | type) == "number"
      and .writerEpoch.startedAtLsn > $previous[0].writerEpoch.startedAtLsn
    ' \
    "$report_file" >/dev/null
}

# Read-only phases take no writer lease and therefore acquire no epoch.
assert_no_writer_epoch() {
  report_file=$1
  # jq reads a missing property as null, so requiring the field to be present
  # keeps this an assertion about a reported absence rather than one satisfied
  # by a host that stopped reporting.
  jq -e 'has("writerEpoch") and .writerEpoch == null' "$report_file" >/dev/null
}
