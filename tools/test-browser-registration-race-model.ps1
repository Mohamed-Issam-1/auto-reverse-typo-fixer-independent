Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "browser-registration-race-model.ps1")

$script:passed = 0

function Assert-Check {
    param([string]$Name, [bool]$Condition)

    if (-not $Condition) {
        throw "FAILED: $Name"
    }

    $script:passed++
    Write-Host "PASS $Name"
}

$normalName = Get-ArfRaceModelOutcome `
    -Strategy SnapshotNameDelete -Mutation None

Assert-Check "NAME_DELETE_WITHOUT_RACE" (
    $normalName.Status -ceq "NAME_DELETE_OCCURRED" -and
    -not $normalName.ChangedStateDeleted
)

$normalAtomic = Get-ArfRaceModelOutcome `
    -Strategy AtomicOracle -Mutation None

Assert-Check "MOCK_ATOMIC_DELETE_WITHOUT_RACE" (
    $normalAtomic.Status -ceq "MOCK_ATOMIC_DELETE" -and
    -not $normalAtomic.ChangedStateDeleted
)

foreach ($mutation in @(
    "Owner"
    "Origin"
    "Manifest"
    "ExtraValue"
    "Child"
    "Replace"
    "ABA"
)) {
    $unsafe = Get-ArfRaceModelOutcome `
        -Strategy SnapshotNameDelete `
        -Mutation $mutation

    Assert-Check "NAME_DELETE_${mutation}_EXPOSES_RACE" (
        $unsafe.Status -ceq "UNSAFE_DELETE_OCCURRED" -and
        $unsafe.ChangedStateDeleted -and
        -not $unsafe.KeyStillPresent
    )

    $protected = Get-ArfRaceModelOutcome `
        -Strategy AtomicOracle `
        -Mutation $mutation

    Assert-Check "MOCK_ATOMIC_${mutation}_REJECTS_RACE" (
        $protected.Status -ceq "DENY_CHANGED_STATE" -and
        -not $protected.ChangedStateDeleted -and
        $protected.KeyStillPresent
    )
}

$absentName = Get-ArfRaceModelOutcome `
    -Strategy SnapshotNameDelete `
    -Mutation Absent

Assert-Check "NAME_DELETE_KEY_DISAPPEARED" (
    $absentName.Status -ceq "NO_KEY_AT_USE" -and
    -not $absentName.ChangedStateDeleted
)

$absentAtomic = Get-ArfRaceModelOutcome `
    -Strategy AtomicOracle `
    -Mutation Absent

Assert-Check "MOCK_ATOMIC_KEY_DISAPPEARED" (
    $absentAtomic.Status -ceq "DENY_CHANGED_STATE" -and
    -not $absentAtomic.ChangedStateDeleted
)

foreach ($strategy in @(
    "SnapshotNameDelete"
    "AtomicOracle"
)) {
    $foreign = Get-ArfRaceModelOutcome `
        -Strategy $strategy `
        -InitiallyOwned $false

    Assert-Check "${strategy}_FOREIGN_PREEXISTING_DENIED" (
        $foreign.Status -ceq "DENY_INITIAL_STATE" -and
        -not $foreign.ChangedStateDeleted -and
        $foreign.KeyStillPresent
    )
}

$managerPath = Join-Path $PSScriptRoot `
    "browser-native-host-registration.ps1"

$manager = [IO.File]::ReadAllText(
    (Resolve-Path -LiteralPath $managerPath).Path
)

$guard = $manager.IndexOf(
    'throw "WRITE_MODES_SUSPENDED_9C4D2D2"'
)

$firstRead = $manager.IndexOf('$userEntries = @(')

$writeEntry = $manager.IndexOf(
    '$root = [Microsoft.Win32.RegistryKey]::OpenBaseKey('
)

Assert-Check "PRODUCTION_BARRIER_BEFORE_READ" (
    $guard -ge 0 -and
    $firstRead -gt $guard
)

Assert-Check "PRODUCTION_BARRIER_BEFORE_WRITE" (
    $guard -ge 0 -and
    $writeEntry -gt $guard
)

$modelPath = Join-Path $PSScriptRoot `
    "browser-registration-race-model.ps1"

$modelSource = [IO.File]::ReadAllText(
    (Resolve-Path -LiteralPath $modelPath).Path
)

Assert-Check "MODEL_HAS_NO_REGISTRY_API" (
    -not $modelSource.Contains("[Microsoft.Win32.RegistryKey]") -and
    -not $modelSource.Contains("RegDeleteKey") -and
    -not $modelSource.Contains("DeleteSubKey(") -and
    -not $modelSource.Contains("RegCreateKeyEx")
)

if ($script:passed -ne 23) {
    throw "Unexpected race model test count: $script:passed"
}

Write-Host ""
Write-Host "REGISTRATION_RACE_MODEL_TESTS_PASS=23"
Write-Host "MODEL=IN_MEMORY_ONLY"
Write-Host "ATOMIC_ORACLE=SIMULATED_NOT_IMPLEMENTED"
Write-Host "PRODUCTION_WRITE_BARRIER=PRESERVED"
Write-Host "REGISTRY_WRITES=NO"