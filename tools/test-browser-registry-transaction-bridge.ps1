[CmdletBinding()]
param(
    [ValidateSet("Plan", "Apply")]
    [string]$Mode = "Plan",

    [string]$Approval = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "browser-registry-transaction-bridge.ps1")

if (-not [Environment]::Is64BitProcess) {
    throw "64-bit PowerShell required"
}

Write-Host "`n=== ISOLATED TRANSACTION BRIDGE ==="
Write-Host "MODE=$Mode"
Write-Host "TEST_ROOT=HKCU\$script:ArfTestPrefix"
Write-Host "PRODUCTION_MANAGER_INTEGRATION=NO"

if ($Mode -eq "Plan") {
    $command = Get-Command Invoke-ArfIsolatedTransaction `
        -CommandType Function -ErrorAction Stop

    if ($null -eq $command) {
        throw "Transaction bridge missing"
    }

    Initialize-ArfTestNativeApi

    Write-Host "BRIDGE_LOADED=YES"
    Write-Host "NATIVE_API_LOADED=YES"
    Write-Host "ISOLATED_TRANSACTION_BRIDGE_PLAN_PASS"
    Write-Host "REGISTRY_WRITES=NO"
    return
}

if ($Approval -cne "RUN_ISOLATED_TRANSACTION_BRIDGE_9C4D2D1") {
    throw "Explicit isolated test approval required"
}

$script:passed = 0
$script:owner = "ARF-9C4D2D-TestOnly-v1"
$script:origin = "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"
$script:manifest = "C:\ARF-Isolated-Test\transaction.json"

$created = New-Object 'System.Collections.Generic.List[string]'
$cleanupFailed = $false

function Assert-Test {
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

function Record-Creation {
    param($Result)

    if ($Result.CreatedByThisRun -and
        -not $created.Contains($Result.Leaf)) {
        $created.Add($Result.Leaf)
    }
}

try {
    $first = "arf-" + [guid]::NewGuid().ToString("N")

    Assert-Test "FRESH_KEY_ABSENT" (
        -not (Get-ArfIsolatedTestState $first).Exists
    )

    $success = Invoke-ArfIsolatedTransaction `
        -Leaf $first -InjectFailure None

    Record-Creation $success

    Assert-Test "TRANSACTION_SUCCESS" (
        $success.Status -ceq "REGISTERED" -and
        $success.CreatedByThisRun
    )

    $state = Get-ArfIsolatedTestState $first

    Assert-Test "COMPLETE_VALUES_VERIFIED" (
        Test-ArfTransactionState `
            -State $state `
            -Owner $script:owner `
            -Origin $script:origin `
            -ManifestPath $script:manifest `
            -RequireComplete
    )

    $originalSignature = Get-ArfTestStateSignature $state

    $duplicate = Invoke-ArfIsolatedTransaction -Leaf $first

    Assert-Test "DUPLICATE_CREATION_DENIED" (
        $duplicate.Status -ceq "DENY_CREATION_UNPROVEN" -and
        -not $duplicate.CreatedByThisRun
    )

    $afterDuplicate = Get-ArfIsolatedTestState $first

    Assert-Test "EXISTING_KEY_PRESERVED" (
        (Get-ArfTestStateSignature $afterDuplicate) -ceq
        $originalSignature
    )

    $second = "arf-" + [guid]::NewGuid().ToString("N")

    Assert-Test "FAULT_TEST_KEY_ABSENT" (
        -not (Get-ArfIsolatedTestState $second).Exists
    )

    $faultDefault = Invoke-ArfIsolatedTransaction `
        -Leaf $second -InjectFailure Default

    Record-Creation $faultDefault

    Assert-Test "DEFAULT_WRITE_FAILURE_ROLLBACK" (
        $faultDefault.Status -ceq "FAILED_ROLLED_BACK"
    )

    Assert-Test "DEFAULT_FAILURE_KEY_REMOVED" (
        -not (Get-ArfIsolatedTestState $second).Exists
    )

    $third = "arf-" + [guid]::NewGuid().ToString("N")

    $faultOwner = Invoke-ArfIsolatedTransaction `
        -Leaf $third -InjectFailure Owner

    Record-Creation $faultOwner

    Assert-Test "OWNER_WRITE_FAILURE_ROLLBACK" (
        $faultOwner.Status -ceq "FAILED_ROLLED_BACK"
    )

    Assert-Test "OWNER_FAILURE_KEY_REMOVED" (
        -not (Get-ArfIsolatedTestState $third).Exists
    )

    $removed = Remove-ArfIsolatedTestKey `
        -Leaf $first `
        -Owner $script:owner `
        -Origin $script:origin `
        -ManifestPath $script:manifest `
        -CreationConfirmed $true

    Assert-Test "COMPLETE_TEST_KEY_CLEANED" (
        $removed -ceq "REMOVED" -and
        -not (Get-ArfIsolatedTestState $first).Exists
    )

    $remaining = @(
        $created | Where-Object {
            (Get-ArfIsolatedTestState $_).Exists
        }
    )

    Assert-Test "ALL_TRACKED_KEYS_ABSENT" (
        $remaining.Count -eq 0
    )

    if ($script:passed -ne 12) {
        throw "Unexpected test count: $script:passed"
    }

    Write-Host ""
    Write-Host "ISOLATED_TRANSACTION_BRIDGE_TESTS_PASS=12"
}
finally {
    foreach ($leaf in $created) {
        try {
            $state = Get-ArfIsolatedTestState $leaf

            if ($state.Exists) {
                $null = Remove-ArfIsolatedTestKey `
                    -Leaf $leaf `
                    -Owner $script:owner `
                    -Origin $script:origin `
                    -ManifestPath $script:manifest `
                    -CreationConfirmed $true
            }
        }
        catch {
            $cleanupFailed = $true
            Write-Warning "Manual review required for isolated key: $leaf"
        }
    }

    if ($cleanupFailed) {
        throw "Isolated transaction cleanup requires review"
    }
}

Write-Host "ISOLATED_TEST_KEYS_CLEANED=YES"
Write-Host "PRODUCTION_MANAGER_INTEGRATION=NO"
Write-Host "BROWSER_NATIVE_HOST_KEYS_TOUCHED=NO"