param(
    [string]$GodotBin = $env:SHIFT_GODOT_BIN,
    [switch]$SkipSmoke,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$windowsDirectory = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'build\windows'))
$zipPath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'build\shift-windows-x64.zip'))
$executablePath = Join-Path $windowsDirectory 'Shift.exe'
$markerPath = Join-Path ([System.IO.Path]::GetTempPath()) ('shift-startup-smoke-' + [guid]::NewGuid().ToString('N') + '.txt')
$releaseDll = Join-Path $projectRoot 'addons\webrtc_native\lib\libwebrtc_native.windows.template_release.x86_64.dll'

function Assert-ProjectChildPath([string]$Path, [string]$ExpectedRelativePath) {
    $expected = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $ExpectedRelativePath))
    if (-not $Path.Equals($expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing filesystem operation outside the expected project path: $Path"
    }
    $rootPrefix = $projectRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $Path.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing filesystem operation outside project root: $Path"
    }
}

Assert-ProjectChildPath $windowsDirectory 'build\windows'
Assert-ProjectChildPath $zipPath 'build\shift-windows-x64.zip'

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -ne $godotCommand) {
        $GodotBin = $godotCommand.Source
    }
}
if ([string]::IsNullOrWhiteSpace($GodotBin) -or -not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) {
    throw 'Godot editor was not found. Set SHIFT_GODOT_BIN to the Godot 4.7.2 console executable or add godot to PATH.'
}
$GodotBin = (Resolve-Path -LiteralPath $GodotBin).Path
$godotFileName = [System.IO.Path]::GetFileName($GodotBin)
if ($godotFileName -match '_console\.exe$') {
    $editorCandidate = Join-Path ([System.IO.Path]::GetDirectoryName($GodotBin)) ($godotFileName -replace '_console(?=\.exe$)', '')
    if (Test-Path -LiteralPath $editorCandidate -PathType Leaf) {
        $GodotBin = (Resolve-Path -LiteralPath $editorCandidate).Path
    }
}
if (-not (Test-Path -LiteralPath $releaseDll -PathType Leaf)) {
    throw "Native WebRTC Windows x64 release library is missing: $releaseDll. Run scripts/install_webrtc.ps1."
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'export_presets.cfg') -PathType Leaf)) {
    throw 'export_presets.cfg is missing.'
}

$versionOutput = ((Get-Item -LiteralPath $GodotBin).VersionInfo.ProductVersion -as [string]).Trim()
if ([string]::IsNullOrWhiteSpace($versionOutput)) {
    throw "Unable to read Godot version from $GodotBin."
}
$versionMatch = [regex]::Match($versionOutput, '^(?<version>\d+\.\d+(?:\.\d+)?)\.(?<status>[A-Za-z0-9_-]+)')
if (-not $versionMatch.Success) {
    throw "Unrecognized Godot version string: $versionOutput"
}
$templateVersion = $versionMatch.Groups['version'].Value + '.' + $versionMatch.Groups['status'].Value
$templateDirectory = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion"
$releaseTemplate = Join-Path $templateDirectory 'windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $releaseTemplate -PathType Leaf)) {
    throw "Godot $templateVersion Windows x64 export template is missing: $releaseTemplate. Install the matching export templates from Editor > Manage Export Templates."
}

if ($ValidateOnly) {
    Write-Output "validation_ok godot=$versionOutput template=$releaseTemplate webrtc=$releaseDll"
    exit 0
}

if (Test-Path -LiteralPath $windowsDirectory) {
    Remove-Item -LiteralPath $windowsDirectory -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
New-Item -ItemType Directory -Force -Path $windowsDirectory | Out-Null

Write-Output "Exporting Shift for Windows x64 with Godot $versionOutput..."
$exportLogBase = Join-Path ([System.IO.Path]::GetTempPath()) ('shift-export-' + [guid]::NewGuid().ToString('N'))
$exportOutputLog = $exportLogBase + '.out.log'
$exportErrorLog = $exportLogBase + '.err.log'
$quotedProjectRoot = '"' + $projectRoot + '"'
$quotedExecutablePath = '"' + $executablePath + '"'
$exportProcess = Start-Process -FilePath $GodotBin -ArgumentList @('--headless', '--path', $quotedProjectRoot, '--export-release', '"Windows x64"', $quotedExecutablePath) -RedirectStandardOutput $exportOutputLog -RedirectStandardError $exportErrorLog -PassThru -Wait -WindowStyle Hidden
$exportOutput = if (Test-Path -LiteralPath $exportOutputLog) { Get-Content -LiteralPath $exportOutputLog -Raw } else { '' }
$exportError = if (Test-Path -LiteralPath $exportErrorLog) { Get-Content -LiteralPath $exportErrorLog -Raw } else { '' }
if (-not [string]::IsNullOrWhiteSpace($exportOutput)) { Write-Output $exportOutput.TrimEnd() }
if (-not [string]::IsNullOrWhiteSpace($exportError)) { Write-Output $exportError.TrimEnd() }
Remove-Item -LiteralPath $exportOutputLog,$exportErrorLog -Force -ErrorAction SilentlyContinue
if ($exportProcess.ExitCode -ne 0) {
    throw "Godot export failed with exit code $($exportProcess.ExitCode)."
}
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Export did not produce $executablePath."
}

$exportedWebRtc = Get-ChildItem -LiteralPath $windowsDirectory -Recurse -File |
    Where-Object { $_.Name -eq 'libwebrtc_native.windows.template_release.x86_64.dll' } |
    Select-Object -First 1
if ($null -eq $exportedWebRtc) {
    throw 'Export is missing the native WebRTC Windows x64 release library.'
}

if (-not $SkipSmoke) {
    if (Test-Path -LiteralPath $markerPath) {
        Remove-Item -LiteralPath $markerPath -Force
    }
    $smokeArgument = '--startup-smoke="' + $markerPath + '"'
    $process = Start-Process -FilePath $executablePath -ArgumentList @('--headless', '--', $smokeArgument) -PassThru -Wait -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "Exported game startup smoke test failed with exit code $($process.ExitCode)."
    }
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
        throw 'Exported game did not write its startup smoke marker.'
    }
    $marker = Get-Content -LiteralPath $markerPath -Raw
    if ($marker -notmatch 'startup_ok' -or $marker -notmatch 'webrtc_ok') {
        throw "Startup marker did not confirm the app and WebRTC extension: $marker"
    }
    Remove-Item -LiteralPath $markerPath -Force
}

Compress-Archive -Path (Join-Path $windowsDirectory '*') -DestinationPath $zipPath -CompressionLevel Optimal
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "ZIP creation failed: $zipPath"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    foreach ($requiredName in @('Shift.exe', 'Shift.pck')) {
        if ($entryNames -notcontains $requiredName) {
            throw "Windows ZIP is missing $requiredName."
        }
    }
    if (-not ($entryNames | Where-Object { $_ -like '*libwebrtc_native.windows.template_release.x86_64.dll' })) {
        throw 'Windows ZIP is missing the native WebRTC release DLL.'
    }
} finally {
    $archive.Dispose()
}

Write-Output "export_ok folder=$windowsDirectory zip=$zipPath"
