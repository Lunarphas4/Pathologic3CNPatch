param(
    [string]$ResourceRoot = "D:\Pathologic3_CN_Work\08_assetripper_export\full_export_20260421\ExportedProject\Assets\Resources",
    [string]$OverlayRoot = "D:\Pathologic3_CN_Work\09_patch_work\overlay_cn_textassets_20260422",
    [string]$ReportDir = "D:\Pathologic3_CN_Work\00_codex_reports"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    [System.IO.File]::WriteAllLines($Path, $Lines, [System.Text.UTF8Encoding]::new($false))
}

function Ensure-ParentDirectory {
    param(
        [string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrEmpty($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Test-FileBytesEqual {
    param(
        [string]$SourcePath,
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        return $false
    }

    $sourceInfo = Get-Item -LiteralPath $SourcePath
    $destInfo = Get-Item -LiteralPath $DestinationPath
    if ($sourceInfo.Length -ne $destInfo.Length) {
        return $false
    }

    $sourceBytes = [System.IO.File]::ReadAllBytes($SourcePath)
    $destBytes = [System.IO.File]::ReadAllBytes($DestinationPath)
    return [System.Linq.Enumerable]::SequenceEqual(
        [byte[]]$sourceBytes,
        [byte[]]$destBytes
    )
}

function Remove-EmptyDirectoriesUpward {
    param(
        [string]$StartDirectory,
        [string]$StopDirectory
    )

    $current = $StartDirectory
    while (-not [string]::IsNullOrEmpty($current)) {
        if ([string]::Equals($current.TrimEnd('\'), $StopDirectory.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        if (-not (Test-Path -LiteralPath $current)) {
            $current = Split-Path -Parent $current
            continue
        }

        $hasChildren = Get-ChildItem -LiteralPath $current -Force | Select-Object -First 1
        if ($null -ne $hasChildren) {
            break
        }

        Remove-Item -LiteralPath $current -Force
        $current = Split-Path -Parent $current
    }
}

if (-not (Test-Path -LiteralPath $ResourceRoot)) {
    throw "Resource root not found: $ResourceRoot"
}

if (-not (Test-Path -LiteralPath $OverlayRoot)) {
    New-Item -ItemType Directory -Path $OverlayRoot | Out-Null
}

if (-not (Test-Path -LiteralPath $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir | Out-Null
}

$manifestPath = Join-Path $ReportDir "66_overlay_sync_manifest.txt"
$reportPath = Join-Path $ReportDir "81_overlay_sync_report.md"
$changesPath = Join-Path $ReportDir "82_overlay_sync_changes.tsv"

$desiredFiles = New-Object System.Collections.Generic.List[object]

$chineseFiles = Get-ChildItem -LiteralPath $ResourceRoot -Recurse -File -Filter "*_Chinese_Simplified.txt"
foreach ($file in $chineseFiles) {
    $relative = $file.FullName.Substring($ResourceRoot.Length).TrimStart('\')
    $desiredFiles.Add([pscustomobject]@{
        relative_path = $relative
        source_path = $file.FullName
        file_kind = "chinese_textasset"
    }) | Out-Null
}

$specialFiles = @(
    "Language.ids.ids",
    "ui\menu\settings\values\LanguageIds_English.txt",
    "ui\menu\settings\values\LanguageIds_Russian.txt",
    "ui\menu\settings\values\LanguageIds_German.txt",
    "ui\menu\settings\values\LanguageIds_Italian.txt",
    "ui\menu\settings\values\LanguageIds_Portuguese_Br.txt"
)

foreach ($relative in $specialFiles) {
    $source = Join-Path $ResourceRoot $relative
    if (-not (Test-Path -LiteralPath $source)) {
        continue
    }

    $desiredFiles.Add([pscustomobject]@{
        relative_path = $relative
        source_path = $source
        file_kind = "language_support"
    }) | Out-Null
}

$desiredFiles = $desiredFiles |
    Sort-Object relative_path -Unique

$previousManifest = @()
if (Test-Path -LiteralPath $manifestPath) {
    $previousManifest = Get-Content -LiteralPath $manifestPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

$desiredSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$changes = New-Object System.Collections.Generic.List[object]

$createdCount = 0
$updatedCount = 0
$unchangedCount = 0

foreach ($entry in $desiredFiles) {
    $null = $desiredSet.Add($entry.relative_path)

    $destinationPath = Join-Path $OverlayRoot $entry.relative_path
    Ensure-ParentDirectory -Path $destinationPath

    if (-not (Test-Path -LiteralPath $destinationPath)) {
        Copy-Item -LiteralPath $entry.source_path -Destination $destinationPath -Force
        $createdCount++
        $changes.Add([pscustomobject]@{
            action = "created"
            relative_path = $entry.relative_path
            file_kind = $entry.file_kind
        }) | Out-Null
        continue
    }

    if (Test-FileBytesEqual -SourcePath $entry.source_path -DestinationPath $destinationPath) {
        $unchangedCount++
        continue
    }

    Copy-Item -LiteralPath $entry.source_path -Destination $destinationPath -Force
    $updatedCount++
    $changes.Add([pscustomobject]@{
        action = "updated"
        relative_path = $entry.relative_path
        file_kind = $entry.file_kind
    }) | Out-Null
}

$removedCount = 0
foreach ($relative in $previousManifest | Sort-Object -Unique) {
    if ($desiredSet.Contains($relative)) {
        continue
    }

    $stalePath = Join-Path $OverlayRoot $relative
    if (-not (Test-Path -LiteralPath $stalePath)) {
        continue
    }

    Remove-Item -LiteralPath $stalePath -Force
    Remove-EmptyDirectoriesUpward -StartDirectory (Split-Path -Parent $stalePath) -StopDirectory $OverlayRoot
    $removedCount++
    $changes.Add([pscustomobject]@{
        action = "removed"
        relative_path = $relative
        file_kind = "stale_previous_sync"
    }) | Out-Null
}

$manifestLines = $desiredFiles | Select-Object -ExpandProperty relative_path
Write-Utf8NoBom -Path $manifestPath -Lines $manifestLines

$changeLines = New-Object System.Collections.Generic.List[string]
$changeLines.Add("action`trelative_path`tfile_kind")
foreach ($row in $changes | Sort-Object action, relative_path) {
    $changeLines.Add("$($row.action)`t$($row.relative_path)`t$($row.file_kind)")
}
Write-Utf8NoBom -Path $changesPath -Lines $changeLines

$reportLines = @(
    "# Overlay Sync Report",
    "",
    "- ResourceRoot = $ResourceRoot",
    "- OverlayRoot = $OverlayRoot",
    "- ManifestPath = $manifestPath",
    "- ChangesPath = $changesPath",
    "",
    "Results:",
    "",
    "- desired_files = $($desiredFiles.Count)",
    "- previous_manifest_entries = $(@($previousManifest | Sort-Object -Unique).Count)",
    "- created_files = $createdCount",
    "- updated_files = $updatedCount",
    "- unchanged_files = $unchangedCount",
    "- removed_stale_files = $removedCount"
)
Write-Utf8NoBom -Path $reportPath -Lines $reportLines

Write-Output "Desired files: $($desiredFiles.Count)"
Write-Output "Created files: $createdCount"
Write-Output "Updated files: $updatedCount"
Write-Output "Unchanged files: $unchangedCount"
Write-Output "Removed stale files: $removedCount"
Write-Output "Manifest: $manifestPath"
Write-Output "Report: $reportPath"
