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
$godotBin = (Resolve-Path -LiteralPath $godotBin).Path
$godotFileName = [System.IO.Path]::GetFileName($godotBin)
if ($godotFileName -match '_console\.exe$') {
    $editorCandidate = Join-Path ([System.IO.Path]::GetDirectoryName($godotBin)) ($godotFileName -replace '_console(?=\.exe$)', '')
    if (Test-Path -LiteralPath $editorCandidate -PathType Leaf) {
        $godotBin = (Resolve-Path -LiteralPath $editorCandidate).Path
    }
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

function Quote-ProcessArgument([string]$Value) {
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + $Value.Replace('"', '\"') + '"'
}
$argumentLine = ($godotArguments | ForEach-Object { Quote-ProcessArgument $_ }) -join ' '
$runId = [guid]::NewGuid().ToString('N')
$stdoutPath = Join-Path $testLogDirectory ($runId + '.stdout.log')
$stderrPath = Join-Path $testLogDirectory ($runId + '.stderr.log')
$process = Start-Process -FilePath $godotBin -ArgumentList $argumentLine `
    -WorkingDirectory $projectRoot -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru -Wait
$godotExitCode = $process.ExitCode
$output = @()
if (Test-Path -LiteralPath $stdoutPath) { $output += Get-Content -LiteralPath $stdoutPath }
if (Test-Path -LiteralPath $stderrPath) { $output += Get-Content -LiteralPath $stderrPath }
$renderedOutput = $output -join [Environment]::NewLine
Write-Output $renderedOutput
Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue

$hasEngineError = $renderedOutput -match '(?m)^(SCRIPT ERROR|ERROR):'
if ($godotExitCode -ne 0 -or $hasEngineError) {
    exit 1
}

exit 0
