$ErrorActionPreference = 'Stop'
$testScript = Join-Path $PSScriptRoot 'test.ps1'
$ErrorActionPreference = 'Continue'
$output = & powershell -NoProfile -ExecutionPolicy Bypass -File $testScript 'tests/fixtures/runtime_error_fixture.gd' 2>&1
$exitCode = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$rendered = $output -join [Environment]::NewLine

Write-Output $rendered

if ($exitCode -eq 0) {
    Write-Error 'The test harness returned success for a runtime script error.'
    exit 1
}

if ($rendered -notmatch 'SCRIPT ERROR:' -or $rendered -notmatch 'intentional harness fixture') {
    Write-Error 'The runtime-error fixture was not executed by the test harness.'
    exit 1
}

Write-Output 'PASS: runtime script errors make the test command fail.'
exit 0
