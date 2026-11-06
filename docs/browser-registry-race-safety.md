# Browser Registry Race Safety Contract

## Current status

The production Native Messaging registration manager has a
fail-closed barrier (`WRITE_MODES_SUSPENDED_9C4D2D2`).

Register and Unregister are intentionally unavailable.
Plan remains read-only.

## Threat model

An external process can change a Registry key after a snapshot
has been read and before a deletion is executed.

Important cases:

1. Ownership value changes.
2. Extension origin changes.
3. Manifest path changes.
4. An additional value appears.
5. A child key appears.
6. The key is deleted and replaced.
7. A different key appears with identical visible values (ABA).
8. The key disappears entirely.

A second snapshot does not eliminate the interval between
verification and deletion.

## Required properties before enabling production operations

- Never overwrite a pre-existing or unmanaged registration.
- Never delete a ChromiumShared key automatically while its
  dependent browser integrations may still use it.
- Require proof that registration creation was exclusive.
- Validate exact owner, origin, manifest, names, value types,
  children, scope and registry view.
- Do not assume matching values establish key identity.
- Do not treat compare-then-delete as an atomic operation.
- Require a supported Windows-native transaction or another
  independently reviewed mechanism for atomic correctness.
- Validate conflicts, failures, cleanup and actual Windows
  compatibility before enabling any destructive operation.
- Fail closed when the required guarantee is unavailable.

## Test limitations

The race model is entirely in memory.

`SnapshotNameDelete` demonstrates the flaw of deleting a
named key after an earlier inspection.

`AtomicOracle` represents a hypothetical atomic
compare-and-delete primitive. It is not an implementation
of a Windows API and does not prove Registry safety.

Existing isolated Registry tests are also not a guarantee
against arbitrary external writers.

## Release gate

No production Register or Unregister operation may be
re-enabled merely because these model tests pass.

The installer must preserve unmanaged registrations.
Browser text correction remains disabled.