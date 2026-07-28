# Delivery Loop Hosting Feasibility

Status: verified against Echo
`eb0abb6ea90d1968e5d10922dc6d88eb7b361460` and Edict
`296bf1f6c76af1e011f5214b6d3de260c67ca84a`.

## Verdict

**Not yet hostable.**

The current Edict-to-Echo seam is a deterministic compiler and execution seam,
not a general effect host. It can:

1. invoke a capability-denied provider component synchronously to lower
   digest-bound Edict artifacts;
2. invoke a structurally separate capability-denied verifier synchronously;
3. emit and admit one bounded Echo executable-operation package; and
4. execute the package's anchored-node attachment operation through
   scheduler-owned Actions and durable Ticks.

The delivery loop requires process, filesystem, network, Git, GitHub, timer,
and model interactions plus durable waiting while external work completes.
None is exposed to an Edict program. Adding them does not require callable
imports in Edict or in the provider world. It requires typed request values
declared in the application closure, durable request/claim/settlement history
owned by Echo, narrow effect adapters, and witnessed settlement ingress.

Those are genuine architecture gaps, not additional provider roles or small
target-lowering extensions. The required follow-up to this feasibility result
is blocker filing and the syntax-independent phase graph in
`docs/phase-graph.md`. No full delivery-loop implementation may begin on this
seam.

## Current seam

### Compiler crossing

The provider ABI exports exactly two component calls:
`lower(request) -> result` and `verify(request) -> result`. It imports only
protocol types. The host rejects every callable or unknown import and installs
no WASI, filesystem, network, environment, clock, randomness, registry, or
callback capability.

The calls are synchronous. Each invocation creates a fresh bounded Wasmtime
store, calls one exported function, lifts its complete result, and destroys the
store. Replay repeats the whole invocation in another fresh store. This is
deterministic transformation and verification over explicit bytes; it is not a
long-lived Edict process.

Evidence:

- [Edict provider worlds](https://github.com/flyingrobots/edict/blob/296bf1f6c76af1e011f5214b6d3de260c67ca84a/docs/abi/edict-target-provider.wit#L211-L220)
- [Capability-denied provider boundary](https://github.com/flyingrobots/edict/blob/296bf1f6c76af1e011f5214b6d3de260c67ca84a/docs/topics/providers/architecture.md#L22-L50)
- [Synchronous lowerer and verifier calls](https://github.com/flyingrobots/edict/blob/296bf1f6c76af1e011f5214b6d3de260c67ca84a/crates/edict-provider-host-wasmtime/src/invocation.rs#L50-L145)

### Produced Echo operation

The generic Echo lowerer currently targets
`echo.dpo@1.anchored-node-attachment-create-if-absent`. The runtime has
canonical invocation shapes for anchored-node attachment compare-and-set and
create-if-absent. This operation mutates Echo-owned causal state; it does not
grant access to the host filesystem, a child process, Git, a network, GitHub,
or a model.

The resulting Action path is durable: acknowledgement follows accepted-action
WAL commit, scheduler construction owns private evaluation, a decided Tick is
committed before publication, and restart reconstructs retained outcomes. That
durability is reusable infrastructure, but the retained state is an Echo Action
and Tick, not an explicit external request, claim, settlement, or waiting state.

Evidence:

- [Generic lowerer target intrinsic](https://github.com/flyingrobots/echo/blob/eb0abb6ea90d1968e5d10922dc6d88eb7b361460/crates/echo-edict-provider-lowerer/src/executable_operation.rs#L17-L52)
- [Current invocation variants](https://github.com/flyingrobots/echo/blob/eb0abb6ea90d1968e5d10922dc6d88eb7b361460/crates/warp-core/src/echo_operation.rs#L1949-L2023)
- [Scheduler-owned Action and restart contract](https://github.com/flyingrobots/echo/blob/eb0abb6ea90d1968e5d10922dc6d88eb7b361460/docs/adr/0025-scheduler-owned-executable-operation-actions.md#L46-L80)
- [Atomic Tick durability and recovery](https://github.com/flyingrobots/echo/blob/eb0abb6ea90d1968e5d10922dc6d88eb7b361460/docs/adr/0025-scheduler-owned-executable-operation-actions.md#L148-L163)

### Native host code is not an Edict effect

The Edict CLI reads source and provider artifacts, invokes Wasmtime, and writes
build outputs. Echo's Rust host opens a filesystem WAL and advances the
scheduler. These are trusted native adapters surrounding the program. Their
existence does not make their operations callable from Edict, attenuable by an
Edict type, or resumable as Edict control flow.

The application-facing Echo handle deliberately excludes scheduler control,
package registration, ticketed staging, and recovery authority. It accepts
canonical intent submission and observation; the runtime owner retains Tick
control.

Evidence:

- [Application-facing authority boundary](https://github.com/flyingrobots/echo/blob/eb0abb6ea90d1968e5d10922dc6d88eb7b361460/crates/warp-core/src/trusted_runtime_host.rs#L5657-L5671)
- [Durable submission, not execution](https://github.com/flyingrobots/echo/blob/eb0abb6ea90d1968e5d10922dc6d88eb7b361460/crates/warp-core/src/trusted_runtime_host.rs#L5797-L5839)

## Required operation inventory

<!-- markdownlint-disable MD013 -->

| Delivery-loop operation | Exposed to Edict now | Gap class | Required extension |
| --- | --- | --- | --- |
| Process spawn | No | Genuine gap | Domain operations such as `RunRegisteredCheck`; a registry binds the operation to executable identity, environment, working directory, resource bounds, and result schema below the protocol. |
| Filesystem read | No | Genuine gap | `ObserveWorkspaceSnapshot` or a smaller read operation with bounded paths and bytes, symlink and race semantics, basis identity, and witnessed result data. |
| Filesystem write | No | Genuine gap | `ApplyValidatedPatch` over an admitted patch, exact basis, and explicit path set, with atomicity, postcondition, and ambiguous-outcome semantics. |
| Network egress | No | Genuine gap | Operation-specific adapters with fixed destination, protocol, credentials, request schema, response bounds, idempotency, and settlement law. No ambient network operation. |
| Git invocation | No | Genuine gap | Domain operations such as `PushFeatureRef` over an admitted repository, expected remote basis, feature ref, and commit. No arbitrary Git argv or force flag. |
| GitHub API | No | Genuine gap | Domain operations such as `OpenPullRequest` and `ObservePullRequestChecks`, each with repository scope, mutation class, idempotency, reconciliation, and durable settlement. |
| Model invocation | No | Genuine gap | `RequestModelJudgment` with explicit input and output schemas. Output is untrusted proposal data and carries no filesystem, Git, GitHub, process, or network authority. |

<!-- markdownlint-enable MD013 -->

The provider host's intentional denial of callable imports means none of these
can be added by linking a convenience host function into the current provider
world. Doing so would collapse the compiler-verification authority boundary.
They require a separate admitted runtime-effect contract.

## Waiting and resumption

An Edict provider call cannot wait on an external result. Its only legal
completion is a full lowerer/verifier result or a bounded host failure. There is
no effect-request record, callback import, or host entry point that resumes a
prior store.

Echo can recover accepted pending Actions and decided Ticks after process loss.
It does not currently persist an explicit program state waiting for an effect
request or correlate an external settlement with that request. CI and review
polling therefore cannot be expressed as a safe hosted wait.

Minimum state required of the extension:

```text
EffectRequested {
  run_id,
  transition_id,
  request_id,
  operation_identity,
  adapter_idempotency_key,
  program_binding_digest,
  authority_scope,
  basis,
  budget,
  canonical_input,
  input_digest
}

EffectDispatchClaimed {
  request_id,
  attempt,
  adapter_id,
  lease_owner,
  lease_epoch,
  witnessed_lease_deadline
}

EffectSettled {
  request_id,
  attempt,
  disposition: succeeded | rejected | failed | outcome_unknown,
  adapter_idempotency_key,
  program_binding_digest,
  canonical_outcome,
  outcome_digest
}

AwaitingEffect {
  program_binding_digest,
  state_schema,
  canonical_state,
  next_transition,
  awaited_request_id
}
```

`program_binding_digest` must immutably bind the admitted program, exact
capability set, authority policy, and program-state schema. `request_id` is
also the adapter-visible idempotency key unless an adapter declares a separate
stable key. A dispatch claim and its attempt number must commit before the
adapter is called. Lease expiry is not inferred from ambient time; the host
records the time or scheduler evidence used to authorize a new claim.

Recovery must enqueue a committed request with no dispatch claim. A claimed
request with no settlement remains owned until its witnessed lease expires.
After expiry, recovery may retry only a read-only effect or an adapter that
guarantees idempotency for the same key. Otherwise it records
`EffectSettled(disposition = outcome_unknown)` and takes the first-class
escalation transition; it must
not guess whether a Git push, GitHub mutation, process, or filesystem write
occurred.

A settlement must commit before the transition resumes and must match the exact
request id, idempotency key, program binding, input, adapter, attempt policy,
and outcome schema. Duplicate settlement, unknown correlation, changed program
or capability identity, stale state schema, noncanonical outcome, and an
outcome from an unauthorized adapter must fail closed.

The waiting state is ordinary canonical program state plus admitted history. It
is not a serialized native stack, hidden callback, or language-level
`async`/`await` continuation.

## Request capability representation

Edict has capability-related data, but not the typed request construction
required by an external-action protocol:

- `CapabilityRef<T>` is an inert receipt reference until admission;
- admission records can require matching capability evidence;
- `use capability` is explicitly rejected by the v1 parser; and
- the current provider component receives no callable capability.

These mechanisms bind evidence and prevent ambient input. They do not let an
application declare and construct a typed external request whose operation
identity, input schema, output schema, scope, basis, and budget are preserved
through Core and package closure.

Evidence:

- [Capability references are inert](https://github.com/flyingrobots/edict/blob/296bf1f6c76af1e011f5214b6d3de260c67ca84a/docs/REQUIREMENTS.md#L68-L70)
- [Capability imports are rejected in v1](https://github.com/flyingrobots/edict/blob/296bf1f6c76af1e011f5214b6d3de260c67ca84a/crates/edict-syntax/src/parser.rs#L478-L495)
- [Hidden effects require explicit canonical or admitted input](https://github.com/flyingrobots/edict/blob/296bf1f6c76af1e011f5214b6d3de260c67ca84a/docs/REQUIREMENTS.md#L83-L86)

A minimal language and Core representation may be substantially smaller than a
general-purpose algebraic-effect system:

```text
external operation Op<Input, Settlement>
request op(input, authority_scope, basis, budget)
  -> EffectRequest<Op, Settlement>
```

The package closure determines which operation families the program may
request. Absence from that closure is a compile-time or package-verification
failure. Echo admission validates dynamic request instances such as resolved
paths, refs, bases, budgets, and adapter identity before execution. An adapter,
not the Edict program, owns the credential or operating-system capability.

Judgment calls follow the same split. A model returns a schema-bound proposal.
Deterministic law validates it. Only then may Echo admit an operation-specific
request for an adapter to perform. The model never receives write authority.

## Named blockers

1. **Joint Edict/Echo boundary RFC.** Define operation identity, request
   construction, package closure, request admission, claim, settlement,
   correlation, idempotency, reconciliation, and replay law before code.
2. **Edict typed request values.** Preserve declared external-operation
   identities and request schemas through syntax, Core, and package closure
   without adding provider imports or ambient authority.
3. **Echo durable external-action protocol.** Commit requests before adapter
   execution, settlements before program resumption, and explicit waiting state
   for recovery.
4. **One narrow adapter proof.** Prove bounded read-only workspace observation
   before basis-bound patch application and before process, Git, GitHub, or
   model adapters.
5. **Complete lawpack closure transport.** The current singleton provider
   closure is separately tracked by
   [Echo #693](https://github.com/flyingrobots/echo/issues/693) and
   [Edict #171](https://github.com/flyingrobots/edict/issues/171). It is
   necessary for general applications but does not by itself supply any
   delivery-loop effect.

The first four blockers form a separate cross-repository campaign. The full
self-hosted delivery loop remains Roadmap Ω. Roadmap A resumes the pure
compiler-to-runtime Hello Echo witness described by `docs/roadmap.md`.
