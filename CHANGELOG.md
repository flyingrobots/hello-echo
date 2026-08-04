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
- Hermetic `tests/writer-epoch-assertions.sh` covering the shared writer-epoch
  assertions against mutated reports. It requires no producer checkout and no
  `cargo`.

- `replacementExceedsRequestBudget` and `observationExceedsFileBudget` as
  distinct request obstructions, with witness cases covering a replacement
  above the encodable ceiling and a declared pre-state above the file budget.

- `producers.lock.json` pinning the exact Edict and Echo commits, enforced at
  every build boundary by `tests/producer-lock.sh`, so a stale, mismatched, or
  locally modified producer checkout fails rather than silently changing what
  is proven.
- A CI workflow that reads that lock, checks the producers out at those
  commits, and runs the complete witness gate plus shell syntax, formatting,
  and strict clippy on pull requests and pushes to `main`.

- Large file bodies are handed to `jq` through `--rawfile` rather than `--arg`.
  A body at the file budget is 131,072 hex characters, which is exactly Linux's
  `MAX_ARG_STRLEN`, so the oversize cases failed with "Argument list too long"
  anywhere but a developer machine.
- Absolute symlink targets in the relative-producer-path probe. The probe
  linked the producer checkout as given, so a relative producer path produced a
  dangling link rather than a relative path, and the observation witness failed
  before it began. It worked only because every caller had passed absolute
  paths until CI existed.
- Settlement attempt, basis, external-evidence, and schema-admission identities
  in the observation report, which `patch-host` already projected and
  `effect-host` did not. Without them a basis retained over the wrong bytes was
  unobservable to the witness.
- An observed-basis binding case for the observation witness. A succeeded
  observation cannot establish it: the adapter refuses unless the basis it
  derives over what it read equals the requested basis, so the two agree there
  by construction. The stale-basis refusal is the one settlement family where
  the retained evidence is independently informative, and a separate successful
  observation of those exact bytes derives the same basis by a second route.
  The case also pins that the refusal does not echo the requested basis, and
  that the basis varies with the observed bytes on a fixed path, so neither
  comparison can be satisfied by a constant.

### Removed

- `tests/lib/check-resource-identities.sh` and
  `tests/resource-identity-guard.sh`. The guard had grown into a second Edict
  parser written in shell and living in the consumer: declaration syntax,
  comments, coordinates, same-line clauses, sidecar terminators, digest
  grammar, and placeholder recognition. Edict owns canonical resource
  construction, identity derivation, closure validation, and rejection of
  malformed, missing, substituted, and sentinel resources, and the build
  already corroborates every artifact byte-for-byte and invokes that validator.
  Hello Echo corroborates Edict artifacts; it does not partially reparse Edict
  source.

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
