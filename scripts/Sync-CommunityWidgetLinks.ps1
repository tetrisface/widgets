[CmdletBinding(SupportsShouldProcess)]
param()

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$communityWidgetsRoot = Join-Path $repositoryRoot 'BAR-Widgets\Widgets\tetrisface'

if (-not (Test-Path -LiteralPath $communityWidgetsRoot -PathType Container)) {
    throw "Community widgets checkout not found: $communityWidgetsRoot"
}

$widgetDirectories = Get-ChildItem -LiteralPath $communityWidgetsRoot -Directory | Sort-Object Name

foreach ($widgetDirectory in $widgetDirectories) {
    $widgetName = $widgetDirectory.Name
    $sourcePath = $widgetDirectory.FullName
    $linkPath = Join-Path (Join-Path $repositoryRoot 'Widgets') $widgetName

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
