# TEST ONLY. Never use this module for production registrations.
# Restricted to HKCU\Software\AutoReverseTypoFixer\IsolatedRegistryTests.
# The cleanup comparison is not atomic against external writers.

. (Join-Path $PSScriptRoot "browser-registration-transaction.ps1")

$script:ArfTestPrefix = "Software\AutoReverseTypoFixer\IsolatedRegistryTests"

function Assert-ArfTestLeaf {
    param([string]$Leaf)

    if ($Leaf -cnotmatch '^arf-[a-f0-9]{32}$') {
        throw "Invalid isolated-test leaf"
    }
}

function Initialize-ArfTestNativeApi {
    if ($null -ne ("ArfIsolatedRegistryNative" -as [type])) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32;

public static class ArfIsolatedRegistryNative
{
    [DllImport("advapi32.dll", EntryPoint="RegCreateKeyExW",
        CharSet=CharSet.Unicode)]
    private static extern int RegCreateKeyEx(
        IntPtr hKey, string subKey, int reserved, IntPtr className,
        int options, int access, IntPtr security,
        out IntPtr result, out int disposition);

    [DllImport("advapi32.dll")]
    private static extern int RegCloseKey(IntPtr key);

    public static int Create(string subkey)
    {
        using (RegistryKey root = RegistryKey.OpenBaseKey(
            RegistryHive.CurrentUser, RegistryView.Registry64))
        {
            IntPtr result = IntPtr.Zero;
            int disposition = 0;

            int code = RegCreateKeyEx(
                root.Handle.DangerousGetHandle(),
                subkey, 0, IntPtr.Zero, 0, 0x2001F,
                IntPtr.Zero, out result, out disposition);

            if (result != IntPtr.Zero)
                RegCloseKey(result);

            if (code != 0)
                throw new Win32Exception(code);

            return disposition;
        }
    }
}
"@ -ErrorAction Stop
}

function New-ArfIsolatedTestKey {
    param([Parameter(Mandatory)][string]$Leaf)

    Assert-ArfTestLeaf $Leaf

    Initialize-ArfTestNativeApi

    $path = "$script:ArfTestPrefix\$Leaf"
    $disposition = [ArfIsolatedRegistryNative]::Create($path)

    switch ($disposition) {
        1 { return "CREATED_NEW" }
        2 { return "ALREADY_EXISTS" }
        default { throw "Unexpected Registry disposition" }
    }
}

function Get-ArfIsolatedTestState {
    param([Parameter(Mandatory)][string]$Leaf)

    Assert-ArfTestLeaf $Leaf

    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::CurrentUser,
        [Microsoft.Win32.RegistryView]::Registry64
    )

    try {
        $key = $root.OpenSubKey(
            "$script:ArfTestPrefix\$Leaf", $false
        )

        if ($null -eq $key) {
            return [pscustomobject]@{
                Exists = $false
                Children = 0
                Values = @{}
            }
        }

        try {
            $values = @{}

            foreach ($name in @($key.GetValueNames())) {
                if ($key.GetValueKind($name) -ne
                    [Microsoft.Win32.RegistryValueKind]::String) {
                    throw "Unexpected Registry value type"
                }

                $value = $key.GetValue($name)

                if ($value -isnot [string]) {
                    throw "Unexpected Registry value content"
                }

                $values[$name] = $value
            }

            return [pscustomobject]@{
                Exists = $true
                Children = [int]$key.SubKeyCount
                Values = $values
            }
        }
        finally {
            $key.Close()
        }
    }
    finally {
        $root.Close()
    }
}

function Set-ArfIsolatedTestValue {
    param(
        [Parameter(Mandatory)][string]$Leaf,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    Assert-ArfTestLeaf $Leaf

    if (@("", "ARFManagedBy", "ARFRegisteredOrigin") -cnotcontains $Name) {
        throw "Unexpected test value name"
    }

    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::CurrentUser,
        [Microsoft.Win32.RegistryView]::Registry64
    )

    try {
        $key = $root.OpenSubKey(
            "$script:ArfTestPrefix\$Leaf", $true
        )

        if ($null -eq $key) {
            throw "Test key disappeared"
        }

        try {
            $key.SetValue(
                $Name, $Value,
                [Microsoft.Win32.RegistryValueKind]::String
            )
        }
        finally {
            $key.Close()
        }
    }
    finally {
        $root.Close()
    }
}

function Get-ArfTestStateSignature {
    param([object]$State)

    $pairs = @(
        foreach ($name in @($State.Values.Keys | Sort-Object)) {
            "$name=$($State.Values[$name])"
        }
    )

    return "$($State.Exists)|$($State.Children)|$($pairs -join ';')"
}

function Remove-ArfIsolatedTestKey {
    param(
        [Parameter(Mandatory)][string]$Leaf,
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Origin,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][bool]$CreationConfirmed
    )

    Assert-ArfTestLeaf $Leaf

    if (-not $CreationConfirmed) {
        throw "Unproven creation; deletion denied"
    }

    $before = Get-ArfIsolatedTestState $Leaf

    if (-not $before.Exists) {
        return "ALREADY_ABSENT"
    }

    if (-not (Test-ArfTransactionState `
        -State $before `
        -Owner $Owner `
        -Origin $Origin `
        -ManifestPath $ManifestPath)) {
        throw "Unsafe test key state; refusing deletion"
    }

    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::CurrentUser,
        [Microsoft.Win32.RegistryView]::Registry64
    )

    try {
        $parent = $root.OpenSubKey($script:ArfTestPrefix, $true)

        if ($null -eq $parent) {
            throw "Test parent disappeared"
        }

        try {
            $fresh = Get-ArfIsolatedTestState $Leaf

            if ((Get-ArfTestStateSignature $fresh) -cne
                (Get-ArfTestStateSignature $before)) {
                throw "Test key changed; refusing deletion"
            }

            $parent.DeleteSubKey($Leaf, $false)
        }
        finally {
            $parent.Close()
        }
    }
    finally {
        $root.Close()
    }

    if ((Get-ArfIsolatedTestState $Leaf).Exists) {
        throw "Test key cleanup unverified"
    }

    return "REMOVED"
}