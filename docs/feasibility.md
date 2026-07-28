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

The delivery loop requires process, filesystem, network, Git, GitHub, and model
effects plus durable suspension while external work completes. None is exposed
to an Edict program. Adding them requires a language-level effect-capability
model, attenuated host adapters, and a durable external-effect continuation
protocol. Those are genuine architecture gaps, not additional provider roles
or small target-lowering extensions.

No delivery-loop implementation may begin on this seam. The next permitted
artifact is the syntax-independent phase graph in `docs/phase-graph.md`.

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
and Tick, not a suspended external-effect continuation.

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
| Process spawn | No | Genuine gap | A typed process capability with executable identity, argv, environment, working-directory, resource, and output bounds; an Echo-owned effect adapter; durable request/result evidence. |
| Filesystem read | No | Genuine gap | A read capability attenuated to canonical roots and byte limits, with symlink and race semantics specified; witnessed bytes and metadata returned as canonical input. |
| Filesystem write | No | Genuine gap | A write capability attenuated to an explicit path set and operation class, with atomicity, overwrite, CI-workflow exclusion, and durable outcome semantics. |
| Network egress | No | Genuine gap | A destination-, protocol-, credential-, request-, and response-bounded network capability plus a durable asynchronous effect adapter. |
| Git invocation | No | Genuine gap | Typed Git operations over an identified repository and ref policy. Raw shell access cannot encode the no-force, no-rebase, no-main-push envelope. |
| GitHub API | No | Genuine gap | Typed REST/GraphQL capabilities scoped by repository and mutation class, including native issue-dependency operations, authentication isolation, idempotency, rate-limit results, and durable polling. |
| Model invocation | No | Genuine gap | A typed model-call operation whose prompt/input scope is explicit, whose output is untrusted bytes, and whose result must pass a declared schema before any transition can consume it. |

<!-- markdownlint-enable MD013 -->

The provider host's intentional denial of callable imports means none of these
can be added by linking a convenience host function into the current provider
world. Doing so would collapse the compiler-verification authority boundary.
They require a separate admitted runtime-effect contract.

## Suspension and resumption

An Edict provider call cannot suspend on an external result. Its only legal
completion is a full lowerer/verifier result or a bounded host failure. There is
no await token, continuation identity, effect-request record, callback import,
or host entry point that resumes a prior store.

Echo can recover accepted pending Actions and decided Ticks after process loss.
It does not currently persist an Edict continuation at an effect boundary or
correlate an external response with such a continuation. CI and review polling
therefore cannot be expressed as a safe hosted wait.

Minimum state required of the extension:

```text
EffectRequested {
  run_id,
  transition_id,
  effect_id,
  adapter_idempotency_key,
  program_binding_digest,
  capability,
  canonical_request,
  request_digest
}

EffectDispatchClaimed {
  effect_id,
  attempt,
  adapter_id,
  lease_owner,
  lease_epoch,
  witnessed_lease_deadline
}

EffectCompleted | EffectFailed {
  effect_id,
  adapter_idempotency_key,
  program_binding_digest,
  canonical_result,
  result_digest
}

EffectOutcomeUnknown {
  effect_id,
  attempt,
  reason
}

SuspendedContinuation {
  program_binding_digest,
  state_schema,
  canonical_state,
  next_transition,
  awaited_effect_id
}
```

`program_binding_digest` must immutably bind the admitted program, exact
capability set, authority policy, and continuation-state schema. `effect_id` is
also the adapter-visible idempotency key unless an adapter declares a separate
stable key. A dispatch claim and its attempt number must commit before the
adapter is called. Lease expiry is not inferred from ambient time; the host
records the time or scheduler evidence used to authorize a new claim.

Recovery must enqueue a committed request with no dispatch claim. A claimed
request with no completion remains owned until its witnessed lease expires.
After expiry, recovery may retry only a read-only effect or an adapter that
guarantees idempotency for the same key. Otherwise it records
`EffectOutcomeUnknown` and takes the first-class escalation transition; it must
not guess whether a Git push, GitHub mutation, process, or filesystem write
occurred.

A completion must commit before the transition resumes and must match the exact
effect id, idempotency key, program binding, request, adapter, attempt policy,
and result schema. Duplicate completion, unknown correlation, changed program
or capability identity, stale state schema, noncanonical result, and a result
from an unauthorized adapter must fail closed.

## Effect capability representation

Edict has capability-related data, but not the capability type system required
by the loop:

- `CapabilityRef<T>` is an inert receipt reference until admission;
- admission records can require matching capability evidence;
- `use capability` is explicitly rejected by the v1 parser; and
- the current provider component receives no callable capability.

These mechanisms bind evidence and prevent ambient input. They do not make
`FsWrite<Paths>`, `GitPush<NonMainRef>`, or
`GitHubMutation<Repository, OperationSet>` available as compiler-checked
effects, and they cannot attenuate authority passed to a judgment leaf.

Evidence:

- [Capability references are inert](https://github.com/flyingrobots/edict/blob/296bf1f6c76af1e011f5214b6d3de260c67ca84a/docs/REQUIREMENTS.md#L68-L70)
- [Capability imports are rejected in v1](https://github.com/flyingrobots/edict/blob/296bf1f6c76af1e011f5214b6d3de260c67ca84a/crates/edict-syntax/src/parser.rs#L478-L495)
- [Hidden effects require explicit canonical or admitted input](https://github.com/flyingrobots/edict/blob/296bf1f6c76af1e011f5214b6d3de260c67ca84a/docs/REQUIREMENTS.md#L83-L86)

A new language and Core representation is required:

```text
effect capability Cap<Scope, Operations, Limits>
operation op : (Cap<...>, Input) -> Effect<Result, Failure>
```

Capability construction remains host-owned. An Edict program may only receive,
attenuate, and consume declared capabilities. Capability absence, an
out-of-scope path, a forbidden Git ref, or an undeclared network destination
must be rejected before execution. Runtime validation remains necessary for
race-dependent facts such as the actual resolved filesystem object and remote
ref state.

## Named blockers

1. **Edict effect-capability types.** Add declared effect capabilities,
   operation sets, static attenuation, and Core preservation.
2. **Durable external-effect protocol.** Add explicit request, suspended-state,
   completion, idempotency, and recovery records to the Echo-hosted lifecycle.
3. **Attenuated host adapters.** Add typed filesystem, process, Git, and
   network/GitHub adapters without granting a generic shell or ambient network.
4. **Schema-validated judgment calls.** Add a model-call effect whose output is
   untrusted until canonical schema admission succeeds.
5. **Complete lawpack closure transport.** The current singleton provider
   closure is separately tracked by
   [Echo #693](https://github.com/flyingrobots/echo/issues/693) and
   [Edict #171](https://github.com/flyingrobots/edict/issues/171). It is
   necessary for general applications but does not by itself supply any
   delivery-loop effect.

The first four blockers are architectural prerequisites. Until they land with
negative compile-time and seam tests, the self-hosted delivery loop remains a
specification.
