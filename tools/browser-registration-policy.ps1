# Pure decision logic. No Registry, filesystem or process operations.

function Get-ArfRegistrationDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Register", "Unregister")]
        [string]$Mode,

        [bool]$ManifestValid,
        [bool]$OriginAllowlisted,
        [string]$ManifestPath,
        [string]$ExtensionOrigin,
        [string]$Owner,
        [object[]]$UserEntries = @(),
        [object[]]$MachineEntries = @()
    )

    if (-not $ManifestValid) {
        return "DENY_INVALID_MANIFEST"
    }

    if (-not $OriginAllowlisted) {
        return "DENY_ORIGIN_NOT_ALLOWLISTED"
    }

    if ($ExtensionOrigin -cnotmatch '^chrome-extension://[a-p]{32}/$') {
        return "DENY_INVALID_EXTENSION_ORIGIN"
    }

    if (-not $ManifestPath -or -not $Owner) {
        return "DENY_MISSING_IDENTITY"
    }

    if ($MachineEntries.Count -gt 0) {
        return "DENY_MACHINE_REGISTRATION"
    }

    foreach ($entry in $UserEntries) {
        if ($null -eq $entry) {
            return "DENY_MALFORMED_REGISTRATION"
        }

        if ($entry.Path -cne $ManifestPath) {
            return "DENY_PATH_CONFLICT"
        }
    }

    if ($Mode -eq "Register") {
        if ($UserEntries.Count -gt 0) {
            return "DENY_ALREADY_REGISTERED"
        }

        return "ALLOW_REGISTER"
    }

    if ($UserEntries.Count -eq 0) {
        return "DENY_NOT_REGISTERED"
    }

    $expectedValues = @(
        "", "ARFManagedBy", "ARFRegisteredOrigin"
    ) | Sort-Object

    foreach ($entry in $UserEntries) {
        if ($entry.Owner -cne $Owner) {
            return "DENY_UNMANAGED_REGISTRATION"
        }

        if ($entry.Origin -cne $ExtensionOrigin) {
            return "DENY_ORIGIN_MISMATCH"
        }

        if ($entry.Children -ne 0) {
            return "DENY_CHILD_KEYS_PRESENT"
        }

        $actualValues = @($entry.Values | Sort-Object)

        if (($actualValues -join "|") -cne
            ($expectedValues -join "|")) {
            return "DENY_UNEXPECTED_VALUES"
        }
    }

    return "ALLOW_UNREGISTER"
}