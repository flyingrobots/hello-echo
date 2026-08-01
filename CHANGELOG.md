# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Standalone Hello Echo Edict source, pinned `causal.cell@1` capability closure,
  and deterministic build for compiler-produced Echo package and verification
  report artifacts.
- Durable singleton runtime witness covering WAL-before-ack submission,
  scheduler-owned evaluation, restart recovery, typed duplicate obstruction,
  altered-basis refusal, byte-identical deterministic reruns, fixed-seed input
  cases, and bounded stress.
- Delivery-loop hosting feasibility report against the current Edict-to-Echo
  seam.
- Syntax-independent delivery-loop phase graph with guarded transitions,
  declared effects, bounded judgment leaves, and terminal reachability.
- Compiler-authored bounded workspace observation witness covering durable
  request and claim recovery, capability-rooted settlement, idempotent and
  conflicting retry, effect-free replay, rootless ambiguous outcome settlement,
  post-claim aperture-substitution refusal, distinct compiler-artifact and
  runtime-request admission errors at every phase boundary, checkout-independent
  artifact paths, path and budget refusals, fixed-seed cases, and bounded
  stress.
- Compiler-authored basis-bound patch witness covering request-before-write,
  exact writable apertures, postcondition settlement, effect-free retry and
  replay, crash reconciliation, ambiguous outcomes, path and basis refusals,
  request-budget boundaries, compiler-artifact substitution, fixed-seed binary
  replacements, and bounded stress.
- Writer-epoch chain evidence in the observation and patch reports, with
  witness cases requiring a fresh epoch per write phase, exact predecessor and
  final-commit-digest linkage, a strictly advancing start LSN, no epoch on
  read-only phases, and no epoch reused across the ordered golden path. The
  predecessor linkage is compared against the commit digest the predecessor
  reported, not merely checked for shape.
- A retained-ledger plateau case in both witnesses, driving sixteen fresh
  writer epochs on one WAL and requiring the persisted ledger to stop changing
  size, which a fixed-size ceiling could not establish.
- A two-route basis binding for the reconciled success settlement, since the
  reconciler is a distinct implementation from the adapter and the existing
  probe exercised only the apply path.
- Writer-epoch coverage on the reconciliation and uncertainty write
  entrypoints, and retained-ledger snapshots across both retries, since a null
  epoch in a retry report is supplied by the phase itself and cannot show that
  no epoch was taken.
- Negative coverage for the retained postcondition evidence: the one settlement
  family where the declared replacement and the observed post-state differ now
  pins that the evidence varies with what was observed and not with what was
  requested, and records that `beforeContentDigest` reports the observed bytes
  in that case.
- `wal.lastCommitDigest` in both reports, so a successor epoch's declared
  predecessor commit can be compared with the commit that actually closed it.
- Build refusal for cross-wired, unresolved, or sentinel external-action schema
  identities in the vendored compiler source, enforced by a single shared guard
  that binds each schema slot to the vendored artifact it names.
- Hermetic `tests/resource-identity-guard.sh` and
  `tests/writer-epoch-assertions.sh` covering the build guard and the shared
  writer-epoch assertions against crafted closures and mutated reports. Both
  require no producer checkout and no `cargo`.

- `replacementExceedsRequestBudget` and `observationExceedsFileBudget` as
  distinct request obstructions, with witness cases covering a replacement
  above the encodable ceiling and a declared pre-state above the file budget.

### Changed

- Advanced the vendored `workspace.patch@1` closure to Edict
  `df80f92ad6242c6da31a64224666fd37aa43b0d0`, which replaces the sentinel
  `workspace.patch.input@1`, `workspace.patch.settlement@1`, and
  `workspace.patch.reconcile@1` digests with the exact identities of vendored
  `edict.external-action-resource/v1` artifacts, now supplied to the build
  through `externalActionResources`.
- Acquire the patch host's writer epoch through Echo's
  `FilesystemWalStore::acquire_fresh_writer_epoch` against Echo
  `c354d531679861fb7bbd52ab7b7703807909ab86`, replacing the static epoch
  identity, fixed fencing, process, host, and lease digests, and absent
  predecessor linkage that could not fence overlapping or restarted hosts.
- Advanced the vendored `workspace.snapshot@1` closure to the same Edict
  commit, which likewise replaces its sentinel `workspace.snapshot.input@1`,
  `workspace.snapshot.settlement@1`, and `workspace.snapshot.reconcile@1`
  digests with vendored external-action resource identities, and acquire the
  observation host's writer epoch through the same producer-owned fresh-epoch
  contract.
- Require the runtime witness to retain the exact Edict-authored
  `GreetingCreated { key, message }` result identity and canonical bytes through
  generic Echo evaluation and to compare the applied, fresh-host, and
  WAL-recovered result records exactly.
- Distinguished producer-satisfied review findings from stale or
  unreproducible findings, bounded operator-authorized remediation without
  resetting the autonomous budget, and made disposition-only closure
  non-mutating.
- Require Echo-produced before/after application-state roots and typed
  target-value digests to be present, canonical, and equal before the duplicate
  no-mutation witness can pass.
- Clear prior application output before each build so stale artifacts cannot
  satisfy post-build validation.
- Restored the pure compiler-to-runtime Hello Echo proof as Roadmap A, defined
  durable request and witnessed-settlement boundaries for later external
  effects, and moved the self-hosted delivery loop to Roadmap Ω.
