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
  # jq reads a missing property as null, so every field the assertion relies on
  # must be required to exist. Otherwise a host that stopped emitting the
  # predecessor fields would satisfy the null comparisons below.
  jq -e '
    has("writerEpoch")
    and (.writerEpoch | has("epochId"))
    and (.writerEpoch | has("previousEpochId"))
    and (.writerEpoch | has("previousEpochFinalCommitDigest"))
    and (.writerEpoch | has("startedAtLsn"))
    and (.writerEpoch.epochId | test("^[0-9a-f]{64}$"))
    and .writerEpoch.previousEpochId == null
    and .writerEpoch.previousEpochFinalCommitDigest == null
    and (.writerEpoch.startedAtLsn | type) == "number"
    and (.writerEpoch.startedAtLsn | floor) == .writerEpoch.startedAtLsn
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
      has("writerEpoch")
      and (.writerEpoch | has("epochId"))
      and (.writerEpoch | has("previousEpochId"))
      and (.writerEpoch | has("previousEpochFinalCommitDigest"))
      and (.writerEpoch | has("startedAtLsn"))
      # The predecessor report is input to this assertion, not a trusted
      # source. Without these, a predecessor carrying no writerEpoch yields
      # null and a successor reporting previousEpochId null satisfies the
      # linkage by null == null.
      and ($previous[0] | has("writerEpoch"))
      and ($previous[0].writerEpoch | has("epochId"))
      and ($previous[0].writerEpoch | has("startedAtLsn"))
      and ($previous[0].writerEpoch.epochId | test("^[0-9a-f]{64}$"))
      and ($previous[0] | has("wal"))
      and ($previous[0].wal | has("lastCommitDigest"))
      and ($previous[0].wal.lastCommitDigest | test("^[0-9a-f]{64}$"))
      and (.writerEpoch.epochId | test("^[0-9a-f]{64}$"))
      and (.writerEpoch.previousEpochFinalCommitDigest | test("^[0-9a-f]{64}$"))
      and .writerEpoch.epochId != $previous[0].writerEpoch.epochId
      and .writerEpoch.previousEpochId == $previous[0].writerEpoch.epochId
      and .writerEpoch.previousEpochFinalCommitDigest
          == $previous[0].wal.lastCommitDigest
      # An LSN is a discrete u64 position. A type check alone admits 0.5,
      # which compares greater than a predecessor 0 and would let malformed
      # epoch evidence through.
      and (.writerEpoch.startedAtLsn | type) == "number"
      and ($previous[0].writerEpoch.startedAtLsn | type) == "number"
      and (.writerEpoch.startedAtLsn | floor) == .writerEpoch.startedAtLsn
      and ($previous[0].writerEpoch.startedAtLsn | floor)
          == $previous[0].writerEpoch.startedAtLsn
      # An Lsn is a u64. 1e100 is a nonnegative integer to jq and compares
      # greater than any predecessor, but cannot represent a position.
      and .writerEpoch.startedAtLsn >= 0
      and $previous[0].writerEpoch.startedAtLsn >= 0
      and .writerEpoch.startedAtLsn <= 18446744073709551615
      and $previous[0].writerEpoch.startedAtLsn <= 18446744073709551615
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
