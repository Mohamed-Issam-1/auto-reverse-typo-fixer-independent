# Windows Transacted Registry Capability Evaluation

## Scope

This evaluation checks whether required Windows API exports
are present. It does not create a transaction or open,
create, modify, or delete any Registry key.

The probe loads system DLLs using LOAD_LIBRARY_SEARCH_SYSTEM32
and checks native exported function names.

## APIs inspected

KtmW32.dll:
- CreateTransaction
- CommitTransaction
- RollbackTransaction

Advapi32.dll:
- RegCreateKeyTransactedW
- RegOpenKeyTransactedW
- RegDeleteKeyTransactedW
- RegSetValueExW
- RegCloseKey

## Important limitations

An available function export does not establish that the
transaction can be started, committed, or rolled back on
the current Windows installation.

A transacted deletion does not by itself prove that an
ownership comparison and key deletion are atomic against
arbitrary external changes.

The next step must investigate real Windows runtime
behavior under a strictly isolated test path.

A non-transactional read followed by a transacted delete
must not be treated as a safe atomic compare-and-delete.

Test results must explicitly cover errors, conflicts,
key replacement, rollback, registry views, and cleanup.

TxR should not be adopted without reviewing platform
support, deployment compatibility, and alternative designs.

## Production requirements

The production registration manager continues to reject
Register and Unregister operations with
WRITE_MODES_SUSPENDED_9C4D2D2.

Unmanaged Chrome/Brave registrations are preserved.
Browser text correction remains disabled.

No production write mode may be enabled on the basis
of exported API names alone.

## Documentation

https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regcreatekeytransactedw

https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regopenkeytransactedw

https://learn.microsoft.com/en-us/windows/desktop/api/winreg/nf-winreg-regdeletekeytransacteda