<#
.SYNOPSIS
    Make every Recoil/BAR engine write dir on this machine load this repo's uikeys.txt.

.DESCRIPTION
    BAR's "BAR Hotkeys" widget runs `keyreload <KeybindingFile>` at LuaUI init: it wipes
    all bindings and loads exactly one file. uikeys.txt is therefore only honoured when
      1. springsettings.cfg in the write dir says  KeybindingFile = uikeys.txt   and
      2. uikeys.txt exists in that write dir (here: a symlink to the repo file).
    Both are lost whenever a launcher creates a fresh write dir or regenerates
    springsettings.cfg. This script re-asserts both, idempotently, for every write dir
    it can find: known install paths, the --write-dir of any running engine, and any
    springsettings.cfg with an infolog.txt next to it under a few roots.

    Editing springsettings.cfg while an engine runs is safe: Recoil re-reads the file
    before each of its own writes (read-modify-write under a lock). The engine picks the
    value up on its next start, or immediately via Settings > Control > Keybindings > Custom.

.PARAMETER DataDir
    Extra write dirs to repair, in addition to the discovered ones.
.PARAMETER DryRun
    Report what would change without touching anything.
.PARAMETER Register
    Create a per-user scheduled task that runs this script at logon and every 30 minutes.
.PARAMETER Unregister
    Remove that scheduled task.

.EXAMPLE
    make keybinds                               # repair now
    make preview-keybinds                       # only report
    .\scripts\Repair-BarKeybinds.ps1 -Register  # keep it repaired automatically
#>
[CmdletBinding()]
param(
    [string[]]$DataDir = @(),
    [switch]$DryRun,
    [switch]$Register,
    [switch]$Unregister
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = 'Repair-BarKeybinds'
$RepositoryRoot = Split-Path $PSScriptRoot -Parent
$UiKeys = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'uikeys.txt'))
$CfgLine = 'KeybindingFile = uikeys.txt'

function Get-RunningEngines {
    Get-CimInstance Win32_Process -Filter "Name LIKE 'spring%.exe'" -ErrorAction SilentlyContinue
}

function Get-EngineWriteDir($process) {
    if ($process.CommandLine -match '--write-dir\s+(?:"([^"]+)"|(\S+))') {
        if ($Matches[1]) { return $Matches[1] }
        return $Matches[2]
    }
}

function Find-WriteDirs {
    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($d in $DataDir) { $dirs.Add($d) }
    $dirs.Add((Join-Path $env:LOCALAPPDATA 'Programs\Beyond-All-Reason\data'))
    $dirs.Add((Join-Path $env:APPDATA 'BeyondAllReason\data'))

    foreach ($p in Get-RunningEngines) {
        $wd = Get-EngineWriteDir $p
        if ($wd) { $dirs.Add($wd) }
    }

    # An engine has run wherever springsettings.cfg sits next to an infolog.txt.
    foreach ($root in @((Join-Path $env:LOCALAPPDATA 'Programs'), $env:APPDATA, (Join-Path $HOME 'git'))) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Recurse -Depth 4 -Filter 'springsettings.cfg' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\node_modules\\' -and (Test-Path -LiteralPath (Join-Path $_.DirectoryName 'infolog.txt')) } |
            ForEach-Object { $dirs.Add($_.DirectoryName) }
    }

    $dirs |
        Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
        ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') } |
        Sort-Object -Unique
}

function Resolve-LinkTarget($item) {
    $target = @($item.Target)[0]
    if (-not $target) { return $null }
    if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path $item.DirectoryName $target }
    return [IO.Path]::GetFullPath($target)
}

function Repair-UiKeysLink([string]$dir) {
    $link = Join-Path $dir 'uikeys.txt'
    $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue

    if ($item) {
        if ($item.LinkType -eq 'SymbolicLink' -and (Resolve-LinkTarget $item) -ieq $UiKeys) { return 'ok' }
        $isForeignFile = (-not $item.LinkType) -and
            ((Get-FileHash -LiteralPath $link).Hash -ne (Get-FileHash -LiteralPath $UiKeys).Hash)
        if ($isForeignFile) {
            $backup = '{0}.bak-{1}' -f $link, (Get-Date -Format 'yyyyMMdd-HHmmss')
            if (-not $DryRun) { Move-Item -LiteralPath $link -Destination $backup }
            Write-Verbose "backed up foreign uikeys.txt to $backup"
        } elseif (-not $DryRun) {
            Remove-Item -LiteralPath $link -Force
        }
    }

    if ($DryRun) { return 'would link' }
    try {
        New-Item -ItemType SymbolicLink -Path $link -Target $UiKeys -ErrorAction Stop | Out-Null
        return 'linked'
    } catch {
        Copy-Item -LiteralPath $UiKeys -Destination $link
        return 'copied (symlink denied - enable Developer Mode so edits go live without re-running)'
    }
}

function Repair-Cfg([string]$dir) {
    $cfg = Join-Path $dir 'springsettings.cfg'
    $text = ''
    if (Test-Path -LiteralPath $cfg) { $text = [IO.File]::ReadAllText($cfg) }

    if ($text -match '(?m)^KeybindingFile\s*=\s*uikeys\.txt\s*$') { return 'ok' }

    $nl = "`n"
    if ($text -match "`r`n") { $nl = "`r`n" }

    if ($text -match '(?m)^KeybindingFile\s*=[^\r\n]*') {
        $new = [regex]::Replace($text, '(?m)^KeybindingFile\s*=[^\r\n]*', $CfgLine)
        $status = 'value replaced'
    } else {
        if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += $nl }
        $new = $text + $CfgLine + $nl
        $status = 'key added'
    }

    if ($DryRun) { return "would fix ($status)" }
    [IO.File]::WriteAllText($cfg, $new, (New-Object Text.UTF8Encoding $false))
    return $status
}

function Get-LastLoadedHotkeys([string]$dir) {
    $log = Join-Path $dir 'infolog.txt'
    if (-not (Test-Path -LiteralPath $log)) { return '(no infolog)' }
    $hit = Select-String -LiteralPath $log -Pattern 'BAR Hotkeys: Loaded hotkeys from (\S+)' | Select-Object -Last 1
    if ($hit) { return $hit.Matches[0].Groups[1].Value }
    return '(no BAR Hotkeys line in infolog)'
}

function Register-RepairTask {
    $shell = (Get-Process -Id $PID).Path
    $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $action = New-ScheduledTaskAction -Execute $shell -Argument $arguments
    $triggers = @(
        (New-ScheduledTaskTrigger -AtLogOn -User $user),
        (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30))
    )
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Force | Out-Null
    "Registered scheduled task '$TaskName': at logon and every 30 min -> $PSCommandPath"
}

if (-not (Test-Path -LiteralPath $UiKeys)) { throw "uikeys.txt not found at repository root: $UiKeys" }

if ($Register) { Register-RepairTask; return }
if ($Unregister) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    "Removed scheduled task '$TaskName'"
    return
}

$runningDirs = @(Get-RunningEngines | ForEach-Object { Get-EngineWriteDir $_ } | Where-Object { $_ } |
    ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })

foreach ($dir in Find-WriteDirs) {
    $linkStatus = Repair-UiKeysLink $dir
    $cfgStatus = Repair-Cfg $dir
    $changed = ($linkStatus -ne 'ok') -or ($cfgStatus -ne 'ok')

    $dir
    "  uikeys.txt      : $linkStatus"
    "  KeybindingFile  : $cfgStatus"
    "  last engine run : loaded $(Get-LastLoadedHotkeys $dir)"
    if ($changed -and ($runningDirs -contains $dir)) {
        "  note            : engine running here - applies on next start, or pick Settings > Control > Keybindings > Custom now"
    }
}
