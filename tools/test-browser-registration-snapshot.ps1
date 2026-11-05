Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "browser-registration-snapshot.ps1")

$script:hostPath = "C:\ARF-Isolated-Test\health.json"
$script:origin = "chrome-extension://kbbpbandkpaakicmlleoaafgadncfcfj/"
$script:owner = "ARF-9C4B-Manager-v1"
$script:passed = 0

function New-Entry {
    param(
        [string]$Path = $script:hostPath,
        [string]$Owner = $script:owner,
        [string]$Origin = $script:origin,
        [string[]]$Values = @(
            "", "ARFManagedBy", "ARFRegisteredOrigin"
        ),
        [int]$Children = 0
    )

    return [pscustomobject]@{
        Hive = "CurrentUser"
        View = "Registry64"
        Path = $Path
        Owner = $Owner
        Origin = $Origin
        Values = @($Values)
        Children = $Children
    }
}

function Assert-Guard {
    param(
        [string]$Name,
        [string]$Expected,
        [hashtable]$Changes
    )

    $inputs = @{
        Mode = "Register"
        Scope = "Edge"
        ManifestValid = $true
        OriginAllowlisted = $true
        ManifestPath = $script:hostPath
        ExtensionOrigin = $script:origin
        Owner = $script:owner
        BeforeUserEntries = @()
        AfterUserEntries = @()
        BeforeMachineEntries = @()
        AfterMachineEntries = @()
    }

    foreach ($key in $Changes.Keys) {
        $inputs[$key] = $Changes[$key]
    }

    $actual = Get-ArfStableRegistrationDecision @inputs

    if ($actual -cne $Expected) {
        throw "$Name FAILED: expected=$Expected actual=$actual"
    }

    $script:passed++
    Write-Host "PASS $Name : $actual"
}

function Assert-Rollback {
    param(
        [string]$Name,
        [string]$Expected,
        [hashtable]$Changes
    )

    $inputs = @{
        CreationAttempted = $true
        ManifestPath = $script:hostPath
        ExtensionOrigin = $script:origin
        Owner = $script:owner
        BeforeUserEntries = @()
        CurrentUserEntries = @()
        MachineEntries = @()
    }

    foreach ($key in $Changes.Keys) {
        $inputs[$key] = $Changes[$key]
    }

    $actual = Get-ArfPartialRollbackDecision @inputs

    if ($actual -cne $Expected) {
        throw "$Name FAILED: expected=$Expected actual=$actual"
    }

    $script:passed++
    Write-Host "PASS $Name : $actual"
}

Assert-Guard "REGISTER_STABLE_EMPTY" "ALLOW_REGISTER" @{}

Assert-Guard "REGISTER_ALREADY_EXISTS" "DENY_ALREADY_REGISTERED" @{
    BeforeUserEntries = @((New-Entry))
    AfterUserEntries = @((New-Entry))
}

Assert-Guard "REGISTER_FOREIGN_APPEARS" "DENY_SNAPSHOT_CHANGED" @{
    AfterUserEntries = @((New-Entry -Owner "External"))
}

Assert-Guard "REGISTER_MACHINE_APPEARS" "DENY_SNAPSHOT_CHANGED" @{
    AfterMachineEntries = @((New-Entry))
}

Assert-Guard "REGISTER_INVALID_MANIFEST" "DENY_INVALID_MANIFEST" @{
    ManifestValid = $false
}

Assert-Guard "UNREGISTER_STABLE_OWNED_EDGE" "ALLOW_UNREGISTER" @{
    Mode = "Unregister"
    BeforeUserEntries = @((New-Entry))
    AfterUserEntries = @((New-Entry))
}

Assert-Guard "UNREGISTER_OWNER_CHANGED" "DENY_SNAPSHOT_CHANGED" @{
    Mode = "Unregister"
    BeforeUserEntries = @((New-Entry))
    AfterUserEntries = @((New-Entry -Owner "External"))
}

Assert-Guard "UNREGISTER_PATH_CHANGED" "DENY_SNAPSHOT_CHANGED" @{
    Mode = "Unregister"
    BeforeUserEntries = @((New-Entry))
    AfterUserEntries = @((New-Entry -Path "C:\Other\host.json"))
}

Assert-Guard "UNREGISTER_ORIGIN_CHANGED" "DENY_SNAPSHOT_CHANGED" @{
    Mode = "Unregister"
    BeforeUserEntries = @((New-Entry))
    AfterUserEntries = @((New-Entry -Origin "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"))
}

Assert-Guard "UNREGISTER_VALUE_ADDED" "DENY_SNAPSHOT_CHANGED" @{
    Mode = "Unregister"
    BeforeUserEntries = @((New-Entry))
    AfterUserEntries = @(
        (New-Entry -Values @(
            "", "ARFManagedBy", "ARFRegisteredOrigin", "Foreign"
        ))
    )
}

Assert-Guard "UNREGISTER_CHILD_ADDED" "DENY_SNAPSHOT_CHANGED" @{
    Mode = "Unregister"
    BeforeUserEntries = @((New-Entry))
    AfterUserEntries = @((New-Entry -Children 1))
}

Assert-Guard "UNREGISTER_SHARED_BLOCKED" "DENY_SHARED_REMOVAL" @{
    Mode = "Unregister"
    Scope = "ChromiumShared"
    BeforeUserEntries = @((New-Entry))
    AfterUserEntries = @((New-Entry))
}

Assert-Guard "MALFORMED_SNAPSHOT" "DENY_INVALID_SNAPSHOT" @{
    AfterUserEntries = @(
        [pscustomobject]@{ Path = $script:hostPath }
    )
}

Assert-Rollback "PARTIAL_OWNED" "ALLOW_OWNED_PARTIAL_ROLLBACK" @{
    CurrentUserEntries = @(
        (New-Entry -Values @(
            "ARFManagedBy", "ARFRegisteredOrigin"
        ))
    )
}

Assert-Rollback "PARTIAL_FOREIGN_OWNER" "DENY_ROLLBACK_UNSAFE_STATE" @{
    CurrentUserEntries = @((New-Entry -Owner "External"))
}

Assert-Rollback "PARTIAL_EXTRA_VALUE" "DENY_ROLLBACK_UNSAFE_STATE" @{
    CurrentUserEntries = @(
        (New-Entry -Values @(
            "ARFManagedBy", "ARFRegisteredOrigin", "Foreign"
        ))
    )
}

Assert-Rollback "PARTIAL_CHILD_KEY" "DENY_ROLLBACK_UNSAFE_STATE" @{
    CurrentUserEntries = @((New-Entry -Children 1))
}

Assert-Rollback "PREEXISTING_KEY" "DENY_PREEXISTING_REGISTRATION" @{
    BeforeUserEntries = @((New-Entry))
    CurrentUserEntries = @((New-Entry))
}

Assert-Rollback "ALREADY_CLEAN" "ALREADY_CLEAN" @{}

Assert-Rollback "CREATION_NOT_ATTEMPTED" "DENY_CREATION_NOT_ATTEMPTED" @{
    CreationAttempted = $false
}

Assert-Rollback "MACHINE_CONFLICT" "DENY_PREEXISTING_REGISTRATION" @{
    MachineEntries = @((New-Entry))
    CurrentUserEntries = @((New-Entry))
}

if ($script:passed -ne 21) {
    throw "Unexpected test count: $script:passed"
}

Write-Host ""
Write-Host "REGISTRATION_SNAPSHOT_TESTS_PASS=21"
Write-Host "SIMULATED_CASES_ONLY=YES"
Write-Host "REGISTRY_WRITES=NO"