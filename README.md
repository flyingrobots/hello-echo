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

Run `./tests/build-cleans-output.sh` with the same environment to verify that a
new invocation cannot be satisfied by stale application artifacts.

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

## Local runtime witness

Run the complete compiler-to-runtime suite with the same compatible checkouts:

```sh
EDICT_REPO=/path/to/edict \
ECHO_REPO=/path/to/echo \
./tests/runtime.sh
```

The suite builds the application once, then invokes `tests/run.sh` with isolated
input and WAL directories. That external boundary supplies only the exact
compiler-produced package, accepted verification report, vendored capability
closure, typed JSON input, and empty WAL path to Echo's generic
`run-edict-operation` command.

The structured witness proves:

- accepted-submission WAL commit before acknowledgement;
- pending-Action recovery by reopening the same WAL before evaluation;
- one scheduler-selected Action in one atomic Tick;
- decided-Tick recovery of Action, Tick, state, outcome, and Receipt by
  reopening that persisted WAL in another fresh host;
- the exact package-declared
  `examples.hello_echo@1.GreetingCreated { key, message }` result as canonical
  evidence, including independent equality of the applied, fresh-host, and
  WAL-recovered generic result records without native reconstruction;
- successful greeting state derived from the same typed input;
- package-declared `causal.cell@1.AlreadyExists` obstruction on duplicate
  creation, with equal canonical application-state roots and typed target-value
  digests independently demonstrating no hidden mutation;
- refusal to recover the WAL against a mutated pre-Tick initial state; and
- exact compiler artifact identities without checkout paths in the report.

The test matrix includes the golden case, a byte-identical deterministic fresh
rerun, malformed and oversized refusals, the exact 256-byte replacement
boundary, three cases derived from fixed seed `69603`, and eight bounded
isolated recovery runs. WAL replay is the fresh-host recovery performed inside
each generic runner invocation; the deterministic rerun is separate evidence.

This is singleton scheduler integration: one Action in one Tick. It does not
claim permanent multi-Action Tick composition or introduce external effects.

## Hello Effect workspace observation

The first external-effect proof is separate from the pure Hello Echo runtime.
Run it with the same compatible producer checkouts:

```sh
EDICT_REPO=/path/to/edict \
ECHO_REPO=/path/to/echo \
./tests/effect-runtime.sh
```

The build corroborates the Edict source and complete `workspace.snapshot@1`
lawpack closure byte-for-byte, then uses Edict's public `externalAction` build
to emit the exact compiler-owned Core and Echo Target IR request artifacts. It
does not emit an executable-operation package or invoke an effect through the
compiler/provider seam.

The runtime witness uses Echo's public generic external-action coordinator and
bounded workspace adapter. It proves:

- request and claim WAL commits occur in separate host processes before the
  requested file exists;
- recovery exposes requested and claimed pending states without filesystem
  authority;
- only the capability-rooted adapter receives the workspace directory and
  exact permitted paths;
- the canonical settlement is committed before its value becomes
  consumer-visible;
- an identical settlement retry returns the original admission without another
  WAL commit, while a kind-only conflict obstructs without mutation;
- replay accepts no workspace root, retains observed value A after the complete
  source root is removed, and does not re-enter the adapter;
- a fresh request on a new worldline observes later value B;
- `outcomeUnknown` remains distinct from failure;
- unauthorized, parent-escaped, and symlink paths settle as typed refusals;
- the exact settlement-size boundary succeeds and one byte less refuses; and
- a substituted Core artifact is rejected before the first WAL commit.

The fixed suite contains one ordered golden path, one idempotent retry, one
conflicting retry, one rootless replay, one fresh-world observation, one
ambiguous outcome, three path refusals, three cases derived from fixed seed
`70110`, and eight bounded stress worldlines. Reports contain compiler and
causal identities but no producer-checkout or workspace-root paths.

Edict declares `workspace.snapshot.observe@1`; Echo durably coordinates it; the
adapter alone reads the workspace. This proof grants Edict no filesystem,
process, network, or model authority and introduces no application callback.

No artifact in this repository may be replaced by a handwritten Echo package,
and no native Hello Echo callback may implement application semantics.
