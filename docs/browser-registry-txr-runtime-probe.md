# Batch 9C.4D2D4B: KTM transaction-handle runtime probe

## Status

This is a **test-only** diagnostic, not a browser Native Messaging registration implementation.
The production barrier `WRITE_MODES_SUSPENDED_9C4D2D2` stays in place.
No Registry key is read, opened, created, modified, or removed by this probe.

The default `Plan` mode reads the source of the production registration manager to
verify the existing fail-closed barrier and prints its scope and limitations.
It returns before compilation or any native Windows transaction call.
CI runs only this Plan mode and static regression tests.

`TransactionOnly` mode is **not included in CI** and requires a separate explicit
user approval string. It creates one unnamed KTM transaction handle with
`CreateTransaction`, calls `RollbackTransaction`, and closes the handle in
`finally`. No registry resource manager is enlisted. An unavailable or failed
KTM operation is reported as a failure, not proof of Windows Registry safety.
Even a successful handle-only probe does **not** prove `RegCreateKeyTransactedW`,
`RegDeleteKeyTransactedW`, any Registry view behavior, or correctness under
concurrent writers.

## Local commands (Windows PowerShell 5.1 x64)

Plan only (safe; no native transaction is created):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\browser-registry-txr-runtime-probe.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\test-browser-registry-txr-runtime-probe.ps1
```

**Do not execute `TransactionOnly` until it has been separately authorized.**
The approval string is checked exactly before any native operation.

## Claims that remain false regardless of handle-only success

- `TXR_REGISTRY_RUNTIME_VERIFIED=NO`
- `TXR_RUNTIME_VERIFIED=NO` (Registry transactional behavior remains untested)
- `ATOMIC_COMPARE_DELETE_VERIFIED=NO`
- `PRODUCTION_MANAGER_INTEGRATION=NO`
- `REGISTRY_WRITES=NO`

Future evaluation of actual Registry transactions, 32-/64-bit views,
concurrent interference and ABA requires a separate, explicitly scoped
isolated-path proposal, snapshots and user approval. A successful native
transaction does not authorize enabling production Register or Unregister.

Relevant Microsoft API references:

- https://learn.microsoft.com/en-us/windows/win32/api/ktmw32/nf-ktmw32-createtransaction
- https://learn.microsoft.com/en-us/windows/win32/api/ktmw32/nf-ktmw32-rollbacktransaction
