Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "browser-registration-transaction.ps1")

$script:owner = "ARF-9C4B-Manager-v1"
$script:origin = "chrome-extension://kbbpbandkpaakicmlleoaafgadncfcfj/"
$script:manifest = "C:\ARF-Isolated-Test\health.json"
$script:passed = 0

function Copy-MockState {
    $values = @{}

    foreach ($key in @($script:mock.Values.Keys)) {
        $values[$key] = $script:mock.Values[$key]
    }

    return [pscustomobject]@{
        Exists = [bool]$script:mock.Exists
        Children = [int]$script:mock.Children
        Values = $values
    }
}

function Test-MockEqual {
    param($A, $B)

    if ($A.Exists -ne $B.Exists -or
        $A.Children -ne $B.Children -or
        $A.Values.Count -ne $B.Values.Count) {
        return $false
    }

    foreach ($key in @($A.Values.Keys)) {
        if (-not $B.Values.Contains($key) -or
            $A.Values[$key] -cne $B.Values[$key]) {
            return $false
        }
    }

    return $true
}

function Initialize-Mock {
    param([string]$Scenario)

    $script:scenario = $Scenario
    $script:sets = 0
    $script:rollbacks = 0
    $script:reappear = $false

    $script:mock = [pscustomobject]@{
        Exists = $false
        Children = 0
        Values = @{}
    }

    if ($Scenario -eq "EXISTING") {
        $script:mock.Exists = $true
        $script:mock.Values[""] = "C:\Foreign\host.json"
    }
}

$backend = @{
    Create = {
        if ($script:scenario -eq "CREATE_THROW") {
            throw "Injected creation failure"
        }

        if ($script:scenario -eq "CREATE_UNKNOWN") {
            return "UNKNOWN"
        }

        if ($script:mock.Exists) {
            return "ALREADY_EXISTS"
        }

        $script:mock.Exists = $true
        return "CREATED_NEW"
    }

    SetValue = {
        param([string]$Name, [string]$Value)

        $script:sets++

        if ($script:scenario -eq "FAIL_OWNER" -and
            $Name -ceq "ARFManagedBy") {
            throw "Injected owner write failure"
        }

        if ($script:scenario -eq "FAIL_ORIGIN" -and
            $Name -ceq "ARFRegisteredOrigin") {
            throw "Injected origin write failure"
        }

        if ($Name -ceq "") {
            switch ($script:scenario) {
                "FAIL_DEFAULT" {
                    throw "Injected default write failure"
                }
                "READ_THROW" {
                    throw "Injected default write failure"
                }
                "ROLLBACK_RACE" {
                    throw "Injected default write failure"
                }
                "ROLLBACK_THROW" {
                    throw "Injected default write failure"
                }
                "ROLLBACK_POSTCHECK" {
                    throw "Injected default write failure"
                }
                "FOREIGN_VALUE" {
                    $script:mock.Values["Foreign"] = "External"
                    throw "External value appeared"
                }
                "FOREIGN_OWNER" {
                    $script:mock.Values["ARFManagedBy"] = "External"
                    throw "Owner changed"
                }
                "FOREIGN_ORIGIN" {
                    $script:mock.Values["ARFRegisteredOrigin"] =
                        "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"
                    throw "Origin changed"
                }
                "FOREIGN_DEFAULT" {
                    $script:mock.Values[""] = "C:\Foreign\host.json"
                    throw "Default changed"
                }
                "FOREIGN_CHILD" {
                    $script:mock.Children = 1
                    throw "Child appeared"
                }
            }
        }

        $script:mock.Values[$Name] = $Value

        if ($script:scenario -eq "OWNER_WRITE_THEN_THROW" -and
            $Name -ceq "ARFManagedBy") {
            throw "Injected failure after owner write"
        }

        if ($script:scenario -eq "DEFAULT_WRITE_THEN_THROW" -and
            $Name -ceq "") {
            throw "Injected failure after default write"
        }
    }

    Read = {
        if ($script:scenario -eq "READ_THROW" -and
            $script:sets -ge 3) {
            throw "Injected read failure"
        }

        if ($script:reappear) {
            $script:mock.Exists = $true
            $script:mock.Values[""] = "C:\Foreign\host.json"
            $script:reappear = $false
        }

        if ($script:scenario -eq "POST_VERIFY_FOREIGN" -and
            $script:sets -eq 3) {
            $script:mock.Values[""] = "C:\Foreign\host.json"
        }

        Copy-MockState
    }

    Rollback = {
        param($Observed)

        $script:rollbacks++

        if ($script:scenario -eq "ROLLBACK_THROW") {
            throw "Injected rollback failure"
        }

        if ($script:scenario -eq "ROLLBACK_RACE") {
            $script:mock.Values["Foreign"] = "External"
        }

        $now = Copy-MockState

        if (-not (Test-MockEqual $now $Observed)) {
            return "STATE_CHANGED"
        }

        $script:mock.Exists = $false
        $script:mock.Children = 0
        $script:mock.Values = @{}

        if ($script:scenario -eq "ROLLBACK_POSTCHECK") {
            $script:reappear = $true
        }

        return "REMOVED"
    }
}

function Assert-Scenario {
    param(
        [string]$Scenario,
        [string]$Expected,
        [bool]$KeyExists,
        [int]$RollbackCalls
    )

    Initialize-Mock $Scenario

    $actual = Invoke-ArfRegistrationTransaction `
        -Backend $backend `
        -Owner $script:owner `
        -Origin $script:origin `
        -ManifestPath $script:manifest

    if ($actual -cne $Expected) {
        throw "$Scenario status: expected=$Expected actual=$actual"
    }

    if ([bool]$script:mock.Exists -ne $KeyExists) {
        throw "$Scenario key existence differs"
    }

    if ($script:rollbacks -ne $RollbackCalls) {
        throw "$Scenario rollback count differs"
    }

    $script:passed++
    Write-Host "PASS $Scenario : $actual"
}

Assert-Scenario "SUCCESS" "REGISTERED" $true 0
Assert-Scenario "EXISTING" "DENY_CREATION_UNPROVEN" $true 0
Assert-Scenario "CREATE_UNKNOWN" "DENY_CREATION_UNPROVEN" $false 0
Assert-Scenario "CREATE_THROW" "FAILED_CREATE_EXCEPTION" $false 0

Assert-Scenario "FAIL_OWNER" "FAILED_ROLLED_BACK" $false 1
Assert-Scenario "FAIL_ORIGIN" "FAILED_ROLLED_BACK" $false 1
Assert-Scenario "FAIL_DEFAULT" "FAILED_ROLLED_BACK" $false 1

Assert-Scenario "OWNER_WRITE_THEN_THROW" "FAILED_ROLLED_BACK" $false 1
Assert-Scenario "DEFAULT_WRITE_THEN_THROW" "FAILED_ROLLED_BACK" $false 1

Assert-Scenario "FOREIGN_VALUE" "FAILED_UNSAFE_PARTIAL_STATE" $true 0
Assert-Scenario "FOREIGN_OWNER" "FAILED_UNSAFE_PARTIAL_STATE" $true 0
Assert-Scenario "FOREIGN_ORIGIN" "FAILED_UNSAFE_PARTIAL_STATE" $true 0
Assert-Scenario "FOREIGN_DEFAULT" "FAILED_UNSAFE_PARTIAL_STATE" $true 0
Assert-Scenario "FOREIGN_CHILD" "FAILED_UNSAFE_PARTIAL_STATE" $true 0

Assert-Scenario "ROLLBACK_RACE" "FAILED_ROLLBACK_CONFLICT" $true 1
Assert-Scenario "ROLLBACK_THROW" "FAILED_ROLLBACK_EXCEPTION" $true 1
Assert-Scenario "READ_THROW" "FAILED_UNREADABLE_STATE" $true 0

Assert-Scenario "POST_VERIFY_FOREIGN" "FAILED_UNSAFE_PARTIAL_STATE" $true 0
Assert-Scenario "ROLLBACK_POSTCHECK" "FAILED_ROLLBACK_UNVERIFIED" $true 1

if ($script:passed -ne 19) {
    throw "Unexpected test count: $script:passed"
}

Write-Host ""
Write-Host "REGISTRATION_TRANSACTION_TESTS_PASS=19"
Write-Host "FAULT_INJECTION=ENABLED"
Write-Host "BACKEND=IN_MEMORY"
Write-Host "PRODUCTION_MANAGER_INTEGRATION=NO"
Write-Host "REGISTRY_WRITES=NO"