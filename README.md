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

The public shell boundary canonicalizes producer checkout paths before
serializing them into the generated Cargo manifest. Relative compiler-artifact
overrides are resolved from the application root, independent of the caller's
working directory.

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
- `outcomeUnknown` remains distinct from failure, requires no workspace root,
  and settles after the source directory is removed;
- the exact permitted path aperture is part of durable request identity, so
  post-claim aperture substitution cannot recover the claim;
- unauthorized, parent-escaped, symlink, and stale-basis paths settle as typed
  refusals;
- the exact settlement-size boundary succeeds and one byte less refuses; and
- substituted compiler artifacts are rejected with the same typed obstruction
  at request and recovery boundaries without appending to the WAL, while
  invalid runtime requests remain a distinct pre-commit refusal.

The fixed suite contains one ordered golden path, one relative
compiler-artifact path probe, one idempotent retry, one conflicting retry, one
aperture substitution, one rootless replay, one fresh-world observation, one
rootless ambiguous outcome, four path-or-basis refusals, one boundary probe,
two boundary cases, two compiler-artifact refusals, one runtime-request
refusal, three cases derived from fixed seed `70110`, and eight bounded stress
worldlines. Every retained JSON artifact is checked for producer-checkout path
leaks. Reports contain compiler and causal identities but no producer-checkout
or workspace-root paths.

Edict declares `workspace.snapshot.observe@1`; Echo durably coordinates it; the
adapter alone reads the workspace. This proof grants Edict no filesystem,
process, network, or model authority and introduces no application callback.

No artifact in this repository may be replaced by a handwritten Echo package,
and no native Hello Echo callback may implement application semantics.

## Hello Effect validated patch application

The second external-effect proof accepts bounded observation evidence as basis
input and applies one compiler-authored validated patch:

```sh
EDICT_REPO=/path/to/edict \
ECHO_REPO=/path/to/echo \
./tests/patch-runtime.sh
```

The build corroborates the exact Edict source, lawpack closure, digest
sidecars, Core artifact, and Target IR artifact for
`workspace.patch.applyValidated@1`. Edict emits request data only. The compiler
provider receives no filesystem authority and emits no executable-operation
package.

The request JSON separates untrusted `proposal` data from the declared
`observation` basis. The host owns `permittedPaths` and the adapter's
65,536-byte file cap; the model controls only the closed `proposal` schema.
The host uses Echo's generic validated-patch encoder and authority functions;
it does not reconstruct patch policy or perform native application semantics.
The observation is also a closed schema. Echo durably records the request and
claim before only the bounded adapter receives a workspace root.

This witness proves the basis-bound write boundary independently. It does not
claim that the observation and patch run share one chained transaction or
worldline.

The runtime witness proves:

- request and claim commit before mutation, across separate processes;
- recovery exposes pending requested and claimed states without workspace
  authority;
- the adapter can mutate only an exact permitted path under the admitted
  observation basis;
- the canonical settlement commits before the result is reported, and the
  report cross-compares its attempt, request basis, external evidence,
  postcondition digest, and resulting basis;
- exact retry is effect-free and conflicting retry obstructs without WAL
  growth;
- replay accepts no workspace root and does not reapply a settled patch after
  the file changes again;
- a crash after mutation but before settlement reconciles from the observed
  postcondition without inventing pre-state evidence;
- an ambiguous postcondition settles as `outcomeUnknown` without another
  mutation;
- stale basis, unauthorized path, parent escape, symlink, and CI-workflow
  policy failures obstruct before mutation;
- the exact request-only settlement floor passes and one byte less refuses
  before a WAL commit;
- compiler-artifact substitution fails at request and claim boundaries
  without hidden WAL growth; and
- fixed-seed text, Unicode, and binary replacements plus eight bounded stress
  worldlines pass.

The model-facing surface is data only. Edict owns the request declaration,
Echo owns admission and durable coordination, and the adapter alone owns the
bounded write. No generic filesystem write, process, network, Git, or model
authority is introduced.
