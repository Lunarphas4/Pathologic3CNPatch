param(
    [string]$GameDataDir = "D:\Pathologic3_CN_Work\Pathologic 3\Pathologic3_Data",
    [string]$UabeaDir = "D:\Pathologic3_CN_Work\02_tools\UABEA",
    [string]$AssetStudioDir = "D:\Pathologic3_CN_Work\02_tools\AssetStudio",
    [string]$BackupRoot = "D:\Pathologic3_CN_Work\09_patch_work\game_file_backups",
    [string]$ReportDir = "D:\Pathologic3_CN_Work\00_codex_reports",
    [long]$FontAssetPathId = 927,
    [long]$TargetFallbackPathId = 931
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

$sharedAssetsPath = Join-Path $GameDataDir "sharedassets0.assets"
$sharedResSPath = Join-Path $GameDataDir "sharedassets0.assets.resS"
$classData = Join-Path $UabeaDir "classdata.tpk"
$assetsDll = Join-Path $UabeaDir "AssetsTools.NET.dll"
$monoCecilBridge = Join-Path $UabeaDir "AssetsTools.NET.MonoCecil.dll"
$monoCecil = Join-Path $AssetStudioDir "Mono.Cecil.dll"
$monoCecilRocks = Join-Path $AssetStudioDir "Mono.Cecil.Rocks.dll"
$managedDir = Join-Path $GameDataDir "Managed"

foreach ($requiredPath in @(
    $sharedAssetsPath,
    $classData,
    $assetsDll,
    $monoCecilBridge,
    $monoCecil,
    $monoCecilRocks,
    $managedDir
)) {
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

[void][Reflection.Assembly]::LoadFrom($monoCecil)
[void][Reflection.Assembly]::LoadFrom($monoCecilRocks)
[void][Reflection.Assembly]::LoadFrom($assetsDll)
[void][Reflection.Assembly]::LoadFrom($monoCecilBridge)

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupDir = Join-Path $BackupRoot "sharedassets0_font_patch_$timestamp"
New-Item -ItemType Directory -Path $backupDir | Out-Null

$assetsBackup = Join-Path $backupDir "sharedassets0.assets"
$resSBackup = Join-Path $backupDir "sharedassets0.assets.resS"
$tempOutput = Join-Path $backupDir "sharedassets0.assets.patched"
$reportPath = Join-Path $ReportDir "70_chianti_fallback_patch_$timestamp.md"

Copy-Item -LiteralPath $sharedAssetsPath -Destination $assetsBackup -Force
if (Test-Path -LiteralPath $sharedResSPath) {
    Copy-Item -LiteralPath $sharedResSPath -Destination $resSBackup -Force
}

$am = [AssetsTools.NET.Extra.AssetsManager]::new()
$am.MonoTempGenerator = [AssetsTools.NET.Extra.MonoCecilTempGenerator]::new($managedDir)
$null = $am.LoadClassPackage($classData)
$inst = $am.LoadAssetsFile($sharedAssetsPath, $false)
$cldb = $am.LoadClassDatabaseFromPackage($inst.file.Metadata.UnityVersion)

$fontInfo = $inst.file.AssetInfos | Where-Object { $_.PathId -eq $FontAssetPathId } | Select-Object -First 1
if ($null -eq $fontInfo) {
    throw "Font asset PathId not found: $FontAssetPathId"
}

$targetInfo = $inst.file.AssetInfos | Where-Object { $_.PathId -eq $TargetFallbackPathId } | Select-Object -First 1
if ($null -eq $targetInfo) {
    throw "Target fallback asset PathId not found: $TargetFallbackPathId"
}

$fontName = [AssetsTools.NET.Extra.AssetHelper]::GetAssetNameFast($inst.file, $cldb, $fontInfo)
$targetName = [AssetsTools.NET.Extra.AssetHelper]::GetAssetNameFast($inst.file, $cldb, $targetInfo)

$field = $am.GetBaseField($inst, $fontInfo, [AssetsTools.NET.Extra.AssetReadFlags]::None)
$fallbackArray = $field["m_FallbackFontAssetTable"]["Array"]

if ($fallbackArray.Children.Count -lt 1) {
    throw "Fallback array is empty on font asset: $fontName"
}

$fallbackEntry = $fallbackArray[0]
$oldFileId = $fallbackEntry["m_FileID"].AsInt
$oldPathId = $fallbackEntry["m_PathID"].AsLong

$fallbackEntry["m_FileID"].AsInt = 0
$fallbackEntry["m_PathID"].AsLong = $TargetFallbackPathId

$replacer = [AssetsTools.NET.AssetsReplacerFromMemory]::new($inst.file, $fontInfo, $field)
$replacers = [System.Collections.Generic.List[AssetsTools.NET.AssetsReplacer]]::new()
$replacers.Add($replacer) | Out-Null
$writer = [AssetsTools.NET.AssetsFileWriter]::new($tempOutput)
try {
    $inst.file.Write(
        $writer,
        0,
        $replacers,
        $cldb
    ) | Out-Null
}
finally {
    $writer.Dispose()
    $am.UnloadAll($true)
}

if (Test-Path -LiteralPath $sharedAssetsPath) {
    Remove-Item -LiteralPath $sharedAssetsPath -Force
}
[System.IO.File]::Move($tempOutput, $sharedAssetsPath)

$reportLines = @(
    "# Chianti Font Fallback Patch",
    "",
    "- SharedAssetsPath = $sharedAssetsPath",
    "- BackupDir = $backupDir",
    "- FontAssetPathId = $FontAssetPathId",
    "- FontAssetName = $fontName",
    "- OldFallbackFileId = $oldFileId",
    "- OldFallbackPathId = $oldPathId",
    "- NewFallbackFileId = 0",
    "- NewFallbackPathId = $TargetFallbackPathId",
    "- NewFallbackName = $targetName"
)
Write-Utf8NoBom -Path $reportPath -Lines $reportLines

Write-Output "BackupDir: $backupDir"
Write-Output "FontAssetName: $fontName"
Write-Output "OldFallbackPathId: $oldPathId"
Write-Output "NewFallbackPathId: $TargetFallbackPathId"
Write-Output "NewFallbackName: $targetName"
Write-Output "ReportPath: $reportPath"
