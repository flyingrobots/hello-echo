# Compiler-Owned Workspace-Patch Closure

The checked artifacts in this directory were copied without modification from
Edict merge commit `df80f92ad6242c6da31a64224666fd37aa43b0d0`:

- `manifest.cbor` and `manifest.sha256`;
- `exports.cbor` and `exports.sha256`;
- `adapter.cbor` and `adapter.sha256`;
- `request-profile-configuration.cbor` and
  `request-profile-configuration.sha256`;
- `input-schema.cbor` and `input-schema.sha256`;
- `settlement-schema.cbor` and `settlement-schema.sha256`; and
- `reconciliation-law.cbor` and `reconciliation-law.sha256`.

The last three are canonical `edict.external-action-resource/v1` artifacts.
`apply-validated-patch.edict` pins their exact identities for
`workspace.patch.input@1`, `workspace.patch.settlement@1`, and
`workspace.patch.reconcile@1`. `edict.patch.application.json` supplies the same
three artifact paths through `externalActionResources`, and Edict recomputes
and validates the complete closure before publishing Core or Target IR. A
digest that names no supplied artifact fails the build closed.

Each `.sha256` sidecar carries the generator-owned canonical resource identity,
not a digest of the enclosing file's bytes.

Edict owns these bytes. Regenerate them in Edict with:

```sh
cargo xtask lawpack-goldens --write
cargo xtask lawpack-goldens
```

Then copy the fourteen exact files and
`fixtures/lawpack/workspace-patch/apply-validated-patch.edict` into this
repository. `tests/patch-build.sh` compares the complete local closure with the
selected Edict checkout before invoking the public application build. Edict
owns validation of that closure and refuses malformed, missing, substituted,
and unresolved resources; Hello Echo does not reparse the source to re-check
what the compiler already enforces.

Hello Echo does not regenerate, reinterpret, or replace the closure. Echo owns
dynamic admission, bounded mutation, durable settlement, reconciliation, and
effect-free replay.
