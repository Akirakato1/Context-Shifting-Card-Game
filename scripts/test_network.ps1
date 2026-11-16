param(
    [string]$GodotBin = $env:SHIFT_GODOT_BIN,
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $projectRoot 'tests\network\fixtures'
$requiredFixtures = @(
    (Join-Path $fixtureRoot 'signaling_runner.mjs'),
    (Join-Path $fixtureRoot 'host_runner.gd'),
    (Join-Path $fixtureRoot 'client_runner.gd')
)

foreach ($fixture in $requiredFixtures) {
    if (-not (Test-Path -LiteralPath $fixture)) {
        Write-Error "Missing network integration fixture: $fixture"
    }
}

if ([string]::IsNullOrWhiteSpace($GodotBin)) {
    $godotCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -ne $godotCommand) {
        $GodotBin = $godotCommand.Source
    }
}
if ([string]::IsNullOrWhiteSpace($GodotBin) -or -not (Test-Path -LiteralPath $GodotBin)) {
    Write-Error 'Godot was not found. Set SHIFT_GODOT_BIN or pass -GodotBin.'
}
if ($null -eq (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error 'Node.js was not found on PATH.'
}

$runRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'shift-network-tests\' + [Guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$stopFile = Join-Path $runRoot 'stop'
$script:Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$processes = [System.Collections.Generic.List[object]]::new()

function Quote-ProcessArgument([string]$Value) {
    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-LoggedProcess {
    param(
        [string]$FilePath,
        [string[]]$ProcessArguments,
        [string]$Name,
        [string]$ExitMarker = ''
    )
    $stdoutPath = Join-Path $runRoot ($Name + '.stdout.log')
    $stderrPath = Join-Path $runRoot ($Name + '.stderr.log')
    $argumentLine = ($ProcessArguments | ForEach-Object {
        Quote-ProcessArgument $_
    }) -join ' '
    $process = Start-Process -FilePath $FilePath `
        -ArgumentList $argumentLine `
        -WorkingDirectory $projectRoot `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -WindowStyle Hidden `
        -PassThru
    $record = [pscustomobject]@{
        Name = $Name
        Process = $process
        Stdout = $stdoutPath
        Stderr = $stderrPath
        ExitMarker = $ExitMarker
    }
    $processes.Add($record)
    return $record
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Wait-Until {
    param(
        [scriptblock]$Condition,
        [string]$Description
    )
    while ([DateTime]::UtcNow -lt $script:Deadline) {
        if (& $Condition) {
            return
        }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for $Description"
}

function Wait-Status {
    param(
        [string]$Path,
        [scriptblock]$Condition,
        [string]$Description,
        [object]$ProcessRecord = $null
    )
    while ([DateTime]::UtcNow -lt $script:Deadline) {
        if ($null -ne $ProcessRecord) {
            $ProcessRecord.Process.Refresh()
            if ($ProcessRecord.Process.HasExited) {
                throw ("{0} exited before {1}" -f $ProcessRecord.Name, $Description)
            }
        }
        $status = Read-JsonFile $Path
        if ($null -ne $status -and (& $Condition $status)) {
            return $status
        }
        Start-Sleep -Milliseconds 50
    }
    throw "Timed out waiting for $Description"
}

function Start-GodotRunner {
    param(
        [string]$ScriptPath,
        [string[]]$UserArguments,
        [string]$Name
    )
    $exitMarker = Join-Path $runRoot ($Name + '.exit')
    $arguments = @(
        '--headless',
        '--path', $projectRoot,
        '--script', $ScriptPath,
        '--'
    ) + $UserArguments + @('--exit-marker', $exitMarker)
    return Start-LoggedProcess -FilePath $GodotBin `
        -ProcessArguments $arguments -Name $Name -ExitMarker $exitMarker
}

function Start-Client {
    param(
        [string]$PlayerId,
        [string]$Role,
        [string]$Mode,
        [string]$Instance,
        [string]$SignalingUrl,
        [string]$RoomCode
    )
    return Start-GodotRunner `
        -ScriptPath 'res://tests/network/fixtures/client_runner.gd' `
        -Name ("client-$PlayerId-$Instance") `
        -UserArguments @(
            '--signaling-url', $SignalingUrl,
            '--room-code', $RoomCode,
            '--player-id', $PlayerId,
            '--role', $Role,
            '--mode', $Mode,
            '--output-dir', $runRoot
        )
}

function Wait-CleanExit($Record) {
    Wait-Until -Description ("{0} clean exit" -f $Record.Name) -Condition {
        $Record.Process.Refresh()
        return $Record.Process.HasExited
    }
    $Record.Process.WaitForExit()
    $Record.Process.Refresh()
    $exitCode = $Record.Process.ExitCode
    $markerCode = $null
    if (-not [string]::IsNullOrWhiteSpace($Record.ExitMarker) -and `
        (Test-Path -LiteralPath $Record.ExitMarker)) {
        $markerCode = [int](Get-Content -LiteralPath $Record.ExitMarker -Raw)
    }
    if (($null -ne $exitCode -and $exitCode -ne 0) -or $markerCode -ne 0) {
        throw ("{0} exited with process code {1}, marker code {2}" -f `
            $Record.Name, $exitCode, $markerCode)
    }
}

function Show-Logs {
    foreach ($record in $processes) {
        Write-Output ("--- {0} stdout ---" -f $record.Name)
        if (Test-Path -LiteralPath $record.Stdout) {
            Get-Content -LiteralPath $record.Stdout -Tail 200
        }
        Write-Output ("--- {0} stderr ---" -f $record.Name)
        if (Test-Path -LiteralPath $record.Stderr) {
            Get-Content -LiteralPath $record.Stderr -Tail 200
        }
    }
}

$failure = $null
try {
    $signalingExitMarker = Join-Path $runRoot 'signaling.exit'
    $signaling = Start-LoggedProcess -FilePath 'node' -Name 'signaling' `
        -ExitMarker $signalingExitMarker -ProcessArguments @(
        (Join-Path $fixtureRoot 'signaling_runner.mjs'),
        '--output-dir', $runRoot,
        '--stop-file', $stopFile,
        '--exit-marker', $signalingExitMarker
    )
    $signalingStatusPath = Join-Path $runRoot 'signaling.json'
    $signalingStatus = Wait-Status -Path $signalingStatusPath `
        -Description 'signaling server readiness' `
        -ProcessRecord $signaling `
        -Condition { param($status) $status.state -eq 'ready' }

    $hostRecord = Start-GodotRunner `
        -ScriptPath 'res://tests/network/fixtures/host_runner.gd' `
        -Name 'host' `
        -UserArguments @(
            '--signaling-url', $signalingStatus.url,
            '--output-dir', $runRoot
        )
    $hostStatusPath = Join-Path $runRoot 'host.json'
    $hostStatus = Wait-Status -Path $hostStatusPath `
        -Description 'host lobby code' `
        -ProcessRecord $hostRecord `
        -Condition { param($status) $status.state -eq 'room_ready' }
    $roomCode = $hostStatus.room_code

    $clientRecords = @()
    foreach ($participant in @(
        @{ Id = 'player-2'; Role = 'active' },
        @{ Id = 'player-3'; Role = 'active' },
        @{ Id = 'player-4'; Role = 'active' },
        @{ Id = 'spectator'; Role = 'spectator' }
    )) {
        $record = Start-Client -PlayerId $participant.Id -Role $participant.Role `
            -Mode 'join' -Instance 'initial' `
            -SignalingUrl $signalingStatus.url -RoomCode $roomCode
        $clientRecords += $record
        $statusPath = Join-Path $runRoot ("client-{0}.json" -f $participant.Id)
        Wait-Status -Path $statusPath `
            -Description ("{0} direct connection and snapshot" -f $participant.Id) `
            -ProcessRecord $record `
            -Condition { param($status) $status.state -eq 'ready' } | Out-Null
    }

    $triggerPath = Join-Path $runRoot 'submit-player-2'
    New-Item -ItemType File -Force -Path $triggerPath | Out-Null
    $playerTwoStatusPath = Join-Path $runRoot 'client-player-2.json'
    Wait-Status -Path $playerTwoStatusPath `
        -Description 'authoritative command result' `
        -Condition { param($status) $status.command_accepted -eq $true } | Out-Null
    $spectatorStatusPath = Join-Path $runRoot 'client-spectator.json'
    $spectatorStatus = Wait-Status -Path $spectatorStatusPath `
        -Description 'spectator public event projection' `
        -Condition { param($status) $status.saw_ready_event -eq $true }
    if ($spectatorStatus.private_leak -eq $true) {
        throw 'Spectator received owner-private snapshot data.'
    }
    $hostStatus = Wait-Status -Path $hostStatusPath `
        -Description 'host direct gameplay receipt' `
        -Condition { param($status) $status.direct_gameplay_messages -ge 1 }

    New-Item -ItemType File -Force -Path (Join-Path $runRoot 'disconnect-player-2') | Out-Null
    Wait-CleanExit $clientRecords[0]
    Wait-Status -Path $hostStatusPath `
        -Description 'host disconnect grace state' `
        -Condition {
            param($status)
            $status.player_2_connected -eq $false -and $status.frozen -eq $true
        } | Out-Null

    Remove-Item -LiteralPath $playerTwoStatusPath -Force
    $reconnectedClient = Start-Client -PlayerId 'player-2' -Role 'active' `
        -Mode 'reconnect' -Instance 'reconnect' `
        -SignalingUrl $signalingStatus.url -RoomCode $roomCode
    $clientRecords += $reconnectedClient
    Wait-Status -Path $playerTwoStatusPath `
        -Description 'player relaunch reconnect snapshot' `
        -Condition { param($status) $status.state -eq 'reconnected' } | Out-Null
    Wait-Status -Path $hostStatusPath `
        -Description 'host resumed after reconnect' `
        -Condition {
            param($status)
            $status.player_2_connected -eq $true -and $status.frozen -eq $false `
                -and $status.reconnects -ge 1
        } | Out-Null

    $hostLog = Get-Content -LiteralPath $hostRecord.Stdout -Raw
    $spectatorLog = Get-Content -LiteralPath $clientRecords[3].Stdout -Raw
    if ($hostLog -notmatch 'DIRECT_GAMEPLAY_RECEIVED.*kind=command') {
        throw 'Host log did not prove a direct gameplay command envelope.'
    }
    if ($spectatorLog -notmatch 'DIRECT_GAMEPLAY_EVENT.*phase_changed') {
        throw 'Spectator log did not prove a direct public gameplay event.'
    }

    New-Item -ItemType File -Force -Path $stopFile | Out-Null
    foreach ($record in $clientRecords[1..($clientRecords.Count - 1)]) {
        Wait-CleanExit $record
    }
    Wait-CleanExit $hostRecord
    Wait-CleanExit $signaling

    Write-Output 'PASS: join-code flow connected host + three remote players + spectator.'
    Write-Output 'PASS: command/result and spectator-safe event traveled over direct WebRTC.'
    Write-Output 'PASS: relaunched player reclaimed its seat and all processes shut down cleanly.'
    Write-Output "NETWORK TEST LOGS: $runRoot"
}
catch {
    $failure = $_
}
finally {
    foreach ($record in $processes) {
        $record.Process.Refresh()
        if (-not $record.Process.HasExited) {
            Stop-Process -Id $record.Process.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($null -ne $failure) {
    Show-Logs
    Write-Error ("Network integration failed: {0}. Logs: {1}" -f $failure, $runRoot)
}

exit 0
