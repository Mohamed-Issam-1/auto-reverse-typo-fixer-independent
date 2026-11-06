Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$probePath = Join-Path $PSScriptRoot "browser-registry-txr-runtime-probe.ps1"
$managerPath = Join-Path $PSScriptRoot "browser-native-host-registration.ps1"
$source = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $probePath).Path)
$manager = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $managerPath).Path)
$script:passed = 0

function Assert-Check {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:passed++
    Write-Host "PASS $Name"
}

Assert-Check "PLAN_DEFAULT" (
    $source.Contains('[string]$Mode = "Plan"')
)
Assert-Check "MODE_LIMITED_TO_TWO_VALUES" (
    $source.Contains('[ValidateSet("Plan", "TransactionOnly")]')
)
Assert-Check "X64_RESTRICTION" (
    $source.Contains('[Environment]::Is64BitProcess')
)
Assert-Check "PRODUCTION_BARRIER_SOURCE_CHECK" (
    $source.Contains('PRODUCTION_WRITE_BARRIER_MISSING_OR_MOVED') -and
    $source.Contains('WRITE_MODES_SUSPENDED_9C4D2D2') -and
    $manager.Contains('throw "WRITE_MODES_SUSPENDED_9C4D2D2"')
)
Assert-Check "PLAN_EXITS_BEFORE_NATIVE_API" (
    $source.IndexOf('if ($Mode -eq "Plan")') -ge 0 -and
    $source.IndexOf('if ($Mode -eq "Plan")') -lt
    $source.IndexOf('Add-Type -TypeDefinition')
)
Assert-Check "SEPARATE_EXACT_APPROVAL" (
    $source.Contains('$Approval -cne "RUN_TRANSACTION_ONLY_9C4D2D4B"') -and
    $source.IndexOf('TRANSACTION_ONLY_APPROVAL_REQUIRED') -lt
    $source.IndexOf('Add-Type -TypeDefinition')
)
Assert-Check "KTM_APIS_RESTRICTED" (
    $source.Contains('EntryPoint = "CreateTransaction"') -and
    $source.Contains('EntryPoint = "RollbackTransaction"') -and
    $source.Contains('EntryPoint = "CloseHandle"')
)
Assert-Check "INVALID_HANDLE_CHECK" (
    $source.Contains('new IntPtr(-1)')
)
Assert-Check "CLOSE_IN_FINALLY" (
    $source.Contains('finally') -and
    $source.Contains('r.Closed = CloseNativeHandle(h);')
)
Assert-Check "NO_REGISTRY_NATIVE_APIS" (
    $source -notmatch 'Reg(Create|Open|Delete|Set|Close)Key' -and
    $source -notmatch '\bCommitTransaction\b' -and
    $source -notmatch '\bNativeMessagingHosts\b'
)
Assert-Check "NO_REGISTRY_POWERSHELL_MUTATION" (
    $source -notmatch '\b(Set-ItemProperty|New-ItemProperty|Remove-ItemProperty|Remove-Item|New-Item|reg\.exe)\b' -and
    $source -notmatch 'DllImport\("advapi32\.dll"'
)
Assert-Check "RUNTIME_CLAIMS_LIMITED" (
    $source.Contains('Write-Host "TXR_REGISTRY_RUNTIME_VERIFIED=NO"') -and
    $source.Contains('Write-Host "ATOMIC_COMPARE_DELETE_VERIFIED=NO"') -and
    $source.Contains('Write-Host "PRODUCTION_MANAGER_INTEGRATION=NO"')
)

$output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $probePath 2>&1)
$exitCode = $LASTEXITCODE
$output | ForEach-Object { Write-Host $_ }

Assert-Check "PLAN_PROCESS_EXIT" (
    $exitCode -eq 0 -and
    $output -ccontains "TXR_RUNTIME_PLAN_COMPLETE"
)
Assert-Check "PLAN_NEVER_CREATES_TRANSACTION" (
    $output -ccontains "TRANSACTION_CREATED=NO" -and
    $output -ccontains "KTM_HANDLE_RUNTIME_VERIFIED=NO"
)
Assert-Check "PLAN_ZERO_REGISTRY_ACCESS" (
    $output -ccontains "REGISTRY_READS=NO" -and
    $output -ccontains "REGISTRY_WRITES=NO" -and
    $output -ccontains "BROWSER_REGISTRY_KEYS_TOUCHED=NO"
)
Assert-Check "PLAN_BARRIER_PRESERVED" (
    $output -ccontains "PRODUCTION_WRITE_BARRIER=PRESERVED" -and
    $output -ccontains "PRODUCTION_MANAGER_INTEGRATION=NO" -and
    $output -ccontains "TXR_RUNTIME_VERIFIED=NO"
)

if ($script:passed -ne 16) {
    throw "Unexpected test count: $script:passed"
}
Write-Host "TXR_HANDLE_PROBE_PLAN_TESTS_PASS=16"
Write-Host "TRANSACTION_CREATED=NO"
Write-Host "REGISTRY_WRITES=NO"
Write-Host "PRODUCTION_WRITE_BARRIER=PRESERVED"
