# Pure preflight and rollback decisions.
# No Registry, filesystem or process operations.

. (Join-Path $PSScriptRoot "browser-registration-policy.ps1")

function Get-ArfSnapshotSignature {
    [CmdletBinding()]
    param([object[]]$Entries = @())

    $lines = New-Object 'System.Collections.Generic.List[string]'

    foreach ($entry in $Entries) {
        if ($null -eq $entry) {
            return $null
        }

        $required = @(
            "Hive", "View", "Path", "Owner",
            "Origin", "Values", "Children"
        )

        foreach ($property in $required) {
            if ($entry.PSObject.Properties.Name -cnotcontains $property) {
                return $null
            }
        }

        if ($null -eq $entry.Values) {
            return $null
        }

        $names = @($entry.Values)

        foreach ($valueName in $names) {
            if ($valueName -isnot [string]) {
                return $null
            }
        }

        try {
            $children = [int]$entry.Children
        }
        catch {
            return $null
        }

        if ($children -lt 0) {
            return $null
        }

        $record = [ordered]@{
            Hive = [string]$entry.Hive
            View = [string]$entry.View
            Path = [string]$entry.Path
            Owner = [string]$entry.Owner
            Origin = [string]$entry.Origin
            Values = @($names | Sort-Object -CaseSensitive)
            Children = $children
        }

        $lines.Add(
            (ConvertTo-Json -InputObject $record -Compress -Depth 5)
        )
    }

    return [string]::Join(
        "`n",
        [string[]]@($lines.ToArray() | Sort-Object -CaseSensitive)
    )
}

function Get-ArfStableRegistrationDecision {
    [CmdletBinding()]
    param(
        [ValidateSet("Register", "Unregister")]
        [string]$Mode,

        [ValidateSet("ChromiumShared", "Edge")]
        [string]$Scope,

        [bool]$ManifestValid,
        [bool]$OriginAllowlisted,

        [string]$ManifestPath,
        [string]$ExtensionOrigin,
        [string]$Owner,

        [object[]]$BeforeUserEntries = @(),
        [object[]]$AfterUserEntries = @(),
        [object[]]$BeforeMachineEntries = @(),
        [object[]]$AfterMachineEntries = @()
    )

    $beforeUser = Get-ArfSnapshotSignature $BeforeUserEntries
    $afterUser = Get-ArfSnapshotSignature $AfterUserEntries
    $beforeMachine = Get-ArfSnapshotSignature $BeforeMachineEntries
    $afterMachine = Get-ArfSnapshotSignature $AfterMachineEntries

    if (
        $null -eq $beforeUser -or
        $null -eq $afterUser -or
        $null -eq $beforeMachine -or
        $null -eq $afterMachine
    ) {
        return "DENY_INVALID_SNAPSHOT"
    }

    if (
        $beforeUser -cne $afterUser -or
        $beforeMachine -cne $afterMachine
    ) {
        return "DENY_SNAPSHOT_CHANGED"
    }

    # A shared registration must not be removed until
    # all dependent browser integrations are coordinated.
    if ($Mode -eq "Unregister" -and
        $Scope -eq "ChromiumShared") {
        return "DENY_SHARED_REMOVAL"
    }

    return Get-ArfRegistrationDecision `
        -Mode $Mode `
        -ManifestValid $ManifestValid `
        -OriginAllowlisted $OriginAllowlisted `
        -ManifestPath $ManifestPath `
        -ExtensionOrigin $ExtensionOrigin `
        -Owner $Owner `
        -UserEntries $AfterUserEntries `
        -MachineEntries $AfterMachineEntries
}

function Get-ArfPartialRollbackDecision {
    [CmdletBinding()]
    param(
        [bool]$CreationAttempted,
        [string]$ManifestPath,
        [string]$ExtensionOrigin,
        [string]$Owner,

        [object[]]$BeforeUserEntries = @(),
        [object[]]$CurrentUserEntries = @(),
        [object[]]$MachineEntries = @()
    )

    if (-not $CreationAttempted) {
        return "DENY_CREATION_NOT_ATTEMPTED"
    }

    $before = Get-ArfSnapshotSignature $BeforeUserEntries
    $current = Get-ArfSnapshotSignature $CurrentUserEntries
    $machine = Get-ArfSnapshotSignature $MachineEntries

    if (
        $null -eq $before -or
        $null -eq $current -or
        $null -eq $machine
    ) {
        return "DENY_INVALID_SNAPSHOT"
    }

    if ($BeforeUserEntries.Count -gt 0 -or
        $MachineEntries.Count -gt 0) {
        return "DENY_PREEXISTING_REGISTRATION"
    }

    if ($CurrentUserEntries.Count -eq 0) {
        return "ALREADY_CLEAN"
    }

    $allowedNames = @(
        "", "ARFManagedBy", "ARFRegisteredOrigin"
    )

    foreach ($entry in $CurrentUserEntries) {
        if (
            $entry.Path -cne $ManifestPath -or
            $entry.Owner -cne $Owner -or
            $entry.Origin -cne $ExtensionOrigin -or
            $entry.Children -ne 0 -or
            @($entry.Values) -cnotcontains "ARFManagedBy"
        ) {
            return "DENY_ROLLBACK_UNSAFE_STATE"
        }

        foreach ($name in @($entry.Values)) {
            if ($allowedNames -cnotcontains $name) {
                return "DENY_ROLLBACK_UNSAFE_STATE"
            }
        }
    }

    return "ALLOW_OWNED_PARTIAL_ROLLBACK"
}