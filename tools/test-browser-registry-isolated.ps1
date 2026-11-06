[CmdletBinding()]
param(
    [ValidateSet("Plan", "Apply")]
    [string]$Mode = "Plan",

    [string]$Approval = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "browser-registry-isolated-backend.ps1")

if (-not [Environment]::Is64BitProcess) {
    throw "64-bit PowerShell required"
}

Initialize-ArfTestNativeApi

Write-Host "`n=== ISOLATED REGISTRY TEST ==="
Write-Host "MODE=$Mode"
Write-Host "TEST_ROOT=HKCU\$script:ArfTestPrefix"
Write-Host "PRODUCTION_MANAGER_INTEGRATION=NO"

if ($Mode -eq "Plan") {
    Write-Host "NATIVE_API_LOADED=YES"
    Write-Host "ISOLATED_REGISTRY_PLAN_PASS"
    Write-Host "REGISTRY_WRITES=NO"
    return
}

if ($Approval -cne "RUN_ISOLATED_REGISTRY_TESTS_9C4D2C") {
    throw "Explicit isolated-registry test approval required"
}

$script:passed = 0
$script:owner = "ARF-9C4D2C-TestOnly-v1"
$script:origin = "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"
$script:manifest = "C:\ARF-Isolated-Test\manifest.json"

$created = New-Object 'System.Collections.Generic.List[string]'
$script:cleanupFailed = $false

function Assert-Test {
    param([string]$Name, [bool]$Condition)

    if (-not $Condition) {
        throw "FAILED: $Name"
    }

    $script:passed++
    Write-Host "PASS $Name"
}

try {
    $rejected = $false

    try {
        $null = New-ArfIsolatedTestKey `
            -Leaf "Software\Google\Chrome"
    }
    catch {
        $rejected = $true
    }

    Assert-Test "UNSAFE_PATH_REJECTED" $rejected

    $first = "arf-" + [guid]::NewGuid().ToString("N")

    $state = Get-ArfIsolatedTestState $first

    Assert-Test "FRESH_GUID_KEY_ABSENT" (-not $state.Exists)

    $result = New-ArfIsolatedTestKey $first

    if ($result -ceq "CREATED_NEW") {
        $created.Add($first)
    }

    Assert-Test "EXCLUSIVE_CREATION_PROVEN" (
        $result -ceq "CREATED_NEW"
    )

    $state = Get-ArfIsolatedTestState $first

    Assert-Test "NEW_KEY_EMPTY" (
        $state.Exists -and
        $state.Values.Count -eq 0 -and
        $state.Children -eq 0
    )

    $result = New-ArfIsolatedTestKey $first

    Assert-Test "EXISTING_KEY_DETECTED" (
        $result -ceq "ALREADY_EXISTS"
    )

    $state = Get-ArfIsolatedTestState $first

    Assert-Test "EXISTING_KEY_NOT_OVERWRITTEN" (
        $state.Values.Count -eq 0
    )

    Set-ArfIsolatedTestValue $first "ARFManagedBy" $script:owner
    Set-ArfIsolatedTestValue $first "ARFRegisteredOrigin" $script:origin
    Set-ArfIsolatedTestValue $first "" $script:manifest

    $state = Get-ArfIsolatedTestState $first

    Assert-Test "COMPLETE_REGISTRATION_VALID" (
        Test-ArfTransactionState `
            -State $state `
            -Owner $script:owner `
            -Origin $script:origin `
            -ManifestPath $script:manifest `
            -RequireComplete
    )

    $second = "arf-" + [guid]::NewGuid().ToString("N")

    $result = New-ArfIsolatedTestKey $second

    if ($result -ceq "CREATED_NEW") {
        $created.Add($second)
    }

    Assert-Test "SECOND_EXCLUSIVE_CREATION" (
        $result -ceq "CREATED_NEW"
    )

    Set-ArfIsolatedTestValue $second "ARFManagedBy" $script:owner
    Set-ArfIsolatedTestValue $second "ARFRegisteredOrigin" $script:origin

    # Intentionally omit the default manifest value.
    # This simulates failure before the final write.
    $state = Get-ArfIsolatedTestState $second

    Assert-Test "PARTIAL_STATE_RECOGNIZED" (
        Test-ArfTransactionState `
            -State $state `
            -Owner $script:owner `
            -Origin $script:origin `
            -ManifestPath $script:manifest
    )

    Assert-Test "PARTIAL_NOT_ACCEPTED_AS_COMPLETE" (
        -not (Test-ArfTransactionState `
            -State $state `
            -Owner $script:owner `
            -Origin $script:origin `
            -ManifestPath $script:manifest `
            -RequireComplete)
    )

    $removed = Remove-ArfIsolatedTestKey `
        -Leaf $second `
        -Owner $script:owner `
        -Origin $script:origin `
        -ManifestPath $script:manifest `
        -CreationConfirmed $true

    Assert-Test "PARTIAL_ROLLBACK_VERIFIED" (
        $removed -ceq "REMOVED" -and
        -not (Get-ArfIsolatedTestState $second).Exists
    )

    $removed = Remove-ArfIsolatedTestKey `
        -Leaf $first `
        -Owner $script:owner `
        -Origin $script:origin `
        -ManifestPath $script:manifest `
        -CreationConfirmed $true

    Assert-Test "COMPLETE_TEST_KEY_CLEANUP" (
        $removed -ceq "REMOVED" -and
        -not (Get-ArfIsolatedTestState $first).Exists
    )

    if ($script:passed -ne 12) {
        throw "Unexpected test count: $script:passed"
    }

    Write-Host "`nISOLATED_REGISTRY_TESTS_PASS=12"
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
            $script:cleanupFailed = $true
            Write-Warning "Manual review required for HKCU\$script:ArfTestPrefix\$leaf"
        }
    }

    if ($script:cleanupFailed) {
        throw "Isolated test cleanup could not be fully verified"
    }
}

Write-Host "ISOLATED_TEST_KEYS_CLEANED=YES"
Write-Host "BROWSER_NATIVE_HOST_KEYS_TOUCHED=NO"
Write-Host "PRODUCTION_MANAGER_INTEGRATION=NO"