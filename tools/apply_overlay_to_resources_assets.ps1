param(
    [string]$OverlayRoot = "D:\Pathologic3_CN_Work\09_patch_work\overlay_cn_textassets_20260422",
    [string]$GameDataDir = "D:\Pathologic3_CN_Work\Pathologic 3\Pathologic3_Data",
    [string]$ToolsDir = "D:\Pathologic3_CN_Work\02_tools\UABEA",
    [string]$BackupRoot = "D:\Pathologic3_CN_Work\09_patch_work\game_file_backups",
    [string]$ReportDir = "D:\Pathologic3_CN_Work\00_codex_reports"
)

# Path-aware overlay applier (post-bug fix 2026-05-09).
#
# 旧实现以"文件名（不含扩展名）"作为 hashtable key，把 419 组同名文件折叠成
# 一份后再覆盖到 resources.assets，导致每组里的 PersonalFiles/UI/SymptomGroups
# 等多个不同 asset 全被同一份内容覆盖，约 870 个本地化 asset 实例被串错。
#
# 新实现改为：
#   1. 从 globalgamemanagers 的 ResourceManager.m_Container 抓出
#      "lowercase resource path -> (FileID, PathID)" 映射（FileID=4 = resources.assets）。
#   2. 把每个 overlay 文件按"相对 OverlayRoot 的路径，去扩展名，转小写，斜杠归一"
#      映射成 ResourceManager key，从而精准锁定单个 PathID。
#   3. 按 PathID 精确写回，不再依赖 asset name 去重。
#
# Verification: 跑过 9110 / 9110 全匹配 ResourceManager，且每个 overlay 文件唯一
# 对应一个 PathID（无 PathID 共用），所以这个映射对当前 overlay 是完备的。

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
$resourcesResSPath = Join-Path $GameDataDir "resources.assets.resS"
$ggmPath = Join-Path $GameDataDir "globalgamemanagers"

foreach ($requiredPath in @($OverlayRoot, $assetsDll, $classData, $resourcesPath, $ggmPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required path not found: $requiredPath"
    }
}

if (-not (Test-Path -LiteralPath $BackupRoot)) {
    New-Item -ItemType Directory -Path $BackupRoot | Out-Null
}

if (-not (Test-Path -LiteralPath $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir | Out-Null
}

[void][Reflection.Assembly]::LoadFrom($assetsDll)

# Step 1: Build ResourceManager path -> PathID map (only FileID=4 -> resources.assets).
$rmMap = @{}
$am = New-Object AssetsTools.NET.Extra.AssetsManager
try {
    $null = $am.LoadClassPackage($classData)
    $ggmInst = $am.LoadAssetsFile($ggmPath, $false)
    $null = $am.LoadClassDatabaseFromPackage($ggmInst.file.Metadata.UnityVersion)

    # Locate the resources.assets entry in externals to derive its FileID for ResourceManager PPtrs.
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
    Write-Output "ResourceManager FileID for resources.assets = $resourcesFileId"

    $rmInfo = $ggmInst.file.AssetInfos | Where-Object { $_.TypeId -eq 147 } | Select-Object -First 1
    if ($null -eq $rmInfo) {
        throw "ResourceManager (TypeId 147) not found in globalgamemanagers"
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
    Write-Output "ResourceManager keys pointing into resources.assets: $($rmMap.Count)"
}
finally {
    $am.UnloadAll($true)
}

# Step 2: Index overlay files by relative path -> (relPath, content, rmKey).
$overlayFiles = Get-ChildItem -LiteralPath $OverlayRoot -Recurse -File |
    Where-Object { $_.Extension -in @(".txt", ".ids") } |
    Sort-Object FullName

$overlayByKey = @{}
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

    if ($overlayByKey.ContainsKey($rmKey)) {
        # Two overlay files generating the same lowercase rm_key -> data integrity issue in overlay tree.
        throw "Duplicate overlay rm_key '$rmKey' for files '$($overlayByKey[$rmKey].rel_path)' and '$relPath'"
    }
    $overlayByKey[$rmKey] = $entry

    if ($rmMap.ContainsKey($rmKey)) {
        $entry.path_id = [int64]$rmMap[$rmKey]
        if ($overlayByPathId.ContainsKey($entry.path_id)) {
            $existing = $overlayByPathId[$entry.path_id]
            throw "Two overlay files map to the same PathID $($entry.path_id): '$($existing.rel_path)' and '$relPath'"
        }
        $overlayByPathId[$entry.path_id] = $entry
    }
    else {
        $overlayUnmapped.Add($entry) | Out-Null
    }
}

Write-Output "Overlay files: $($overlayFiles.Count)"
Write-Output "Mapped to PathID: $($overlayByPathId.Count)"
Write-Output "Unmapped (no ResourceManager entry): $($overlayUnmapped.Count)"

# Step 3: Backup and load resources.assets.
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $BackupRoot "resources_assets_patch_$timestamp"
New-Item -ItemType Directory -Path $backupDir | Out-Null

$resourcesBackup = Join-Path $backupDir "resources.assets"
$resourcesResSBackup = Join-Path $backupDir "resources.assets.resS"
$tempOutput = Join-Path $backupDir "resources.assets.patched"
$samplePath = Join-Path $ReportDir "59_resources_assets_patch_samples.tsv"
$reportPath = Join-Path $ReportDir "60_resources_assets_patch_report.md"

Copy-Item -LiteralPath $resourcesPath -Destination $resourcesBackup -Force
if (Test-Path -LiteralPath $resourcesResSPath) {
    Copy-Item -LiteralPath $resourcesResSPath -Destination $resourcesResSBackup -Force
}

$am = New-Object AssetsTools.NET.Extra.AssetsManager
try {
    $null = $am.LoadClassPackage($classData)
    $inst = $am.LoadAssetsFile($resourcesPath, $false)
    $cldb = $am.LoadClassDatabaseFromPackage($inst.file.Metadata.UnityVersion)

    $replacers = New-Object 'System.Collections.Generic.List[AssetsTools.NET.AssetsReplacer]'
    $samples = New-Object System.Collections.Generic.List[object]
    $assetMatchCount = 0
    $alreadyMatch = 0
    $patched = 0
    $patchedPathIds = New-Object 'System.Collections.Generic.HashSet[int64]'

    foreach ($info in ($inst.file.AssetInfos | Where-Object { $_.TypeId -eq 49 })) {
        $infoPathId = [int64]$info.PathId
        if (-not $overlayByPathId.ContainsKey($infoPathId)) {
            continue
        }

        $entry = $overlayByPathId[$infoPathId]
        $assetMatchCount++

        $field = $am.GetBaseField($inst, $info, [AssetsTools.NET.Extra.AssetReadFlags]::None)
        $originalScript = $field["m_Script"].AsString
        $newScript = $entry.text

        if (-not [string]::IsNullOrEmpty($originalScript) -and $originalScript[0] -eq [char]0xFEFF -and
            ($newScript.Length -eq 0 -or $newScript[0] -ne [char]0xFEFF)) {
            $newScript = [string]([char]0xFEFF) + $newScript
        }

        if ($originalScript -ceq $newScript) {
            $alreadyMatch++
            $null = $patchedPathIds.Add($infoPathId)
            continue
        }

        $field["m_Script"].AsString = $newScript
        $replacer = New-Object AssetsTools.NET.AssetsReplacerFromMemory($inst.file, $info, $field)
        $replacers.Add($replacer) | Out-Null
        $patched++
        $null = $patchedPathIds.Add($infoPathId)

        if ($samples.Count -lt 40) {
            $oldPreview = Normalize-Value $originalScript
            $newPreview = Normalize-Value $newScript

            if ($oldPreview.Length -gt 120) {
                $oldPreview = $oldPreview.Substring(0, 120)
            }
            if ($newPreview.Length -gt 120) {
                $newPreview = $newPreview.Substring(0, 120)
            }

            $samples.Add([pscustomobject]@{
                rel_path = $entry.rel_path
                rm_key = $entry.rm_key
                path_id = $infoPathId
                old_preview = $oldPreview
                new_preview = $newPreview
            })
        }
    }

    $missingPathIds = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $overlayByPathId.Values) {
        if (-not $patchedPathIds.Contains([int64]$entry.path_id)) {
            $missingPathIds.Add($entry) | Out-Null
        }
    }

    $writer = New-Object AssetsTools.NET.AssetsFileWriter($tempOutput)
    try {
        $inst.file.Write($writer, 0, $replacers, $cldb) | Out-Null
    }
    finally {
        $writer.Dispose()
    }
}
finally {
    $am.UnloadAll($true)
}

if (Test-Path -LiteralPath $resourcesPath) {
    Remove-Item -LiteralPath $resourcesPath -Force
}
[System.IO.File]::Move($tempOutput, $resourcesPath)

# Step 4: Write reports.
$sampleColumns = @("rel_path", "rm_key", "path_id", "old_preview", "new_preview")
$sampleLines = New-Object System.Collections.Generic.List[string]
$sampleLines.Add(($sampleColumns -join "`t"))
foreach ($sample in $samples) {
    $sampleLines.Add((
        @(
            $sample.rel_path,
            $sample.rm_key,
            [string]$sample.path_id,
            $sample.old_preview,
            $sample.new_preview
        ) -join "`t"
    ))
}
Write-Utf8NoBom -Path $samplePath -Lines $sampleLines

$reportLines = @(
    "# Resources Assets Patch Report",
    "",
    "- OverlayRoot = $OverlayRoot",
    "- GameDataDir = $GameDataDir",
    "- ResourcesPath = $resourcesPath",
    "- BackupDir = $backupDir",
    "- SamplePath = $samplePath",
    "- Strategy = ResourceManager path -> PathID (FileID=$resourcesFileId)",
    "",
    "Results:",
    "",
    "- overlay_files = $($overlayFiles.Count)",
    "- overlay_mapped_to_pathid = $($overlayByPathId.Count)",
    "- overlay_unmapped = $($overlayUnmapped.Count)",
    "- asset_instances_visited = $assetMatchCount",
    "- already_matching = $alreadyMatch",
    "- replacers_written = $patched",
    "- pathids_patched_or_matching = $($patchedPathIds.Count)",
    "- missing_pathids_after_pass = $($missingPathIds.Count)"
)

if ($overlayUnmapped.Count -gt 0) {
    $reportLines += ""
    $reportLines += "Unmapped overlay files (no ResourceManager entry):"
    $reportLines += ""
    foreach ($entry in ($overlayUnmapped | Select-Object -First 50)) {
        $reportLines += "- $($entry.rel_path)"
    }
}

if ($missingPathIds.Count -gt 0) {
    $reportLines += ""
    $reportLines += "PathIDs that have an overlay but no matching asset in resources.assets:"
    $reportLines += ""
    foreach ($entry in ($missingPathIds | Select-Object -First 50)) {
        $reportLines += "- pathid=$($entry.path_id) rm_key=$($entry.rm_key) rel_path=$($entry.rel_path)"
    }
}

Write-Utf8NoBom -Path $reportPath -Lines $reportLines

Write-Output "BackupDir: $backupDir"
Write-Output "Overlay files: $($overlayFiles.Count)"
Write-Output "Mapped to PathID: $($overlayByPathId.Count)"
Write-Output "Visited matching assets: $assetMatchCount"
Write-Output "Replacers written: $patched"
Write-Output "Already matched (skipped): $alreadyMatch"
Write-Output "Unmapped overlay (no ResourceManager entry): $($overlayUnmapped.Count)"
Write-Output "PathIDs missing after pass: $($missingPathIds.Count)"
