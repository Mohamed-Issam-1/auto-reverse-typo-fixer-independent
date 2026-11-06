# Pure in-memory Registry race model.
# No Registry, filesystem, or process access.
# AtomicOracle is hypothetical. It is NOT a Windows implementation.

function Get-ArfRaceModelOutcome {
    [CmdletBinding()]
    param(
        [ValidateSet("SnapshotNameDelete", "AtomicOracle")]
        [string]$Strategy,

        [ValidateSet(
            "None", "Owner", "Origin", "Manifest",
            "ExtraValue", "Child", "Replace", "ABA", "Absent"
        )]
        [string]$Mutation = "None",

        [bool]$InitiallyOwned = $true
    )

    $expectedOwner = "ARF-Test-Owner"
    $expectedOrigin = "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"
    $expectedPath = "C:\ARF-Test\manifest.json"

    $state = [pscustomobject]@{
        Present = $true
        Identity = "original-key"
        Revision = 1
        Owner = if ($InitiallyOwned) {
            $expectedOwner
        } else {
            "External-Owner"
        }
        Origin = $expectedOrigin
        Manifest = $expectedPath
        ValueNames = @(
            "", "ARFManagedBy", "ARFRegisteredOrigin"
        )
        Children = 0
    }

    $wantedNames = @(
        "", "ARFManagedBy", "ARFRegisteredOrigin"
    ) | Sort-Object -CaseSensitive

    $actualNames = @(
        $state.ValueNames | Sort-Object -CaseSensitive
    )

    $initialEligible = (
        $state.Present -and
        $state.Owner -ceq $expectedOwner -and
        $state.Origin -ceq $expectedOrigin -and
        $state.Manifest -ceq $expectedPath -and
        $state.Children -eq 0 -and
        ($actualNames -join "|") -ceq ($wantedNames -join "|")
    )

    if (-not $initialEligible) {
        return [pscustomobject]@{
            Status = "DENY_INITIAL_STATE"
            ChangedStateDeleted = $false
            KeyStillPresent = $state.Present
        }
    }

    $observedIdentity = $state.Identity
    $observedRevision = $state.Revision

    # A competing writer acts AFTER the initial inspection
    # but BEFORE the simulated deletion attempt.
    switch ($Mutation) {
        "Owner" {
            $state.Owner = "External-Owner"
            $state.Revision++
        }

        "Origin" {
            $state.Origin =
                "chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/"
            $state.Revision++
        }

        "Manifest" {
            $state.Manifest = "C:\External\manifest.json"
            $state.Revision++
        }

        "ExtraValue" {
            $state.ValueNames += "ExternalValue"
            $state.Revision++
        }

        "Child" {
            $state.Children = 1
            $state.Revision++
        }

        "Replace" {
            $state.Identity = "replacement-key"
            $state.Owner = "External-Owner"
            $state.Revision++
        }

        "ABA" {
            # Different key identity, with the same visible
            # values and revision as the original.
            $state.Identity = "replacement-key"
        }

        "Absent" {
            $state.Present = $false
            $state.Revision++
        }
    }

    $changed = (
        -not $state.Present -or
        $state.Identity -cne $observedIdentity -or
        $state.Revision -ne $observedRevision
    )

    if ($Strategy -eq "SnapshotNameDelete") {
        if (-not $state.Present) {
            return [pscustomobject]@{
                Status = "NO_KEY_AT_USE"
                ChangedStateDeleted = $false
                KeyStillPresent = $false
            }
        }

        # Demonstrates why deleting by name after inspection
        # can delete a modified or replacement key.
        $state.Present = $false

        return [pscustomobject]@{
            Status = if ($changed) {
                "UNSAFE_DELETE_OCCURRED"
            } else {
                "NAME_DELETE_OCCURRED"
            }
            ChangedStateDeleted = [bool]$changed
            KeyStillPresent = $false
        }
    }

    # Hypothetical indivisible operation:
    # compare identity/revision and delete in one protected step.
    # No Windows API or Registry write occurs here.
    if ($changed) {
        return [pscustomobject]@{
            Status = "DENY_CHANGED_STATE"
            ChangedStateDeleted = $false
            KeyStillPresent = $state.Present
        }
    }

    $state.Present = $false

    return [pscustomobject]@{
        Status = "MOCK_ATOMIC_DELETE"
        ChangedStateDeleted = $false
        KeyStillPresent = $false
    }
}