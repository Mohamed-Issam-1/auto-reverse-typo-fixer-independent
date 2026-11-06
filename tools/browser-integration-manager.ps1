[CmdletBinding()]
param(
    [ValidateSet("Audit", "Plan")]
    [string]$Mode = "Audit",

    [string]$ChromeExtensionId = "",
    [string]$BraveExtensionId = "",
    [string]$EdgeExtensionId = "",

    [string]$ReportPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not [Environment]::Is64BitProcess) {
    throw "64-bit Windows PowerShell is required"
}

$hostName = "com.autoreversetypofixer.health"

$installDir = Join-Path $env:LOCALAPPDATA `
    "AutoReverseTypoFixer\DevNativeHost_9C3B"

$manifestPath = Join-Path $installDir "$hostName.json"
$exePath = Join-Path $installDir "arf-native-host.exe"

$chromeKey = "Software\Google\Chrome\NativeMessagingHosts\$hostName"
$edgeKey = "Software\Microsoft\Edge\NativeMessagingHosts\$hostName"
$chromiumKey = "Software\Chromium\NativeMessagingHosts\$hostName"
$braveKey = "Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\$hostName"

$browsers = @(
    [pscustomobject]@{
        Name = "Chrome"
        RelativeExe = "Google\Chrome\Application\chrome.exe"
        ExtensionId = $ChromeExtensionId
        SearchKeys = @($chromeKey)
    },
    [pscustomobject]@{
        Name = "Brave"
        RelativeExe = "BraveSoftware\Brave-Browser\Application\brave.exe"
        ExtensionId = $BraveExtensionId
        SearchKeys = @($chromeKey)
    },
    [pscustomobject]@{
        Name = "Edge"
        RelativeExe = "Microsoft\Edge\Application\msedge.exe"
        ExtensionId = $EdgeExtensionId
        SearchKeys = @($edgeKey, $chromiumKey, $chromeKey)
    }
)

$report = New-Object 'System.Collections.Generic.List[string]'

function Add-Report {
    param([string]$Value)
    $report.Add($Value)
    Write-Host $Value
}

function Find-Browser {
    param([string]$RelativeExe)

    $bases = @(
        $env:ProgramFiles
        [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
        $env:LOCALAPPDATA
    ) | Where-Object { $_ }

    foreach ($base in $bases) {
        $candidate = Join-Path $base $RelativeExe
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Get-HostRegistrations {
    param([string[]]$Subkeys)

    $rows = New-Object 'System.Collections.Generic.List[object]'

    foreach ($hive in @(
        [Microsoft.Win32.RegistryHive]::CurrentUser
        [Microsoft.Win32.RegistryHive]::LocalMachine
    )) {
        foreach ($view in @(
            [Microsoft.Win32.RegistryView]::Registry32
            [Microsoft.Win32.RegistryView]::Registry64
        )) {
            $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                $hive, $view
            )

            try {
                foreach ($subkey in $Subkeys) {
                    $key = $root.OpenSubKey($subkey, $false)

                    if ($null -eq $key) {
                        continue
                    }

                    try {
                        $value = [string]$key.GetValue(
                            "",
                            $null,
                            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
                        )

                        $rows.Add([pscustomobject]@{
                            Hive = [string]$hive
                            View = [string]$view
                            Subkey = $subkey
                            Path = $value
                        })
                    }
                    finally {
                        $key.Close()
                    }
                }
            }
            finally {
                $root.Close()
            }
        }
    }

    return @($rows.ToArray())
}

function Assert-ExtensionId {
    param([string]$Id, [string]$Browser)

    if ($Id -and $Id -cnotmatch '^[a-p]{32}$') {
        throw "Invalid $Browser extension ID"
    }
}

foreach ($browser in $browsers) {
    Assert-ExtensionId $browser.ExtensionId $browser.Name
}

Add-Report "BATCH_9C4A_BROWSER_INTEGRATION_AUDIT"
Add-Report "MODE=$Mode"
Add-Report "REGISTRY_WRITES=NO"
Add-Report "TEXT_CORRECTION=DISABLED"
Add-Report ""

Add-Report "=== LOCAL HOST ==="

$exeExists = Test-Path -LiteralPath $exePath -PathType Leaf
$manifestExists = Test-Path -LiteralPath $manifestPath -PathType Leaf

Add-Report "HOST_EXE_EXISTS=$exeExists"
Add-Report "HOST_MANIFEST_EXISTS=$manifestExists"

$manifestValid = $false
$allowedOrigins = @()

if ($exeExists -and $manifestExists) {
    try {
        $m = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json

        $allowedOrigins = @($m.allowed_origins)

        $originsValid = (
            $allowedOrigins.Count -gt 0 -and
            @(
                $allowedOrigins | Where-Object {
                    $_ -isnot [string] -or
                    $_ -cnotmatch '^chrome-extension://[a-p]{32}/$'
                }
            ).Count -eq 0 -and
            @($allowedOrigins | Select-Object -Unique).Count -eq
                $allowedOrigins.Count
        )

        $manifestValid = (
            $m.name -ceq $hostName -and
            $m.type -ceq "stdio" -and
            $m.path -ceq $exePath -and
            $originsValid
        )
    }
    catch {
        Add-Report "MANIFEST_PARSE_ERROR=$($_.Exception.Message)"
    }
}

Add-Report "HOST_MANIFEST_VALID=$manifestValid"

if ($manifestValid) {
    foreach ($origin in $allowedOrigins) {
        Add-Report "ALLOWED_ORIGIN=$origin"
    }
}

Add-Report ""
Add-Report "=== REGISTRY INVENTORY ==="

$keys = @(
    $chromeKey, $edgeKey, $chromiumKey, $braveKey
)

$entries = @(
    Get-HostRegistrations -Subkeys $keys
)

if ($entries.Count -eq 0) {
    Add-Report "NO_NATIVE_HOST_REGISTRATIONS_FOUND"
}

foreach ($entry in $entries) {
    $matches = $entry.Path -ceq $manifestPath

    Add-Report (
        "REGISTRY | $($entry.Hive) | $($entry.View) | " +
        "$($entry.Subkey) | PATH_MATCH=$matches"
    )
}

Add-Report ""
Add-Report "=== BROWSER INTEGRATION ==="

foreach ($browser in $browsers) {
    $exe = Find-Browser $browser.RelativeExe
    $installed = $null -ne $exe

    $matches = @(
        $entries | Where-Object {
            $browser.SearchKeys -contains $_.Subkey -and
            $_.Path -ceq $manifestPath
        }
    )

    $conflicts = @(
        $entries | Where-Object {
            $browser.SearchKeys -contains $_.Subkey -and
            $_.Path -cne $manifestPath
        }
    )

    $id = $browser.ExtensionId
    $origin = if ($id) {
        "chrome-extension://$id/"
    } else {
        ""
    }

    $allowlisted = (
        $manifestValid -and
        $id -and
        $allowedOrigins -ccontains $origin
    )

    if (-not $installed) {
        $state = "BROWSER_NOT_FOUND_IN_COMMON_PATHS"
    }
    elseif (-not $manifestValid) {
        $state = "LOCAL_HOST_NOT_READY"
    }
    elseif (-not $id) {
        $state = "EXTENSION_ID_REQUIRED"
    }
    elseif (-not $allowlisted) {
        $state = "EXTENSION_ORIGIN_NOT_ALLOWED"
    }
    elseif ($conflicts.Count -gt 0) {
        $state = "REGISTRATION_CONFLICT"
    }
    elseif ($matches.Count -eq 0) {
        $state = "HOST_REGISTRATION_MISSING"
    }
    else {
        $state = "CONFIGURED_RUNTIME_TEST_REQUIRED"
    }

    Add-Report (
        "$($browser.Name) | INSTALLED=$installed | " +
        "MATCHING_REGISTRATIONS=$($matches.Count) | " +
        "CONFLICTS=$($conflicts.Count) | " +
        "STATE=$state"
    )

    if ($Mode -eq "Plan") {
        if (-not $id) {
            Add-Report "PLAN_$($browser.Name)=OBTAIN_EXTENSION_ID"
        }
        elseif (-not $allowlisted) {
            Add-Report "PLAN_$($browser.Name)=REVIEW_MANIFEST_ALLOWLIST"
        }
        elseif ($matches.Count -eq 0) {
            Add-Report "PLAN_$($browser.Name)=REVIEW_REGISTRY_REGISTRATION"
        }
        else {
            Add-Report "PLAN_$($browser.Name)=VERIFY_NATIVE_HEALTH_IN_BROWSER"
        }
    }
}

Add-Report ""
Add-Report "=== SAFETY ==="
Add-Report "NO_REGISTRY_CHANGES=YES"
Add-Report "NO_BROWSER_EXTENSION_INSTALLATION=YES"
Add-Report "NO_KEYBOARD_HOOKS=YES"
Add-Report "NO_SENDINPUT=YES"
Add-Report "AUDIT_GATE=READ_ONLY_COMPLETE"

if (-not $ReportPath) {
    $ReportPath = Join-Path `
        ([Environment]::GetFolderPath("Desktop")) `
        "ARF_Batch9C4A_Browser_Integration_Report.txt"
}

[IO.File]::WriteAllLines(
    $ReportPath,
    [string[]]$report.ToArray(),
    (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "REPORT=$ReportPath"
Write-Host "BATCH_9C4A_AUDIT_COMPLETE" -ForegroundColor Green