param(
    [switch]$Visual,
    [string]$CapturePath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$godotBin = $env:SHIFT_GODOT_BIN

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

function Quote-ProcessArgument([string]$Value) {
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + $Value.Replace('"', '\"') + '"'
}

$viewTests = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests\view') -Filter '*_test.gd' |
    Sort-Object Name |
    ForEach-Object { 'tests/view/' + $_.Name }

& (Join-Path $PSScriptRoot 'test.ps1') @viewTests
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$fixture = 'res://src/view/app/ui_fixture.tscn'
if ($Visual) {
    $visualArguments = (@('--path', $projectRoot, $fixture) | ForEach-Object { Quote-ProcessArgument $_ }) -join ' '
    $visualProcess = Start-Process -FilePath $godotBin -ArgumentList $visualArguments -WorkingDirectory $projectRoot -PassThru -Wait
    exit $visualProcess.ExitCode
}

if (-not [string]::IsNullOrWhiteSpace($CapturePath)) {
    $resolvedCapture = [System.IO.Path]::GetFullPath($CapturePath)
    $captureParent = Split-Path -Parent $resolvedCapture
    New-Item -ItemType Directory -Force -Path $captureParent | Out-Null
    $arguments = @('--path', $projectRoot, $fixture)
    $arguments += '--'
    $arguments += '--capture-ui=' + $resolvedCapture
}
else {
    $arguments = @('--headless', '--path', $projectRoot, '--quit-after', '4', $fixture)
}

$runId = [guid]::NewGuid().ToString('N')
$stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ('shift-ui-' + $runId + '.stdout.log')
$stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ('shift-ui-' + $runId + '.stderr.log')
$argumentLine = ($arguments | ForEach-Object { Quote-ProcessArgument $_ }) -join ' '
$fixtureProcess = Start-Process -FilePath $godotBin -ArgumentList $argumentLine `
    -WorkingDirectory $projectRoot -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru -Wait
$exitCode = $fixtureProcess.ExitCode
$output = @()
if (Test-Path -LiteralPath $stdoutPath) { $output += Get-Content -LiteralPath $stdoutPath }
if (Test-Path -LiteralPath $stderrPath) { $output += Get-Content -LiteralPath $stderrPath }
$rendered = $output -join [Environment]::NewLine
Write-Output $rendered
Remove-Item -LiteralPath $stdoutPath,$stderrPath -Force -ErrorAction SilentlyContinue
if ($exitCode -ne 0 -or $rendered -match '(?m)^(SCRIPT ERROR|ERROR):') {
    exit 1
}

exit 0
