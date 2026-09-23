[CmdletBinding(SupportsShouldProcess)]
param()

$repositoryRoot = Split-Path $PSScriptRoot -Parent
# Only the direct submodules are valid sources. The nested copy at
# BAR-Widgets/Widgets/tetrisface is pinned to whatever upstream recorded, so any
# `git submodule update` in BAR-Widgets silently reverts it and the linked widgets
# disappear from the game mid-session.
# Ordered by precedence: when both hold a widget, the community-widgets copy is linked.
$sourceRoots = @('community-widgets', 'widgets-extra') | ForEach-Object { Join-Path $repositoryRoot $_ }
$missingRoots = @($sourceRoots | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Container) })
if ($missingRoots.Count -gt 0) {
    throw "Widget source checkout not found: $($missingRoots -join ', ')"
}

$widgetDirectories = $sourceRoots |
    ForEach-Object { Get-ChildItem -LiteralPath $_ -Directory } |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName ($_.Name + '.lua')) -PathType Leaf } |
    Group-Object Name |
    ForEach-Object {
        if ($_.Count -gt 1) {
            Write-Warning "Duplicate widget $($_.Name): linking $($_.Group[0].FullName), ignoring $(@($_.Group | Select-Object -Skip 1).FullName -join ', ')"
        }
        $_.Group[0]
    } |
    Sort-Object Name

$linkExclusionPatterns = [System.Collections.Generic.List[string]]::new()

foreach ($widgetDirectory in $widgetDirectories) {
    $widgetName = $widgetDirectory.Name
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

# A junction whose target vanished (e.g. a branch switch in community-widgets dropped the widget
# directory) makes the engine's directory walker throw; that C++ exception escapes through the Lua VM
# and LuaUI fails to load entirely. Prune such links so a stale junction can never reach the game.
$widgetLinkRoot = Join-Path $repositoryRoot 'Widgets'
$danglingLinks = Get-ChildItem -LiteralPath $widgetLinkRoot -Force |
    Where-Object {
        $_.LinkType -eq 'Junction' -and
            -not (Test-Path -LiteralPath ($_.Target | Select-Object -First 1) -PathType Container)
    }

foreach ($danglingLink in $danglingLinks) {
    $target = $danglingLink.Target -join ';'
    if (-not $PSCmdlet.ShouldProcess($danglingLink.FullName, "Remove dangling junction (missing target $target)")) {
        continue
    }
    Remove-Item -LiteralPath $danglingLink.FullName -Force
    Write-Output "Removed dangling junction: $($danglingLink.FullName) (missing target $target)"
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
