param(
    [string]$OverlayRoot = "D:\Pathologic3_CN_Work\09_patch_work\overlay_cn_textassets_20260422",
    [string]$GameDataDir = "D:\Pathologic3_CN_Work\Pathologic 3\Pathologic3_Data",
    [string]$ToolsDir = "D:\Pathologic3_CN_Work\02_tools\UABEA",
    [string]$ReportDir = "D:\Pathologic3_CN_Work\00_codex_reports"
)

# Path-aware verification (post-bug fix 2026-05-09).
# Mirrors apply_overlay_to_resources_assets.ps1 logic so we don't lie to ourselves
# again about "exact_matches = 9110" while the personalfiles slot is silently
# loaded with ui/tablet content.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-Value {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return $Value.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Read-Utf8File {
    param(
        [string]$Path
    )

    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    [System.IO.File]::WriteAllLines($Path, $Lines, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-RmKey {
    param(
        [string]$RelativePath
    )

    $noExt = [System.IO.Path]::ChangeExtension($RelativePath, $null)
    if ($noExt.EndsWith(".")) {
        $noExt = $noExt.Substring(0, $noExt.Length - 1)
    }
    return ($noExt -replace '\\', '/').ToLowerInvariant()
}

$assetsDll = Join-Path $ToolsDir "AssetsTools.NET.dll"
$classData = Join-Path $ToolsDir "classdata.tpk"
$resourcesPath = Join-Path $GameDataDir "resources.assets"
$ggmPath = Join-Path $GameDataDir "globalgamemanagers"

foreach ($requiredPath in @($OverlayRoot, $assetsDll, $classData, $resourcesPath, $ggmPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required path not found: $requiredPath"
    }
}

if (-not (Test-Path -LiteralPath $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir | Out-Null
}

[void][Reflection.Assembly]::LoadFrom($assetsDll)

# Step 1: ResourceManager map.
$rmMap = @{}
$am = New-Object AssetsTools.NET.Extra.AssetsManager
try {
    $null = $am.LoadClassPackage($classData)
    $ggmInst = $am.LoadAssetsFile($ggmPath, $false)
    $null = $am.LoadClassDatabaseFromPackage($ggmInst.file.Metadata.UnityVersion)

    $resourcesFileId = -1
    for ($i = 0; $i -lt $ggmInst.file.Metadata.Externals.Count; $i++) {
        $ext = $ggmInst.file.Metadata.Externals[$i]
        if ($ext.PathName -ieq "resources.assets") {
            $resourcesFileId = $i + 1
            break
        }
    }
    if ($resourcesFileId -lt 0) {
        throw "resources.assets not found in globalgamemanagers externals"
    }

    $rmInfo = $ggmInst.file.AssetInfos | Where-Object { $_.TypeId -eq 147 } | Select-Object -First 1
    if ($null -eq $rmInfo) {
        throw "ResourceManager (TypeId 147) not found"
    }
    $rmField = $am.GetBaseField($ggmInst, $rmInfo)
    $container = $rmField["m_Container"]["Array"]
    for ($i = 0; $i -lt $container.Children.Count; $i++) {
        $entry = $container.Children[$i]
        $key = $entry.Children[0].AsString
        $ptr = $entry.Children[1]
        $fid = $ptr["m_FileID"].AsInt
        $resPathId = $ptr["m_PathID"].AsLong
        if ($fid -eq $resourcesFileId) {
            $rmMap[$key] = $resPathId
        }
    }
}
finally {
    $am.UnloadAll($true)
}

# Step 2: overlay map by PathID.
$overlayFiles = Get-ChildItem -LiteralPath $OverlayRoot -Recurse -File |
    Where-Object { $_.Extension -in @(".txt", ".ids") } |
    Sort-Object FullName

$overlayByPathId = @{}
$overlayUnmapped = New-Object System.Collections.Generic.List[object]
$rootPrefixLen = $OverlayRoot.Length + 1

foreach ($file in $overlayFiles) {
    $relPath = $file.FullName.Substring($rootPrefixLen)
    $rmKey = ConvertTo-RmKey -RelativePath $relPath

    $entry = [pscustomobject]@{
        rel_path = $relPath
        rm_key = $rmKey
        path_id = $null
        text = Normalize-Value (Read-Utf8File -Path $file.FullName)
    }

    if ($rmMap.ContainsKey($rmKey)) {
        $entry.path_id = [int64]$rmMap[$rmKey]
        if ($overlayByPathId.ContainsKey($entry.path_id)) {
            throw "Two overlay files map to PathID $($entry.path_id)"
        }
        $overlayByPathId[$entry.path_id] = $entry
    }
    else {
        $overlayUnmapped.Add($entry) | Out-Null
    }
}

# Step 3: walk resources.assets, compare matched PathIDs.
$matchedInstances = 0
$exactMatches = 0
$mismatches = New-Object System.Collections.Generic.List[object]
$missingPathIds = New-Object System.Collections.Generic.List[object]
$visitedPathIds = New-Object 'System.Collections.Generic.HashSet[int64]'

$am = New-Object AssetsTools.NET.Extra.AssetsManager
try {
    $null = $am.LoadClassPackage($classData)
    $inst = $am.LoadAssetsFile($resourcesPath, $false)
    $null = $am.LoadClassDatabaseFromPackage($inst.file.Metadata.UnityVersion)

    foreach ($info in ($inst.file.AssetInfos | Where-Object { $_.TypeId -eq 49 })) {
        $infoPathId = [int64]$info.PathId
        if (-not $overlayByPathId.ContainsKey($infoPathId)) {
            continue
        }

        $entry = $overlayByPathId[$infoPathId]
        $matchedInstances++
        $null = $visitedPathIds.Add($infoPathId)

        $field = $am.GetBaseField($inst, $info, [AssetsTools.NET.Extra.AssetReadFlags]::None)
        $actual = Normalize-Value $field["m_Script"].AsString
        $expected = $entry.text

        if (-not [string]::IsNullOrEmpty($actual) -and $actual[0] -eq [char]0xFEFF) {
            $actual = $actual.Substring(1)
        }
        if (-not [string]::IsNullOrEmpty($expected) -and $expected[0] -eq [char]0xFEFF) {
            $expected = $expected.Substring(1)
        }

        if ($actual -ceq $expected) {
            $exactMatches++
        }
        elseif ($mismatches.Count -lt 50) {
            $actualPreview = if ($actual.Length -gt 160) { $actual.Substring(0, 160) } else { $actual }
            $expectedPreview = if ($expected.Length -gt 160) { $expected.Substring(0, 160) } else { $expected }

            $mismatches.Add([pscustomobject]@{
                rel_path = $entry.rel_path
                rm_key = $entry.rm_key
                path_id = $infoPathId
                actual_preview = $actualPreview
                expected_preview = $expectedPreview
            })
        }
    }

    foreach ($entry in $overlayByPathId.Values) {
        if (-not $visitedPathIds.Contains([int64]$entry.path_id)) {
            $missingPathIds.Add($entry) | Out-Null
        }
    }
}
finally {
    $am.UnloadAll($true)
}

$mismatchPath = Join-Path $ReportDir "61_resources_assets_overlay_mismatches.tsv"
$reportPath = Join-Path $ReportDir "62_resources_assets_overlay_verification.md"

$mismatchColumns = @("rel_path", "rm_key", "path_id", "actual_preview", "expected_preview")
$mismatchLines = New-Object System.Collections.Generic.List[string]
$mismatchLines.Add(($mismatchColumns -join "`t"))
foreach ($row in $mismatches) {
    $mismatchLines.Add((
        @(
            $row.rel_path,
            $row.rm_key,
            [string]$row.path_id,
            $row.actual_preview,
            $row.expected_preview
        ) -join "`t"
    ))
}
Write-Utf8NoBom -Path $mismatchPath -Lines $mismatchLines

$reportLines = @(
    "# Resources Assets Overlay Verification",
    "",
    "- OverlayRoot = $OverlayRoot",
    "- ResourcesPath = $resourcesPath",
    "- Strategy = ResourceManager path -> PathID",
    "- MismatchPath = $mismatchPath",
    "",
    "Results:",
    "",
    "- overlay_files = $($overlayFiles.Count)",
    "- overlay_mapped_to_pathid = $($overlayByPathId.Count)",
    "- overlay_unmapped = $($overlayUnmapped.Count)",
    "- matched_asset_instances = $matchedInstances",
    "- exact_matches = $exactMatches",
    "- mismatched_instances = $($matchedInstances - $exactMatches)",
    "- pathids_present_in_resources = $($visitedPathIds.Count)",
    "- pathids_missing_in_resources = $($missingPathIds.Count)"
)

if ($missingPathIds.Count -gt 0) {
    $reportLines += ""
    $reportLines += "Missing PathIDs (overlay has them, but no matching TextAsset in resources.assets):"
    $reportLines += ""
    foreach ($entry in ($missingPathIds | Select-Object -First 30)) {
        $reportLines += "- pathid=$($entry.path_id) rm_key=$($entry.rm_key) rel_path=$($entry.rel_path)"
    }
}

Write-Utf8NoBom -Path $reportPath -Lines $reportLines

Write-Output "Overlay files: $($overlayFiles.Count)"
Write-Output "Overlay mapped to PathID: $($overlayByPathId.Count)"
Write-Output "Matched asset instances: $matchedInstances"
Write-Output "Exact matches: $exactMatches"
Write-Output "Mismatched instances: $($matchedInstances - $exactMatches)"
Write-Output "PathIDs missing in resources.assets: $($missingPathIds.Count)"
