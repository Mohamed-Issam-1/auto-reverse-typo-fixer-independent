[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Read-only export inspection.
# No transaction creation, registry key access, or registry writes.

if ([Environment]::OSVersion.Platform -ne
    [PlatformID]::Win32NT) {
    throw "Windows required"
}

if (-not [Environment]::Is64BitProcess) {
    throw "64-bit process required"
}

if ($null -eq ("ArfTxrExportProbeV1" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ArfTxrExportProbeV1
{
    // LOAD_LIBRARY_SEARCH_SYSTEM32 = 0x00000800
    private const uint System32Only = 0x00000800;

    [DllImport("kernel32.dll",
        EntryPoint = "LoadLibraryExW",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    private static extern IntPtr LoadSystemLibrary(
        string fileName, IntPtr reserved, uint flags);

    [DllImport("kernel32.dll",
        EntryPoint = "GetProcAddress",
        CharSet = CharSet.Ansi,
        SetLastError = true)]
    private static extern IntPtr FindExport(
        IntPtr module, string exportName);

    [DllImport("kernel32.dll",
        EntryPoint = "FreeLibrary",
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ReleaseLibrary(IntPtr module);

    public static bool HasExport(string library, string symbol)
    {
        IntPtr module = LoadSystemLibrary(
            library, IntPtr.Zero, System32Only);

        if (module == IntPtr.Zero)
            return false;

        try
        {
            return FindExport(module, symbol) != IntPtr.Zero;
        }
        finally
        {
            ReleaseLibrary(module);
        }
    }
}
"@ -ErrorAction Stop
}

$apis = @(
    @{ Library = "ktmw32.dll"; Symbol = "CreateTransaction" }
    @{ Library = "ktmw32.dll"; Symbol = "CommitTransaction" }
    @{ Library = "ktmw32.dll"; Symbol = "RollbackTransaction" }

    @{ Library = "advapi32.dll"; Symbol = "RegCreateKeyTransactedW" }
    @{ Library = "advapi32.dll"; Symbol = "RegOpenKeyTransactedW" }
    @{ Library = "advapi32.dll"; Symbol = "RegDeleteKeyTransactedW" }
    @{ Library = "advapi32.dll"; Symbol = "RegSetValueExW" }
    @{ Library = "advapi32.dll"; Symbol = "RegCloseKey" }
)

Write-Host "`n=== WINDOWS TXR API CAPABILITIES ==="
Write-Host "MODE=EXPORT_INSPECTION_ONLY"
Write-Host "OS=$([Environment]::OSVersion.VersionString)"
Write-Host "PROCESS_64_BIT=YES"

$allPresent = $true

foreach ($api in $apis) {
    $present = [ArfTxrExportProbeV1]::HasExport(
        $api.Library,
        $api.Symbol
    )

    Write-Host "EXPORT=$($api.Library):$($api.Symbol);PRESENT=$present"

    if (-not $present) {
        $allPresent = $false
    }
}

$exportState = if ($allPresent) {
    "COMPLETE"
}
else {
    "INCOMPLETE"
}

Write-Host ""
Write-Host "API_EXPORT_SET=$exportState"
Write-Host "TRANSACTION_CREATED=NO"
Write-Host "TXR_RUNTIME_VERIFIED=NO"
Write-Host "ATOMIC_COMPARE_DELETE_VERIFIED=NO"
Write-Host "PRODUCTION_MANAGER_INTEGRATION=NO"
Write-Host "REGISTRY_WRITES=NO"
Write-Host "TXR_CAPABILITY_PROBE_COMPLETE"