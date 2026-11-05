Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "browser-registration-policy.ps1")

$script:testPath = "C:\ARF-Isolated-Test\health.json"
$script:testOwner = "ARF-9C4B-Manager-v1"
$script:testOrigin = "chrome-extension://kbbpbandkpaakicmlleoaafgadncfcfj/"
$script:passed = 0

function New-Entry {
    param(
        [string]$P = $script:testPath,
        [string]$O = $script:testOwner,
        [string]$R = $script:testOrigin,
        [string[]]$Values = @(
            "", "ARFManagedBy", "ARFRegisteredOrigin"
        ),
        [int]$Children = 0
    )

    return [pscustomobject]@{
        Path = $P
        Owner = $O
        Origin = $R
        Values = @($Values)
        Children = $Children
    }
}

function Assert-Case {
    param(
        [string]$Name,
        [string]$Expected,
        [hashtable]$Changes
    )

    $inputs = @{
        Mode = "Register"
        ManifestValid = $true
        OriginAllowlisted = $true
        ManifestPath = $script:testPath
        ExtensionOrigin = $script:testOrigin
        Owner = $script:testOwner
        UserEntries = @()
        MachineEntries = @()
    }

    foreach ($key in $Changes.Keys) {
        $inputs[$key] = $Changes[$key]
    }

    $actual = Get-ArfRegistrationDecision @inputs

    if ($actual -cne $Expected) {
        throw "$Name FAILED: expected=$Expected actual=$actual"
    }

    $script:passed++
    Write-Host "PASS $Name : $actual"
}

Assert-Case "REGISTER_EMPTY" "ALLOW_REGISTER" @{}

Assert-Case "REGISTER_OWNED_EXISTS" "DENY_ALREADY_REGISTERED" @{
    UserEntries = @(New-Entry)
}

Assert-Case "REGISTER_FOREIGN_EXISTS" "DENY_ALREADY_REGISTERED" @{
    UserEntries = @(New-Entry -O "External")
}

Assert-Case "REGISTER_MACHINE_CONFLICT" "DENY_MACHINE_REGISTRATION" @{
    MachineEntries = @(New-Entry)
}

Assert-Case "REGISTER_INVALID_MANIFEST" "DENY_INVALID_MANIFEST" @{
    ManifestValid = $false
}

Assert-Case "REGISTER_ORIGIN_DENIED" "DENY_ORIGIN_NOT_ALLOWLISTED" @{
    OriginAllowlisted = $false
}

Assert-Case "REGISTER_INVALID_ORIGIN" "DENY_INVALID_EXTENSION_ORIGIN" @{
    ExtensionOrigin = "chrome-extension://invalid/"
}

Assert-Case "REGISTER_PATH_CONFLICT" "DENY_PATH_CONFLICT" @{
    UserEntries = @(New-Entry -P "C:\Other\host.json")
}

Assert-Case "REGISTER_MISSING_OWNER" "DENY_MISSING_IDENTITY" @{
    Owner = ""
}

Assert-Case "REGISTER_NULL_ENTRY" "DENY_MALFORMED_REGISTRATION" @{
    UserEntries = @($null)
}

Assert-Case "UNREGISTER_OWNED" "ALLOW_UNREGISTER" @{
    Mode = "Unregister"
    UserEntries = @(New-Entry)
}

Assert-Case "UNREGISTER_NOT_FOUND" "DENY_NOT_REGISTERED" @{
    Mode = "Unregister"
}

Assert-Case "UNREGISTER_FOREIGN" "DENY_UNMANAGED_REGISTRATION" @{
    Mode = "Unregister"
    UserEntries = @(New-Entry -O "External")
}

Assert-Case "UNREGISTER_WRONG_ORIGIN" "DENY_ORIGIN_MISMATCH" @{
    Mode = "Unregister"
    UserEntries = @(
        New-Entry -R "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"
    )
}

Assert-Case "UNREGISTER_CHILD_KEYS" "DENY_CHILD_KEYS_PRESENT" @{
    Mode = "Unregister"
    UserEntries = @(New-Entry -Children 1)
}

Assert-Case "UNREGISTER_EXTRA_VALUE" "DENY_UNEXPECTED_VALUES" @{
    Mode = "Unregister"
    UserEntries = @(
        New-Entry -Values @(
            "", "ARFManagedBy", "ARFRegisteredOrigin", "External"
        )
    )
}

Assert-Case "UNREGISTER_MISSING_VALUE" "DENY_UNEXPECTED_VALUES" @{
    Mode = "Unregister"
    UserEntries = @(
        New-Entry -Values @(
            "ARFManagedBy", "ARFRegisteredOrigin"
        )
    )
}

Assert-Case "UNREGISTER_PATH_CONFLICT" "DENY_PATH_CONFLICT" @{
    Mode = "Unregister"
    UserEntries = @(New-Entry -P "C:\Other\host.json")
}

Assert-Case "UNREGISTER_MACHINE_CONFLICT" "DENY_MACHINE_REGISTRATION" @{
    Mode = "Unregister"
    UserEntries = @(New-Entry)
    MachineEntries = @(New-Entry)
}

Assert-Case "UNREGISTER_MIXED_OWNERSHIP" "DENY_UNMANAGED_REGISTRATION" @{
    Mode = "Unregister"
    UserEntries = @(
        (New-Entry),
        (New-Entry -O "External")
    )
}

if ($script:passed -ne 20) {
    throw "Unexpected policy test count"
}

Write-Host ""
Write-Host "REGISTRATION_POLICY_TESTS_PASS=20"
Write-Host "SIMULATED_CASES_ONLY=YES"
Write-Host "REGISTRY_WRITES=NO"