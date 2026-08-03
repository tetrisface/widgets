[CmdletBinding(SupportsShouldProcess)]
param()

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$communityCandidates = @(
    Join-Path $repositoryRoot 'BAR-Widgets/Widgets/tetrisface',
    Join-Path $repositoryRoot 'community-widgets'
)
$communityWidgetsRoot = $communityCandidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
    Select-Object -First 1

if (-not $communityWidgetsRoot) {
    throw "Community widgets checkout not found. Checked: $($communityCandidates -join ', ')"
}

$widgetDirectories = Get-ChildItem -LiteralPath $communityWidgetsRoot -Directory |
    Where-Object {
        $manifestPath = Join-Path $_.FullName 'manifest.json'
        $entrypointPath = Join-Path $_.FullName ($_.Name + '.lua')
        (Test-Path -LiteralPath $manifestPath -PathType Leaf) -and
            (Test-Path -LiteralPath $entrypointPath -PathType Leaf)
    } |
    Sort-Object Name

$linkExclusionPatterns = [System.Collections.Generic.List[string]]::new()

foreach ($widgetDirectory in $widgetDirectories) {
    $widgetName = $widgetDirectory.Name
    # This widget is managed in widgets-extra (widgets-extra/gui_pve_stats) and must not be linked from community-widgets.
    if ($widgetName -eq 'gui_pve_stats') {
        Write-Output "Skipping managed widget from sync: $widgetName"
        continue
    }
    $sourcePath = $widgetDirectory.FullName
    $linkPath = Join-Path (Join-Path $repositoryRoot 'Widgets') $widgetName
	$linkExclusionPatterns.Add("/Widgets/$widgetName/")

    $existingItem = Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
    if ($null -ne $existingItem -and $null -eq $existingItem.LinkType) {
        throw "Refusing to replace a non-link path: $linkPath"
    }

    $resolvedSourcePath = (Resolve-Path -LiteralPath $sourcePath).Path
    $currentTarget = if ($null -eq $existingItem) { $null } else { $existingItem.Target -join ';' }
    if ($currentTarget -eq $resolvedSourcePath) {
        Write-Output "Link already current: $linkPath"
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($linkPath, "Point junction to $resolvedSourcePath")) {
        continue
    }

    if ($null -ne $existingItem) {
        Remove-Item -LiteralPath $linkPath -Force
    }

    $null = New-Item -ItemType Junction -Path $linkPath -Target $resolvedSourcePath
    Write-Output "Linked $linkPath -> $resolvedSourcePath"
}

$gitExcludeOutput = & git -C $repositoryRoot rev-parse --git-path info/exclude
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitExcludeOutput)) {
    throw 'Unable to locate the repository-local Git exclude file.'
}

$gitExcludePath = $gitExcludeOutput.Trim()
if (-not [System.IO.Path]::IsPathRooted($gitExcludePath)) {
    $gitExcludePath = Join-Path $repositoryRoot $gitExcludePath
}

$existingExcludeContent = if (Test-Path -LiteralPath $gitExcludePath -PathType Leaf) {
    [System.IO.File]::ReadAllText($gitExcludePath)
} else {
    ''
}
$existingExcludeLines = @($existingExcludeContent -split '\r?\n')
$missingPatterns = @($linkExclusionPatterns | Where-Object { $_ -notin $existingExcludeLines })

if ($missingPatterns.Count -gt 0 -and $PSCmdlet.ShouldProcess($gitExcludePath, 'Add community-widget link exclusions')) {
    $excludeDirectory = Split-Path $gitExcludePath -Parent
    if (-not (Test-Path -LiteralPath $excludeDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $excludeDirectory
    }
    $prefix = if ($existingExcludeContent.Length -eq 0 -or $existingExcludeContent.EndsWith([Environment]::NewLine)) {
        ''
    } else {
        [Environment]::NewLine
    }
    $addition = $prefix + ($missingPatterns -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::AppendAllText($gitExcludePath, $addition)
    foreach ($pattern in $missingPatterns) { Write-Output "Excluded local widget link from Git status: $pattern" }
}
