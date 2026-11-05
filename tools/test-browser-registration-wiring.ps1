Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "browser-registration-snapshot.ps1")

$path = Join-Path $PSScriptRoot "browser-native-host-registration.ps1"
$source = [IO.File]::ReadAllText((Resolve-Path $path).Path)

$passed = 0

function Assert-Check {
    param([string]$Name, [bool]$Condition)

    if (-not $Condition) {
        throw "FAILED: $Name"
    }

    $script:passed++
    Write-Host "PASS $Name"
}

$importPos = $source.IndexOf(
    '. (Join-Path $PSScriptRoot "browser-registration-snapshot.ps1")'
)

$stablePos = $source.IndexOf(
    '$stableDecision = Get-ArfStableRegistrationDecision'
)

$gatePos = $source.IndexOf(
    'SNAPSHOT_GATE=$stableDecision'
)

$rootMatches = [regex]::Matches(
    $source,
    '(?m)^\$root = \[Microsoft\.Win32\.RegistryKey\]::OpenBaseKey\('
)

Assert-Check "SINGLE_TOP_LEVEL_WRITE_ENTRY" (
    $rootMatches.Count -eq 1
)

Assert-Check "POLICY_LOADED_BEFORE_WRITES" (
    $importPos -ge 0 -and
    $importPos -lt $rootMatches[0].Index
)

Assert-Check "SNAPSHOT_BEFORE_WRITES" (
    $stablePos -gt $importPos -and
    $gatePos -gt $stablePos -and
    $gatePos -lt $rootMatches[0].Index
)

$refreshUserPos = $source.IndexOf(
    '$freshUserEntries = @('
)

$refreshMachinePos = $source.IndexOf(
    '$freshMachineEntries = @('
)

Assert-Check "FRESH_USER_SNAPSHOT" (
    $refreshUserPos -ge 0 -and
    $refreshUserPos -lt $stablePos
)

Assert-Check "FRESH_MACHINE_SNAPSHOT" (
    $refreshMachinePos -ge 0 -and
    $refreshMachinePos -lt $stablePos
)

$finalGuardPos = $source.IndexOf(
    '$deleteDecision = Get-ArfStableRegistrationDecision'
)

$deletePos = $source.IndexOf(
    '$parent.DeleteSubKey($name, $false)'
)

Assert-Check "FINAL_RECHECK_BEFORE_DELETE" (
    $finalGuardPos -gt $rootMatches[0].Index -and
    $finalGuardPos -lt $deletePos
)

Assert-Check "FINAL_DELETE_GATE_PRESENT" (
    $source.Contains(
        'if ($deleteDecision -cne "ALLOW_UNREGISTER")'
    )
)

$id = "kbbpbandkpaakicmlleoaafgadncfcfj"
$origin = "chrome-extension://$id/"
$hostPath = "C:\ARF-Isolated-Test\health.json"
$owner = "ARF-9C4B-Manager-v1"

$entry = [pscustomobject]@{
    Hive = "CurrentUser"
    View = "Registry64"
    Path = $hostPath
    Owner = $owner
    Origin = $origin
    Values = @("", "ARFManagedBy", "ARFRegisteredOrigin")
    Children = 0
}

$parameters = @{
    Mode = "Unregister"
    Scope = "ChromiumShared"
    ManifestValid = $true
    OriginAllowlisted = $true
    ManifestPath = $hostPath
    ExtensionOrigin = $origin
    Owner = $owner
    BeforeUserEntries = @($entry)
    AfterUserEntries = @($entry)
    BeforeMachineEntries = @()
    AfterMachineEntries = @()
}

$decision = Get-ArfStableRegistrationDecision @parameters

Assert-Check "CHROMIUM_SHARED_REMOVAL_DENIED" (
    $decision -ceq "DENY_SHARED_REMOVAL"
)

$parameters.Scope = "Edge"

$decision = Get-ArfStableRegistrationDecision @parameters

Assert-Check "OWNED_EDGE_ELIGIBLE_FOR_RECHECK" (
    $decision -ceq "ALLOW_UNREGISTER"
)

$parameters.AfterUserEntries = @(
    [pscustomobject]@{
        Hive = "CurrentUser"
        View = "Registry64"
        Path = $hostPath
        Owner = "External"
        Origin = $origin
        Values = @("", "ARFManagedBy", "ARFRegisteredOrigin")
        Children = 0
    }
)

$decision = Get-ArfStableRegistrationDecision @parameters

Assert-Check "CHANGED_OWNER_DENIED" (
    $decision -ceq "DENY_SNAPSHOT_CHANGED"
)

if ($script:passed -ne 10) {
    throw "Unexpected test count: $script:passed"
}

Write-Host ""
Write-Host "REGISTRATION_WIRING_TESTS_PASS=10"
Write-Host "REGISTRY_WRITES=NO"
Write-Host "STATIC_AND_SIMULATED_TESTS_ONLY=YES"