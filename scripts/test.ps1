param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TestPaths
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotBin = $env:SHIFT_GODOT_BIN
$testLogDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'shift-card-game-tests'
New-Item -ItemType Directory -Force -Path $testLogDirectory | Out-Null
$testLogPath = Join-Path $testLogDirectory 'godot.log'

if ([string]::IsNullOrWhiteSpace($godotBin)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -ne $godotCommand) {
        $godotBin = $godotCommand.Source
    }
}

if ([string]::IsNullOrWhiteSpace($godotBin) -or -not (Test-Path -LiteralPath $godotBin)) {
    Write-Error 'Godot was not found. Set SHIFT_GODOT_BIN or add godot to PATH.'
    exit 2
}

$godotArguments = @(
    '--headless'
    '--path', $projectRoot
    '--log-file', $testLogPath
    '--script', 'res://tests/test_runner.gd'
)

if ($TestPaths.Count -gt 0) {
    $godotArguments += '--'
    $godotArguments += $TestPaths
}

& $godotBin @godotArguments
exit $LASTEXITCODE
