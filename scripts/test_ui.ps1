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

$viewTests = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests\view') -Filter '*_test.gd' |
    Sort-Object Name |
    ForEach-Object { 'tests/view/' + $_.Name }

& (Join-Path $PSScriptRoot 'test.ps1') @viewTests
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$fixture = 'res://src/view/app/ui_fixture.tscn'
if ($Visual) {
    & $godotBin '--path' $projectRoot $fixture
    exit $LASTEXITCODE
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

$output = & $godotBin @arguments 2>&1
$exitCode = $LASTEXITCODE
$rendered = $output -join [Environment]::NewLine
Write-Output $rendered
if ($exitCode -ne 0 -or $rendered -match '(?m)^(SCRIPT ERROR|ERROR):') {
    exit 1
}

exit 0
