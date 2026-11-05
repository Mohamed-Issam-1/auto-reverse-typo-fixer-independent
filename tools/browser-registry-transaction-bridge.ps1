# TEST ONLY: combines the transaction engine and isolated Registry backend.
# Never import this file into the production Native Host manager.
# Registry rollback comparison is not atomic against external writers.

. (Join-Path $PSScriptRoot "browser-registry-isolated-backend.ps1")

function Invoke-ArfIsolatedTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Leaf,

        [ValidateSet("None", "Owner", "Origin", "Default")]
        [string]$InjectFailure = "None"
    )

    Assert-ArfTestLeaf $Leaf

    # Fixed test-only identity. Never a real browser registration.
    $ctx = @{
        Leaf = $Leaf
        Owner = "ARF-9C4D2D-TestOnly-v1"
        Origin = "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"
        ManifestPath = "C:\ARF-Isolated-Test\transaction.json"
        Fault = $InjectFailure
        Created = $false
    }

    $create = {
        $result = New-ArfIsolatedTestKey -Leaf $ctx.Leaf

        if ($result -ceq "CREATED_NEW") {
            $ctx.Created = $true
        }

        return $result
    }

    $setValue = {
        param(
            [string]$Name,
            [string]$Value
        )

        if (
            ($ctx.Fault -ceq "Owner" -and
                $Name -ceq "ARFManagedBy") -or
            ($ctx.Fault -ceq "Origin" -and
                $Name -ceq "ARFRegisteredOrigin") -or
            ($ctx.Fault -ceq "Default" -and
                $Name -ceq "")
        ) {
            throw "Injected isolated write failure"
        }

        Set-ArfIsolatedTestValue `
            -Leaf $ctx.Leaf `
            -Name $Name `
            -Value $Value
    }

    $read = {
        return (Get-ArfIsolatedTestState -Leaf $ctx.Leaf)
    }

    $rollback = {
        param($Observed)

        if (-not $ctx.Created) {
            return "UNPROVEN_CREATION"
        }

        try {
            $current = Get-ArfIsolatedTestState -Leaf $ctx.Leaf

            $beforeSignature = Get-ArfTestStateSignature $Observed
            $currentSignature = Get-ArfTestStateSignature $current

            if ($beforeSignature -cne $currentSignature) {
                return "STATE_CHANGED"
            }

            return (Remove-ArfIsolatedTestKey `
                -Leaf $ctx.Leaf `
                -Owner $ctx.Owner `
                -Origin $ctx.Origin `
                -ManifestPath $ctx.ManifestPath `
                -CreationConfirmed $true)
        }
        catch {
            return "ROLLBACK_DENIED"
        }
    }

    $backend = @{
        Create = $create.GetNewClosure()
        SetValue = $setValue.GetNewClosure()
        Read = $read.GetNewClosure()
        Rollback = $rollback.GetNewClosure()
    }

    $status = Invoke-ArfRegistrationTransaction `
        -Backend $backend `
        -Owner $ctx.Owner `
        -Origin $ctx.Origin `
        -ManifestPath $ctx.ManifestPath

    return [pscustomobject]@{
        Status = [string]$status
        Leaf = $Leaf
        CreatedByThisRun = [bool]$ctx.Created
    }
}