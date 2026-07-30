# Compiler-Owned Workspace-Patch Closure

The checked artifacts in this directory were copied without modification from
Edict merge commit `cf8c17f917b7262be2c89fa136898e01dab7f40a`:

- `manifest.cbor` and `manifest.sha256`;
- `exports.cbor` and `exports.sha256`;
- `adapter.cbor` and `adapter.sha256`; and
- `request-profile-configuration.cbor` and
  `request-profile-configuration.sha256`.

Edict owns these bytes. Regenerate them in Edict with:

```sh
cargo xtask lawpack-goldens --write
cargo xtask lawpack-goldens
```

Then copy the eight exact files and
`fixtures/lawpack/workspace-patch/apply-validated-patch.edict` into this
repository. `tests/patch-build.sh` compares the complete local closure with the
selected Edict checkout before invoking the public application build.

Hello Echo does not regenerate, reinterpret, or replace the closure. Echo owns
dynamic admission, bounded mutation, durable settlement, reconciliation, and
effect-free replay.
