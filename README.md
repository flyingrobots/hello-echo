# Hello Echo

Hello Echo is the canonical smallest Edict application that targets Echo
without native application code, callbacks, GraphQL, or handwritten Echo
packages.

The application defines one operation:

```text
examples.hello_echo@1.createGreeting
```

`createGreeting` uses the portable `causal.cell@1.createIfAbsent` capability.
The application owns the greeting vocabulary. The capability package owns the
portable create-if-absent contract. Echo owns only the generic target adapter,
executable program, scheduler, WAL, receipts, and recovery.

## Local build

Set `EDICT_REPO` and `ECHO_REPO` to compatible local checkouts, then run:

```sh
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
