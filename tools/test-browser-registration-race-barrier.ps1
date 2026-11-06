Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$managerPath = Join-Path $PSScriptRoot `
    "browser-native-host-registration.ps1"

$source = [IO.File]::ReadAllText(
    (Resolve-Path -LiteralPath $managerPath).Path
)

$script:passed = 0

function Assert-Check {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if (-not $Condition) {
        throw "FAILED: $Name"
    }

    $script:passed++
    Write-Host "PASS $Name"
}

$guardPos = $source.IndexOf(
    'throw "WRITE_MODES_SUSPENDED_9C4D2D2"'
)

$approvalPos = $source.IndexOf(
    'if (-not $Apply -or $Approval -cne $expectedApproval)'
)

$readPos = $source.IndexOf(
    '$userEntries = @('
)

$writePos = $source.IndexOf(
    '$root = [Microsoft.Win32.RegistryKey]::OpenBaseKey('
)

Assert-Check "WRITE_BARRIER_PRESENT" (
    $guardPos -ge 0
)

Assert-Check "APPROVAL_PRECEDES_BARRIER" (
    $approvalPos -ge 0 -and
    $approvalPos -lt $guardPos
)

Assert-Check "BARRIER_BEFORE_REGISTRY_READ" (
    $guardPos -ge 0 -and
    $readPos -gt $guardPos
)

Assert-Check "BARRIER_BEFORE_REGISTRY_WRITE" (
    $guardPos -ge 0 -and
    $writePos -gt $guardPos
)

Assert-Check "TEST_BACKEND_NOT_CONNECTED" (
    -not $source.Contains(
        "browser-registry-transaction-bridge.ps1"
    ) -and
    -not $source.Contains(
        "Invoke-ArfIsolatedTransaction"
    )
)

# Runtime probes are only executed after validating that the
# write barrier appears before all existing Registry operations.

$id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

foreach ($mode in @("Register", "Unregister")) {
    foreach ($scope in @("ChromiumShared", "Edge")) {
        $errorMessage = ""

        try {
            & $managerPath `
                -Mode $mode `
                -Scope $scope `
                -ExtensionId $id `
                -Apply `
                -Approval "${mode}_${scope}" | Out-Null
        }
        catch {
            $errorMessage = $_.Exception.Message
        }

        Assert-Check "${mode}_${scope}_BLOCKED" (
            $errorMessage -ceq "WRITE_MODES_SUSPENDED_9C4D2D2"
        )
    }
}

$approvalError = ""

try {
    & $managerPath `
        -Mode Register `
        -Scope Edge `
        -ExtensionId $id | Out-Null
}
catch {
    $approvalError = $_.Exception.Message
}

Assert-Check "EXPLICIT_APPROVAL_STILL_REQUIRED" (
    $approvalError -like "Explicit approval required:*"
)

$idError = ""

try {
    & $managerPath `
        -Mode Register `
        -Scope Edge `
        -Apply `
        -Approval "Register_Edge" | Out-Null
}
catch {
    $idError = $_.Exception.Message
}

Assert-Check "EXTENSION_ID_STILL_REQUIRED" (
    $idError -ceq "ExtensionId is required for Registry changes"
)

# Plan does read the existing Registry but never writes.
& $managerPath -Mode Plan `
    -Scope ChromiumShared `
    -ExtensionId $id

Assert-Check "READ_ONLY_PLAN_AVAILABLE" $true

if ($script:passed -ne 12) {
    throw "Unexpected test count: $script:passed"
}

Write-Host ""
Write-Host "REGISTRATION_RACE_BARRIER_TESTS_PASS=12"
Write-Host "REGISTER_RUNTIME=BLOCKED"
Write-Host "UNREGISTER_RUNTIME=BLOCKED"
Write-Host "PRODUCTION_REGISTRY_WRITES=NO"
Write-Host "NON_ATOMIC_DELETE_REMAINS_UNRESOLVED=YES"