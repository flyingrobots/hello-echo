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
  altered-basis refusal, fixed-seed input cases, and bounded stress.
- Delivery-loop hosting feasibility report against the current Edict-to-Echo
  seam.
- Syntax-independent delivery-loop phase graph with guarded transitions,
  declared effects, bounded judgment leaves, and terminal reachability.

### Changed

- Clear prior application output before each build so stale artifacts cannot
  satisfy post-build validation.
- Restored the pure compiler-to-runtime Hello Echo proof as Roadmap A, defined
  durable request and witnessed-settlement boundaries for later external
  effects, and moved the self-hosted delivery loop to Roadmap Ω.
