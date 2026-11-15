param(
	[string]$DestinationRoot = '',
	[string]$ArchivePath = '',
	[switch]$AllPlatforms
)

$ErrorActionPreference = 'Stop'
$releaseUri = 'https://github.com/godotengine/webrtc-native/releases/download/1.2.2-stable/godot-extension-webrtc_native.zip'
$expectedSha256 = '98E9446921740D995BD9CA1BE48798DC3C2CEED51E044A25CE18B3CFF11F56E5'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
	$DestinationRoot = $projectRoot
}

$destinationFull = [System.IO.Path]::GetFullPath($DestinationRoot)
New-Item -ItemType Directory -Force -Path $destinationFull | Out-Null
$temporaryArchive = $false
if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
	$ArchivePath = Join-Path ([System.IO.Path]::GetTempPath()) (
		'shift-webrtc-' + [System.IO.Path]::GetRandomFileName() + '.zip'
	)
	$temporaryArchive = $true
	Write-Output "Downloading official WebRTC v1.2.2 archive..."
	Invoke-WebRequest -UseBasicParsing -Uri $releaseUri -OutFile $ArchivePath
}

try {
	$actualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ArchivePath).Hash.ToUpperInvariant()
	if ($actualSha256 -ne $expectedSha256) {
		throw "WebRTC archive SHA-256 mismatch. Expected $expectedSha256, got $actualSha256."
	}

	Add-Type -AssemblyName System.IO.Compression.FileSystem
	$archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ArchivePath))
	try {
		$extracted = 0
		foreach ($entry in $archive.Entries) {
			if ([string]::IsNullOrEmpty($entry.Name)) {
				continue
			}
			$path = $entry.FullName
			$isRequiredWindowsFile = (
				$path -eq 'addons/webrtc_native/webrtc_native.gdextension' -or
				$path -like 'addons/webrtc_native/LICENSE.*' -or
				$path -match '^addons/webrtc_native/lib/libwebrtc_native\.windows\.template_(debug|release)\.x86_64\.dll$'
			)
			if (-not $AllPlatforms -and -not $isRequiredWindowsFile) {
				continue
			}
			if ($AllPlatforms -and -not $path.StartsWith('addons/webrtc_native/')) {
				continue
			}

			$relativePath = $path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
			$targetPath = [System.IO.Path]::GetFullPath((Join-Path $destinationFull $relativePath))
			$destinationPrefix = $destinationFull.TrimEnd(
				[System.IO.Path]::DirectorySeparatorChar,
				[System.IO.Path]::AltDirectorySeparatorChar
			) + [System.IO.Path]::DirectorySeparatorChar
			if (-not $targetPath.StartsWith($destinationPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
				throw "Archive entry escapes destination: $path"
			}

			$targetDirectory = Split-Path -Parent $targetPath
			New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
			$inputStream = $entry.Open()
			$outputStream = [System.IO.File]::Create($targetPath)
			try {
				$inputStream.CopyTo($outputStream)
			} finally {
				$outputStream.Dispose()
				$inputStream.Dispose()
			}
			$extracted += 1
		}
	} finally {
		$archive.Dispose()
	}

	$manifest = Join-Path $destinationFull 'addons\webrtc_native\webrtc_native.gdextension'
	$debugLibrary = Join-Path $destinationFull 'addons\webrtc_native\lib\libwebrtc_native.windows.template_debug.x86_64.dll'
	$releaseLibrary = Join-Path $destinationFull 'addons\webrtc_native\lib\libwebrtc_native.windows.template_release.x86_64.dll'
	foreach ($requiredPath in @($manifest, $debugLibrary, $releaseLibrary)) {
		if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
			throw "Required WebRTC file was not extracted: $requiredPath"
		}
	}
	Write-Output "Installed $extracted verified WebRTC v1.2.2 files for Windows x64."
} finally {
	if ($temporaryArchive -and (Test-Path -LiteralPath $ArchivePath)) {
		Remove-Item -LiteralPath $ArchivePath -Force
	}
}
