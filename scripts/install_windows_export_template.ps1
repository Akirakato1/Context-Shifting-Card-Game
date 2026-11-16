param(
    [string]$Version = '4.7.2',
    [string]$Status = 'stable'
)

$ErrorActionPreference = 'Stop'
$templateVersion = "$Version.$Status"
$requiredTemplateVersion = '4.7.2.stable'
$requiredTemplateSha256 = 'D34D36F3BE1A6C49C56525AE86469B92E4F417DDF0B43CF00DD80C385C4B0562'
if ($templateVersion -ne $requiredTemplateVersion) {
    throw "This installer is pinned to $requiredTemplateVersion; requested $templateVersion."
}
$fileName = 'windows_release_x86_64.exe'
$archiveUrl = "https://godot-releases.nbg1.your-objectstorage.com/$Version-$Status/Godot_v$Version-$Status`_export_templates.tpz"
$targetDirectory = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion"
$targetPath = Join-Path $targetDirectory $fileName
$temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
$temporaryDirectory = [System.IO.Path]::GetFullPath((Join-Path $temporaryRoot ('shift-godot-template-' + [guid]::NewGuid().ToString('N'))))
$verifiedTemplatePath = Join-Path $temporaryDirectory $fileName
$temporaryPrefix = $temporaryRoot + [System.IO.Path]::DirectorySeparatorChar
if (-not $temporaryDirectory.StartsWith($temporaryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Temporary path escaped the system temp directory: $temporaryDirectory"
}

function Invoke-RangeDownload([long]$Start, [long]$End, [string]$Destination) {
    & curl.exe --fail --location --silent --show-error --http1.1 --retry 5 --retry-all-errors --range "$Start-$End" --output $Destination $archiveUrl
    if ($LASTEXITCODE -ne 0) {
        throw "Range download failed for bytes $Start-$End with exit code $LASTEXITCODE."
    }
}

function Find-SignatureBackwards([byte[]]$Bytes, [byte[]]$Signature) {
    for ($index = $Bytes.Length - $Signature.Length; $index -ge 0; $index--) {
        $matches = $true
        for ($offset = 0; $offset -lt $Signature.Length; $offset++) {
            if ($Bytes[$index + $offset] -ne $Signature[$offset]) {
                $matches = $false
                break
            }
        }
        if ($matches) {
            return $index
        }
    }
    return -1
}

New-Item -ItemType Directory -Force -Path $temporaryDirectory | Out-Null
try {
    $headers = & curl.exe --fail --silent --show-error --http1.1 --retry 5 --retry-all-errors --head $archiveUrl
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to query the official Godot template archive (curl exit $LASTEXITCODE)."
    }
    $lengthMatch = [regex]::Match(($headers -join "`n"), '(?im)^content-length:\s*(\d+)')
    if (-not $lengthMatch.Success) {
        throw 'The official Godot template archive did not report a content length.'
    }
    $archiveLength = [long]$lengthMatch.Groups[1].Value
    $tailLength = [Math]::Min(65536L, $archiveLength)
    $tailPath = Join-Path $temporaryDirectory 'tail.bin'
    Invoke-RangeDownload ($archiveLength - $tailLength) ($archiveLength - 1) $tailPath
    [byte[]]$tail = [System.IO.File]::ReadAllBytes($tailPath)
    $endIndex = Find-SignatureBackwards $tail ([byte[]](0x50, 0x4b, 0x05, 0x06))
    if ($endIndex -lt 0) {
        throw 'Could not find the ZIP end-of-central-directory record.'
    }
    $centralSize = [long][BitConverter]::ToUInt32($tail, $endIndex + 12)
    $centralOffset = [long][BitConverter]::ToUInt32($tail, $endIndex + 16)
    $centralPath = Join-Path $temporaryDirectory 'central.bin'
    Invoke-RangeDownload $centralOffset ($centralOffset + $centralSize - 1) $centralPath
    [byte[]]$central = [System.IO.File]::ReadAllBytes($centralPath)

    $entryOffset = 0
    $entry = $null
    while ($entryOffset + 46 -le $central.Length) {
        if ([BitConverter]::ToUInt32($central, $entryOffset) -ne 0x02014b50) {
            throw "Invalid ZIP central-directory record at offset $entryOffset."
        }
        $nameLength = [BitConverter]::ToUInt16($central, $entryOffset + 28)
        $extraLength = [BitConverter]::ToUInt16($central, $entryOffset + 30)
        $commentLength = [BitConverter]::ToUInt16($central, $entryOffset + 32)
        $recordLength = 46 + $nameLength + $extraLength + $commentLength
        $entryName = [Text.Encoding]::UTF8.GetString($central, $entryOffset + 46, $nameLength)
        if ($entryName.Replace('\', '/').EndsWith("/$fileName") -or $entryName -eq $fileName) {
            $entry = @{
                Name = $entryName
                Offset = [long][BitConverter]::ToUInt32($central, $entryOffset + 42)
                CompressedSize = [long][BitConverter]::ToUInt32($central, $entryOffset + 20)
                UncompressedSize = [long][BitConverter]::ToUInt32($central, $entryOffset + 24)
                RecordOffset = $entryOffset
                RecordLength = $recordLength
            }
            break
        }
        $entryOffset += $recordLength
    }
    if ($null -eq $entry) {
        throw "$fileName was not found in the official export-template archive."
    }

    $localHeaderPath = Join-Path $temporaryDirectory 'local-header.bin'
    Invoke-RangeDownload $entry.Offset ($entry.Offset + 29) $localHeaderPath
    [byte[]]$localHeader = [System.IO.File]::ReadAllBytes($localHeaderPath)
    if ([BitConverter]::ToUInt32($localHeader, 0) -ne 0x04034b50) {
        throw 'Invalid ZIP local-file header.'
    }
    $localNameLength = [BitConverter]::ToUInt16($localHeader, 26)
    $localExtraLength = [BitConverter]::ToUInt16($localHeader, 28)
    $fragmentLength = 30L + $localNameLength + $localExtraLength + $entry.CompressedSize
    $fragmentPath = Join-Path $temporaryDirectory 'entry-fragment.bin'
    Write-Output "Downloading the $fileName template fragment ($([Math]::Round($fragmentLength / 1MB, 1)) MB)..."
    Invoke-RangeDownload $entry.Offset ($entry.Offset + $fragmentLength - 1) $fragmentPath
    [byte[]]$fragment = [System.IO.File]::ReadAllBytes($fragmentPath)

    [byte[]]$centralRecord = New-Object byte[] $entry.RecordLength
    [Array]::Copy($central, $entry.RecordOffset, $centralRecord, 0, $entry.RecordLength)
    [Array]::Clear($centralRecord, 42, 4)
    [byte[]]$endRecord = New-Object byte[] 22
    [Array]::Copy([BitConverter]::GetBytes([uint32]0x06054b50), 0, $endRecord, 0, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint16]1), 0, $endRecord, 8, 2)
    [Array]::Copy([BitConverter]::GetBytes([uint16]1), 0, $endRecord, 10, 2)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$centralRecord.Length), 0, $endRecord, 12, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$fragment.Length), 0, $endRecord, 16, 4)
    [byte[]]$miniZip = New-Object byte[] ($fragment.Length + $centralRecord.Length + $endRecord.Length)
    [Array]::Copy($fragment, 0, $miniZip, 0, $fragment.Length)
    [Array]::Copy($centralRecord, 0, $miniZip, $fragment.Length, $centralRecord.Length)
    [Array]::Copy($endRecord, 0, $miniZip, $fragment.Length + $centralRecord.Length, $endRecord.Length)
    $miniZipPath = Join-Path $temporaryDirectory 'template.zip'
    [System.IO.File]::WriteAllBytes($miniZipPath, $miniZip)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($miniZipPath)
    try {
        $zipEntry = $archive.Entries | Select-Object -First 1
        if ($null -eq $zipEntry -or $zipEntry.FullName -ne $entry.Name) {
            throw 'The reconstructed template archive did not contain the expected entry.'
        }
        $inputStream = $zipEntry.Open()
        $outputStream = [System.IO.File]::Create($verifiedTemplatePath)
        try {
            $inputStream.CopyTo($outputStream)
        } finally {
            $outputStream.Dispose()
            $inputStream.Dispose()
        }
    } finally {
        $archive.Dispose()
    }
    if ((Get-Item -LiteralPath $verifiedTemplatePath).Length -ne $entry.UncompressedSize) {
        throw "Extracted template size mismatch for $verifiedTemplatePath."
    }
    $templateHash = (Get-FileHash -LiteralPath $verifiedTemplatePath -Algorithm SHA256).Hash
    if ($templateHash -ne $requiredTemplateSha256) {
        throw "Downloaded template hash mismatch. Expected $requiredTemplateSha256, found $templateHash."
    }
    New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
    Move-Item -LiteralPath $verifiedTemplatePath -Destination $targetPath -Force
    Set-Content -LiteralPath (Join-Path $targetDirectory 'version.txt') -Value $templateVersion -NoNewline
    Write-Output "installed_ok template=$targetPath sha256=$templateHash"
} finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        $resolvedTemporary = [System.IO.Path]::GetFullPath($temporaryDirectory)
        if ($resolvedTemporary.StartsWith($temporaryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
        }
    }
}
