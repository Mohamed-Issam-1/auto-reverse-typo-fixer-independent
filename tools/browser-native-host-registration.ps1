[CmdletBinding()]
param(
    [ValidateSet("Plan","Register","Unregister")]
    [string]$Mode = "Plan",

    [ValidateSet("ChromiumShared","Edge")]
    [string]$Scope = "ChromiumShared",

    [string]$ExtensionId = "",
    [switch]$Apply,
    [string]$Approval = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not [Environment]::Is64BitProcess) {
    throw "Use 64-bit Windows PowerShell"
}

$name = "com.autoreversetypofixer.health"
$owner = "ARF-9C4B-Manager-v1"

$directory = Join-Path $env:LOCALAPPDATA `
    "AutoReverseTypoFixer\DevNativeHost_9C3B"

$exe = Join-Path $directory "arf-native-host.exe"
$manifestPath = Join-Path $directory "$name.json"

$subkey = if ($Scope -eq "Edge") {
    "Software\Microsoft\Edge\NativeMessagingHosts\$name"
} else {
    "Software\Google\Chrome\NativeMessagingHosts\$name"
}

if ($ExtensionId -and $ExtensionId -cnotmatch '^[a-p]{32}$') {
    throw "Invalid Chromium extension ID"
}

if ($Mode -ne "Plan") {
    $expectedApproval = "${Mode}_${Scope}"

    if (-not $Apply -or $Approval -cne $expectedApproval) {
        throw "Explicit approval required: -Apply -Approval '$expectedApproval'"
    }

    if (-not $ExtensionId) {
        throw "ExtensionId is required for Registry changes"
    }
}

function Get-KeyEntries {
    param(
        [Microsoft.Win32.RegistryHive]$Hive,
        [string]$Path
    )

    $items = New-Object 'System.Collections.Generic.List[object]'

    foreach ($view in @(
        [Microsoft.Win32.RegistryView]::Registry32,
        [Microsoft.Win32.RegistryView]::Registry64
    )) {
        $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            $Hive, $view
        )

        try {
            $key = $root.OpenSubKey($Path, $false)

            if ($null -eq $key) {
                continue
            }

            try {
                $items.Add([pscustomobject]@{
                    Hive = [string]$Hive
                    View = [string]$view
                    Path = [string]$key.GetValue("")
                    Owner = [string]$key.GetValue("ARFManagedBy")
                    Origin = [string]$key.GetValue("ARFRegisteredOrigin")
                    Values = @($key.GetValueNames() | Sort-Object)
                    Children = [int]$key.SubKeyCount
                })
            }
            finally {
                $key.Close()
            }
        }
        finally {
            $root.Close()
        }
    }

    return @($items.ToArray())
}

$exeExists = Test-Path -LiteralPath $exe -PathType Leaf
$manifestExists = Test-Path -LiteralPath $manifestPath -PathType Leaf

$validManifest = $false
$allowlisted = $false

if ($exeExists -and $manifestExists) {
    $manifest = Get-Content -LiteralPath $manifestPath `
        -Raw | ConvertFrom-Json

    $origins = @($manifest.allowed_origins)

    $validOrigins = (
        $origins.Count -gt 0 -and
        @($origins | Where-Object {
            $_ -isnot [string] -or
            $_ -cnotmatch '^chrome-extension://[a-p]{32}/$'
        }).Count -eq 0 -and
        @($origins | Select-Object -Unique).Count -eq $origins.Count
    )

    $validManifest = (
        $manifest.name -ceq $name -and
        $manifest.type -ceq "stdio" -and
        $manifest.path -ceq $exe -and
        $validOrigins
    )

    if ($ExtensionId) {
        $allowlisted = $validManifest -and (
            $origins -ccontains "chrome-extension://$ExtensionId/"
        )
    }
}

$userEntries = @(
    Get-KeyEntries -Hive CurrentUser -Path $subkey
)

$machineEntries = @(
    Get-KeyEntries -Hive LocalMachine -Path $subkey
)

Write-Host "`n=== ARF BROWSER REGISTRATION ==="
Write-Host "MODE=$Mode"
Write-Host "SCOPE=$Scope"
Write-Host "REGISTRY=HKCU\$subkey"
Write-Host "HOST_PRESENT=$exeExists"
Write-Host "MANIFEST_VALID=$validManifest"
Write-Host "ORIGIN_ALLOWLISTED=$allowlisted"
Write-Host "HKCU_VIEWS_FOUND=$($userEntries.Count)"
Write-Host "HKLM_VIEWS_FOUND=$($machineEntries.Count)"
Write-Host "CHROMIUM_SHARED=Chrome and Brave share a registry key"

foreach ($entry in @($userEntries) + @($machineEntries)) {
    Write-Host (
        "ENTRY=$($entry.Hive)/$($entry.View); " +
        "PATH_MATCH=$($entry.Path -ceq $manifestPath); " +
        "MANAGED=$($entry.Owner -ceq $owner)"
    )
}

if ($Mode -eq "Plan") {
    if (-not $validManifest) {
        $state = "HOST_NOT_READY"
    }
    elseif (-not $ExtensionId) {
        $state = "EXTENSION_ID_REQUIRED"
    }
    elseif (-not $allowlisted) {
        $state = "ORIGIN_NOT_ALLOWLISTED"
    }
    elseif (@(
        $userEntries | Where-Object {
            $_.Path -cne $manifestPath
        }
    ).Count -gt 0) {
        $state = "CONFLICTING_USER_REGISTRATION"
    }
    elseif ($userEntries.Count -gt 0) {
        if (@(
            $userEntries | Where-Object {
                $_.Owner -cne $owner
            }
        ).Count -gt 0) {
            $state = "EXISTING_UNMANAGED_REGISTRATION_PRESERVED"
        }
        else {
            $state = "EXISTING_MANAGER_REGISTRATION"
        }
    }
    elseif ($machineEntries.Count -gt 0) {
        $state = "MACHINE_REGISTRATION_REQUIRES_REVIEW"
    }
    else {
        $state = "READY_FOR_EXPLICIT_REGISTRATION"
    }

    Write-Host "STATE=$state"
    Write-Host "BATCH_9C4B_PLAN_COMPLETE"
    Write-Host "REGISTRY_WRITES=NO"
    return
}

if (-not $validManifest -or -not $allowlisted) {
    throw "Host manifest or extension allowlist is not ready"
}

if (@(
    $userEntries | Where-Object {
        $_.Path -cne $manifestPath
    }
).Count -gt 0) {
    throw "Existing registration points elsewhere"
}

if ($machineEntries.Count -gt 0) {
    throw "Machine-wide registration requires review"
}

. (Join-Path $PSScriptRoot "browser-registration-snapshot.ps1")

$decision = Get-ArfRegistrationDecision `
    -Mode $Mode `
    -ManifestValid ([bool]$validManifest) `
    -OriginAllowlisted ([bool]$allowlisted) `
    -ManifestPath $manifestPath `
    -ExtensionOrigin "chrome-extension://$ExtensionId/" `
    -Owner $owner `
    -UserEntries $userEntries `
    -MachineEntries $machineEntries

$requiredDecision = if ($Mode -eq "Register") {
    "ALLOW_REGISTER"
} else {
    "ALLOW_UNREGISTER"
}

if ($decision -cne $requiredDecision) {
    throw "Registration policy blocked operation: $decision"
}

Write-Host "POLICY_PRECHECK=$decision"

# Refresh both Registry hives after the initial policy decision.
# These reads do not write to Registry.
$freshUserEntries = @(
    Get-KeyEntries -Hive CurrentUser -Path $subkey
)

$freshMachineEntries = @(
    Get-KeyEntries -Hive LocalMachine -Path $subkey
)

$origin = "chrome-extension://$ExtensionId/"

$stableDecision = Get-ArfStableRegistrationDecision `
    -Mode $Mode `
    -Scope $Scope `
    -ManifestValid ([bool]$validManifest) `
    -OriginAllowlisted ([bool]$allowlisted) `
    -ManifestPath $manifestPath `
    -ExtensionOrigin $origin `
    -Owner $owner `
    -BeforeUserEntries $userEntries `
    -AfterUserEntries $freshUserEntries `
    -BeforeMachineEntries $machineEntries `
    -AfterMachineEntries $freshMachineEntries

if ($stableDecision -cne $requiredDecision) {
    throw "Snapshot safety gate blocked operation: $stableDecision"
}

Write-Host "SNAPSHOT_GATE=$stableDecision"
$root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::CurrentUser,
    [Microsoft.Win32.RegistryView]::Registry64
)

try {
    if ($Mode -eq "Register") {
        if ($userEntries.Count -gt 0) {
            Write-Host "REGISTRATION_ALREADY_PRESENT_NO_CHANGES"
            return
        }

        $check = $root.OpenSubKey($subkey, $false)

        if ($null -ne $check) {
            $check.Close()
            throw "Registry key appeared during operation"
        }

        $key = $root.CreateSubKey($subkey)

        if ($null -eq $key) {
            throw "Could not create Registry key"
        }

        try {
            if ($key.ValueCount -ne 0 -or $key.SubKeyCount -ne 0) {
                throw "Registry key is not empty; refusing overwrite"
            }

            $key.SetValue(
                "ARFManagedBy", $owner,
                [Microsoft.Win32.RegistryValueKind]::String
            )

            $key.SetValue(
                "ARFRegisteredOrigin",
                "chrome-extension://$ExtensionId/",
                [Microsoft.Win32.RegistryValueKind]::String
            )

            $key.SetValue(
                "", $manifestPath,
                [Microsoft.Win32.RegistryValueKind]::String
            )
        }
        finally {
            $key.Close()
        }

        $verified = @(
            Get-KeyEntries -Hive CurrentUser -Path $subkey
        )

        if (
            $verified.Count -eq 0 -or
            @($verified | Where-Object {
                $_.Path -cne $manifestPath -or
                $_.Owner -cne $owner -or
                $_.Origin -cne "chrome-extension://$ExtensionId/"
            }).Count -gt 0
        ) {
            throw "Post-registration verification failed"
        }

        Write-Host "ARF_REGISTRATION_CREATED_AND_VERIFIED"
    }
    else {
        if ($userEntries.Count -eq 0) {
            Write-Host "NO_MANAGER_REGISTRATION_TO_REMOVE"
            return
        }

        $allowedNames = @(
            "", "ARFManagedBy", "ARFRegisteredOrigin"
        ) | Sort-Object

        foreach ($entry in $userEntries) {
            if (
                $entry.Owner -cne $owner -or
                $entry.Origin -cne "chrome-extension://$ExtensionId/" -or
                $entry.Path -cne $manifestPath -or
                $entry.Children -ne 0 -or
                (($entry.Values -join "|") -cne ($allowedNames -join "|"))
            ) {
                throw "Registration not owned by manager; refusing removal"
            }
        }

        $parentPath = $subkey.Substring(
            0, $subkey.LastIndexOf("\")
        )

        $parent = $root.OpenSubKey($parentPath, $true)

        if ($null -eq $parent) {
            throw "Registry parent disappeared"
        }

        try {
            # Final read-only recheck immediately before deletion.
# ChromiumShared removal is always denied by the stable policy.
$beforeDeleteUser = @(
    Get-KeyEntries -Hive CurrentUser -Path $subkey
)

$beforeDeleteMachine = @(
    Get-KeyEntries -Hive LocalMachine -Path $subkey
)

$deleteDecision = Get-ArfStableRegistrationDecision `
    -Mode Unregister `
    -Scope $Scope `
    -ManifestValid ([bool]$validManifest) `
    -OriginAllowlisted ([bool]$allowlisted) `
    -ManifestPath $manifestPath `
    -ExtensionOrigin $origin `
    -Owner $owner `
    -BeforeUserEntries $freshUserEntries `
    -AfterUserEntries $beforeDeleteUser `
    -BeforeMachineEntries $freshMachineEntries `
    -AfterMachineEntries $beforeDeleteMachine

if ($deleteDecision -cne "ALLOW_UNREGISTER") {
    throw "Final deletion guard blocked operation: $deleteDecision"
}

Write-Host "FINAL_DELETE_GATE=ALLOW_UNREGISTER"
        $parent.DeleteSubKey($name, $false)
        }
        finally {
            $parent.Close()
        }

        if (@(
            Get-KeyEntries -Hive CurrentUser -Path $subkey
        ).Count -ne 0) {
            throw "Registration was not fully removed"
        }

        Write-Host "ARF_OWNED_REGISTRATION_REMOVED"
    }
}
finally {
    $root.Close()
}

Write-Host "NO_HOST_FILES_REMOVED=YES"
Write-Host "TEXT_CORRECTION=DISABLED"