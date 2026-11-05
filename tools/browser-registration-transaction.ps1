# Dependency-injected registration transaction.
# No direct Registry, filesystem or process operations.
#
# Backend contract:
# Create must prove exclusive NEW-key creation.
# Rollback must compare the complete observed state and remove
# only if unchanged, in one protected operation.
# This module is NOT connected to the production Registry manager.

function Test-ArfTransactionState {
    [CmdletBinding()]
    param(
        [object]$State,
        [string]$Owner,
        [string]$Origin,
        [string]$ManifestPath,
        [switch]$RequireComplete
    )

    if ($null -eq $State) {
        return $false
    }

    foreach ($property in @("Exists", "Children", "Values")) {
        if ($null -eq $State.PSObject.Properties[$property]) {
            return $false
        }
    }

    if (-not $State.Exists -or $State.Children -ne 0) {
        return $false
    }

    $values = $State.Values

    if ($values -isnot [System.Collections.IDictionary]) {
        return $false
    }

    $allowed = @("", "ARFManagedBy", "ARFRegisteredOrigin")

    foreach ($name in @($values.Keys)) {
        if ($name -isnot [string] -or
            $allowed -cnotcontains $name -or
            $values[$name] -isnot [string]) {
            return $false
        }
    }

    if ($RequireComplete -and $values.Count -ne 3) {
        return $false
    }

    if ($values.Count -eq 0) {
        return (-not $RequireComplete)
    }

    # Registration writes owner first, origin second,
    # and the browser-visible default value last.
    if (-not $values.Contains("ARFManagedBy")) {
        return $false
    }

    if ($values["ARFManagedBy"] -cne $Owner) {
        return $false
    }

    if ($values.Contains("ARFRegisteredOrigin")) {
        if ($values["ARFRegisteredOrigin"] -cne $Origin) {
            return $false
        }
    }
    elseif ($values.Contains("")) {
        return $false
    }

    if ($values.Contains("")) {
        if ($values[""] -cne $ManifestPath) {
            return $false
        }

        if (-not $values.Contains("ARFRegisteredOrigin")) {
            return $false
        }
    }

    if ($RequireComplete) {
        return (
            $values.Contains("") -and
            $values.Contains("ARFManagedBy") -and
            $values.Contains("ARFRegisteredOrigin")
        )
    }

    return $true
}

function Invoke-ArfRegistrationTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Backend,

        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Origin,

        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    foreach ($action in @(
        "Create", "SetValue", "Read", "Rollback"
    )) {
        if (
            -not $Backend.ContainsKey($action) -or
            $Backend[$action] -isnot [scriptblock]
        ) {
            throw "Invalid transaction backend: $action"
        }
    }

    $create = $Backend["Create"]
    $setValue = $Backend["SetValue"]
    $read = $Backend["Read"]
    $rollback = $Backend["Rollback"]

    try {
        $disposition = & $create
    }
    catch {
        return "FAILED_CREATE_EXCEPTION"
    }

    if ($disposition -cne "CREATED_NEW") {
        return "DENY_CREATION_UNPROVEN"
    }

    try {
        $null = & $setValue "ARFManagedBy" $Owner
        $null = & $setValue "ARFRegisteredOrigin" $Origin
        $null = & $setValue "" $ManifestPath

        $verified = & $read

        if (-not (Test-ArfTransactionState `
            -State $verified `
            -Owner $Owner `
            -Origin $Origin `
            -ManifestPath $ManifestPath `
            -RequireComplete)) {
            throw "Post-registration verification failed"
        }

        return "REGISTERED"
    }
    catch {
        # Creation was explicitly confirmed as NEW.
        # Inspect before considering rollback.
    }

    try {
        $current = & $read
    }
    catch {
        return "FAILED_UNREADABLE_STATE"
    }

    if ($null -eq $current -or
        $null -eq $current.PSObject.Properties["Exists"]) {
        return "FAILED_UNREADABLE_STATE"
    }

    if (-not $current.Exists) {
        return "FAILED_KEY_ALREADY_ABSENT"
    }

    if (-not (Test-ArfTransactionState `
        -State $current `
        -Owner $Owner `
        -Origin $Origin `
        -ManifestPath $ManifestPath)) {
        return "FAILED_UNSAFE_PARTIAL_STATE"
    }

    try {
        $rollbackResult = & $rollback $current
    }
    catch {
        return "FAILED_ROLLBACK_EXCEPTION"
    }

    if ($rollbackResult -cne "REMOVED") {
        return "FAILED_ROLLBACK_CONFLICT"
    }

    try {
        $postRollback = & $read

        if ($null -eq $postRollback -or
            $null -eq $postRollback.PSObject.Properties["Exists"] -or
            $postRollback.Exists) {
            return "FAILED_ROLLBACK_UNVERIFIED"
        }
    }
    catch {
        return "FAILED_ROLLBACK_UNVERIFIED"
    }

    return "FAILED_ROLLED_BACK"
}