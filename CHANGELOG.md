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

### Changed

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
