[CmdletBinding()]
param(
    [ValidateSet("Plan", "TransactionOnly")]
    [string]$Mode = "Plan",

    [string]$Approval = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 9C.4D2D4B: KTM transaction-HANDLE capability only.
# No Registry reads/writes or resource-manager enlistment in either mode.
# The TransactionOnly mode must not be run without separate approval.

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "Windows required"
}
if (-not [Environment]::Is64BitProcess) {
    throw "64-bit PowerShell required"
}

$managerPath = Join-Path $PSScriptRoot "browser-native-host-registration.ps1"
$manager = [IO.File]::ReadAllText(
    (Resolve-Path -LiteralPath $managerPath).Path
)
$guardPosition = $manager.IndexOf('throw "WRITE_MODES_SUSPENDED_9C4D2D2"')
$readPosition = $manager.IndexOf('$userEntries = @(')
$writePosition = $manager.IndexOf('$root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(')
if ($guardPosition -lt 0 -or
    $readPosition -le $guardPosition -or
    $writePosition -le $guardPosition) {
    throw "PRODUCTION_WRITE_BARRIER_MISSING_OR_MOVED"
}

Write-Host "MODE=$Mode"
Write-Host "OS=$([Environment]::OSVersion.VersionString)"
Write-Host "PROCESS_64_BIT=YES"
Write-Host "PRODUCTION_WRITE_BARRIER=PRESERVED"
Write-Host "SCOPE=KTM_HANDLE_ONLY_NO_REGISTRY_ENLISTMENT"

if ($Mode -eq "Plan") {
    # This branch must return before Add-Type and all KTM API calls.
    Write-Host "TRANSACTION_CREATED=NO"
    Write-Host "KTM_HANDLE_RUNTIME_VERIFIED=NO"
    Write-Host "TXR_REGISTRY_RUNTIME_VERIFIED=NO"
    Write-Host "TXR_RUNTIME_VERIFIED=NO"
    Write-Host "ATOMIC_COMPARE_DELETE_VERIFIED=NO"
    Write-Host "REGISTRY_READS=NO"
    Write-Host "REGISTRY_WRITES=NO"
    Write-Host "BROWSER_REGISTRY_KEYS_TOUCHED=NO"
    Write-Host "PRODUCTION_MANAGER_INTEGRATION=NO"
    Write-Host "TXR_RUNTIME_PLAN_COMPLETE"
    return
}

if ($Approval -cne "RUN_TRANSACTION_ONLY_9C4D2D4B") {
    throw "TRANSACTION_ONLY_APPROVAL_REQUIRED"
}

if ($null -eq ("ArfKtmHandleOnlyProbe9C4D2D4B" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public sealed class ArfKtmHandleOnlyResult9C4D2D4B
{
    public bool Created;
    public bool RolledBack;
    public bool Closed;
    public int CreateError;
    public int RollbackError;
    public int CloseError;
}

public static class ArfKtmHandleOnlyProbe9C4D2D4B
{
    [DllImport("ktmw32.dll", EntryPoint = "CreateTransaction",
        CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateNativeTransaction(
        IntPtr attributes, IntPtr uow, uint options,
        uint isolation, uint isolationFlags, uint timeout,
        string description);

    [DllImport("ktmw32.dll", EntryPoint = "RollbackTransaction",
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RollbackNativeTransaction(IntPtr handle);

    [DllImport("kernel32.dll", EntryPoint = "CloseHandle",
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseNativeHandle(IntPtr handle);

    public static ArfKtmHandleOnlyResult9C4D2D4B Run()
    {
        var r = new ArfKtmHandleOnlyResult9C4D2D4B();
        IntPtr h = CreateNativeTransaction(
            IntPtr.Zero, IntPtr.Zero, 0, 0, 0, 5000,
            "ARF 9C4D2D4B no-registry handle-only test");
        if (h == IntPtr.Zero || h == new IntPtr(-1))
        {
            r.CreateError = Marshal.GetLastWin32Error();
            return r;
        }

        r.Created = true;
        try
        {
            r.RolledBack = RollbackNativeTransaction(h);
            if (!r.RolledBack)
                r.RollbackError = Marshal.GetLastWin32Error();
        }
        finally
        {
            // Uncommitted KTM transactions also roll back on last-handle close.
            r.Closed = CloseNativeHandle(h);
            if (!r.Closed)
                r.CloseError = Marshal.GetLastWin32Error();
        }
        return r;
    }
}
"@ -ErrorAction Stop
}

$result = [ArfKtmHandleOnlyProbe9C4D2D4B]::Run()
$created = if ($result.Created) { "YES" } else { "NO" }
$rolled = if ($result.RolledBack) { "YES" } else { "NO" }
$closed = if ($result.Closed) { "YES" } else { "NO" }
$verified = if ($result.Created -and $result.RolledBack -and $result.Closed) {
    "YES"
} else {
    "NO"
}

Write-Host "TRANSACTION_CREATED=$created"
Write-Host "ROLLBACK_SUCCEEDED=$rolled"
Write-Host "TRANSACTION_HANDLE_CLOSED=$closed"
Write-Host "CREATE_ERROR_CODE=$($result.CreateError)"
Write-Host "ROLLBACK_ERROR_CODE=$($result.RollbackError)"
Write-Host "CLOSE_ERROR_CODE=$($result.CloseError)"
Write-Host "KTM_HANDLE_RUNTIME_VERIFIED=$verified"
Write-Host "TXR_REGISTRY_RUNTIME_VERIFIED=NO"
Write-Host "TXR_RUNTIME_VERIFIED=NO"
Write-Host "ATOMIC_COMPARE_DELETE_VERIFIED=NO"
Write-Host "REGISTRY_READS=NO"
Write-Host "REGISTRY_WRITES=NO"
Write-Host "BROWSER_REGISTRY_KEYS_TOUCHED=NO"
Write-Host "PRODUCTION_MANAGER_INTEGRATION=NO"

if ($verified -cne "YES") {
    throw "KTM_HANDLE_RUNTIME_PROBE_UNAVAILABLE_OR_FAILED"
}

Write-Host "KTM_HANDLE_ONLY_PROBE_COMPLETE"
