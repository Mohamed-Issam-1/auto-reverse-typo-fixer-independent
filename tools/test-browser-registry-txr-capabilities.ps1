Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$probePath = Join-Path $PSScriptRoot `
    "browser-registry-txr-capabilities.ps1"

$managerPath = Join-Path $PSScriptRoot `
    "browser-native-host-registration.ps1"

$source = [IO.File]::ReadAllText(
    (Resolve-Path -LiteralPath $probePath).Path
)

$manager = [IO.File]::ReadAllText(
    (Resolve-Path -LiteralPath $managerPath).Path
)

$script:passed = 0

function Assert-Check {
    param([string]$Name, [bool]$Condition)

    if (-not $Condition) {
        throw "FAILED: $Name"
    }

    $script:passed++
    Write-Host "PASS $Name"
}

Assert-Check "SYSTEM_LIBRARY_EXPORT_INSPECTION" (
    $source.Contains("LoadLibraryExW") -and
    $source.Contains("GetProcAddress") -and
    $source.Contains("FreeLibrary")
)

Assert-Check "SYSTEM32_SEARCH_RESTRICTION" (
    $source.Contains("0x00000800")
)

Assert-Check "NO_BROWSER_REGISTRY_PATH" (
    -not $source.Contains("NativeMessagingHosts")
)

Assert-Check "64_BIT_PROCESS_REQUIRED" (
    $source.Contains("[Environment]::Is64BitProcess")
)

Assert-Check "CREATE_TRANSACTION_EXPORT_REQUESTED" (
    $source.Contains('"CreateTransaction"')
)

Assert-Check "TRANSACTED_CREATE_EXPORT_REQUESTED" (
    $source.Contains('"RegCreateKeyTransactedW"')
)

Assert-Check "TRANSACTED_DELETE_EXPORT_REQUESTED" (
    $source.Contains('"RegDeleteKeyTransactedW"')
)

$guardPos = $manager.IndexOf(
    'throw "WRITE_MODES_SUSPENDED_9C4D2D2"'
)

$readPos = $manager.IndexOf('$userEntries = @(')

$writePos = $manager.IndexOf(
    '$root = [Microsoft.Win32.RegistryKey]::OpenBaseKey('
)

Assert-Check "PRODUCTION_BARRIER_BEFORE_READ" (
    $guardPos -ge 0 -and $readPos -gt $guardPos
)

Assert-Check "PRODUCTION_BARRIER_BEFORE_WRITE" (
    $guardPos -ge 0 -and $writePos -gt $guardPos
)

$probeOutput = @(
    & powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File $probePath 2>&1
)

$exitCode = $LASTEXITCODE

$probeOutput | ForEach-Object {
    Write-Host $_
}

Assert-Check "PROBE_COMPLETED" (
    $exitCode -eq 0 -and
    $probeOutput -ccontains "TXR_CAPABILITY_PROBE_COMPLETE"
)

$exportRows = @(
    $probeOutput | Where-Object {
        $_ -like "EXPORT=*"
    }
)

Assert-Check "EIGHT_EXPORT_RESULTS" (
    $exportRows.Count -eq 8
)

$invalidRows = @(
    $exportRows | Where-Object {
        $_ -notmatch '^EXPORT=(advapi32|ktmw32)\.dll:[A-Za-z0-9]+;PRESENT=(True|False)$'
    }
)

Assert-Check "EXPORT_RESULTS_FORMAT_VALID" (
    $invalidRows.Count -eq 0
)

Assert-Check "CAPABILITY_STATE_REPORTED" (
    @(
        $probeOutput | Where-Object {
            $_ -match '^API_EXPORT_SET=(COMPLETE|INCOMPLETE)$'
        }
    ).Count -eq 1
)

Assert-Check "NO_TRANSACTION_CREATED" (
    $probeOutput -ccontains "TRANSACTION_CREATED=NO"
)

Assert-Check "RUNTIME_NOT_CLAIMED_VERIFIED" (
    $probeOutput -ccontains "TXR_RUNTIME_VERIFIED=NO"
)

Assert-Check "ATOMIC_DELETE_NOT_CLAIMED" (
    $probeOutput -ccontains "ATOMIC_COMPARE_DELETE_VERIFIED=NO"
)

Assert-Check "REGISTRY_WRITES_DISABLED" (
    $probeOutput -ccontains "REGISTRY_WRITES=NO"
)

Assert-Check "PRODUCTION_NOT_CONNECTED" (
    $probeOutput -ccontains "PRODUCTION_MANAGER_INTEGRATION=NO"
)

if ($script:passed -ne 18) {
    throw "Unexpected test count: $script:passed"
}

Write-Host ""
Write-Host "TXR_CAPABILITY_TESTS_PASS=18"
Write-Host "PRODUCTION_WRITE_BARRIER=PRESERVED"
Write-Host "TXR_RUNTIME_VERIFIED=NO"
Write-Host "REGISTRY_WRITES=NO"