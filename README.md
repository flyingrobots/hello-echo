# Hello Echo

Hello Echo is the canonical smallest standalone Edict application hosted by
Echo. It proves that application semantics can originate in Edict, cross Echo's
generic target adapter and independent verifier, and execute without native
application callbacks or handwritten Echo packages.

The application defines one operation:

```text
examples.hello_echo@1.createGreeting
```

`createGreeting` uses the portable `causal.cell@1.createIfAbsent` capability.
The application owns the greeting vocabulary. The capability package owns the
portable create-if-absent contract. Echo owns only the generic target adapter,
executable program, scheduler, WAL, Receipts, and recovery.

Hello Echo is Roadmap A for the Graft-on-Echo campaign. Its complete local
build, execution, durability, and recovery witness is the prerequisite for
Roadmap B: writing Graft in Edict and hosting it on Echo.

External workspace effects are introduced only after that pure runtime proof.
The [campaign roadmap](docs/roadmap.md) orders bounded workspace observation,
basis-bound patch application, Graft hosting, Git and GitHub adapters, and the
self-hosted delivery loop. The delivery loop is Roadmap Ω, not Hello Echo's
bootstrap workload.

## Local build

Set `EDICT_REPO` and `ECHO_REPO` to compatible local checkouts, then run:

```sh
EDICT_REPO=/path/to/edict \
ECHO_REPO=/path/to/echo \
./tests/build.sh
```

The build:

1. corroborates every vendored causal-cell artifact byte-for-byte against
   Edict's generator-owned fixture;
2. copies Echo's checked target-provider package into an isolated build tree,
   following no symlinks and copying no Git repository metadata;
3. invokes Edict's public application-build boundary;
4. loads the exact source and complete vendored lawpack closure;
5. invokes the provider lowerer and structurally separate verifier;
6. writes the exact accepted provider-emitted bytes to:
   - `.build/application/executable-operation-package.cbor`;
   - `.build/application/verification-report.cbor`.

The external build is GREEN. The remaining RED is runtime execution: the
compiler-emitted package and accepted verification report must cross a supported
generic Echo runner, scheduler-owned bounded evaluation, durable submission and
decided-Tick WAL boundaries, restart recovery, and typed duplicate obstruction
without hidden mutation.

No artifact in this repository may be replaced by a handwritten Echo package,
and no native Hello Echo callback may implement application semantics.
