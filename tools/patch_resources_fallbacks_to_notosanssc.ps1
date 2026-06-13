param(
    [string]$GameDataDir = "D:\Pathologic3_CN_Work\Pathologic 3\Pathologic3_Data",
    [string]$UabeaDir = "D:\Pathologic3_CN_Work\02_tools\UABEA",
    [string]$AssetStudioDir = "D:\Pathologic3_CN_Work\02_tools\AssetStudio",
    [string]$BackupRoot = "D:\Pathologic3_CN_Work\09_patch_work\game_file_backups",
    [string]$ReportDir = "D:\Pathologic3_CN_Work\00_codex_reports",
    [long[]]$FontAssetPathIds = @(279128, 278967),
    [long]$TmpSettingsPathId = 279131,
    [long]$TargetFallbackPathId = 931,
    [string]$TargetExternalAssetFile = "sharedassets0.assets"
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

function Copy-Field {
    param(
        [AssetsTools.NET.AssetTypeValueField]$Source
    )

    $children = [System.Collections.Generic.List[AssetsTools.NET.AssetTypeValueField]]::new()
    foreach ($child in $Source.Children) {
        $children.Add((Copy-Field -Source $child)) | Out-Null
    }

    $copy = [AssetsTools.NET.AssetTypeValueField]::new()
    $template = $null
    if ($null -ne $Source.TemplateField) {
        $template = $Source.TemplateField.Clone()
    }
    [void]$copy.Read($Source.Value, $template, $children)
    return ,$copy
}

function Get-ChildFieldByName {
    param(
        [AssetsTools.NET.AssetTypeValueField]$Parent,
        [string]$Name
    )

    foreach ($child in $Parent.Children) {
        if ($child.FieldName -eq $Name) {
            return ,$child
        }
    }

    throw "Child field '$Name' not found under '$($Parent.FieldName)'."
}

function Set-VectorToSinglePPtr {
    param(
        [AssetsTools.NET.AssetTypeValueField]$VectorField,
        [AssetsTools.NET.AssetTypeValueField]$TemplatePPtr,
        [int]$FileId,
        [long]$PathId
    )

    $arrayField = $VectorField.Get("Array")
    if ($null -eq $arrayField) {
        throw "Vector field '$($VectorField.FieldName)' does not expose an Array child."
    }

    $entry = Copy-Field -Source $TemplatePPtr
    (Get-ChildFieldByName -Parent $entry -Name "m_FileID").AsInt = $FileId
    (Get-ChildFieldByName -Parent $entry -Name "m_PathID").AsLong = $PathId

    $arrayField.Children.Clear()
    $arrayField.Children.Add($entry) | Out-Null
    $arrayField.AsArray = [AssetsTools.NET.AssetTypeArrayInfo]::new($arrayField.Children.Count)
}

$resourcesPath = Join-Path $GameDataDir "resources.assets"
$resourcesResSPath = Join-Path $GameDataDir "resources.assets.resS"
$sharedAssetsPath = Join-Path $GameDataDir "sharedassets0.assets"
$classData = Join-Path $UabeaDir "classdata.tpk"
$assetsDll = Join-Path $UabeaDir "AssetsTools.NET.dll"
$monoCecilBridge = Join-Path $UabeaDir "AssetsTools.NET.MonoCecil.dll"
$monoCecil = Join-Path $AssetStudioDir "Mono.Cecil.dll"
$monoCecilRocks = Join-Path $AssetStudioDir "Mono.Cecil.Rocks.dll"
$managedDir = Join-Path $GameDataDir "Managed"

foreach ($requiredPath in @(
    $resourcesPath,
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
$backupDir = Join-Path $BackupRoot "resources_font_fallback_patch_$timestamp"
New-Item -ItemType Directory -Path $backupDir | Out-Null

$resourcesBackup = Join-Path $backupDir "resources.assets"
$resourcesResSBackup = Join-Path $backupDir "resources.assets.resS"
$tempOutput = Join-Path $backupDir "resources.assets.patched"
$reportPath = Join-Path $ReportDir "85_resources_font_fallback_patch_$timestamp.md"

Copy-Item -LiteralPath $resourcesPath -Destination $resourcesBackup -Force
if (Test-Path -LiteralPath $resourcesResSPath) {
    Copy-Item -LiteralPath $resourcesResSPath -Destination $resourcesResSBackup -Force
}

$am = [AssetsTools.NET.Extra.AssetsManager]::new()
$am.MonoTempGenerator = [AssetsTools.NET.Extra.MonoCecilTempGenerator]::new($managedDir)
$null = $am.LoadClassPackage($classData)

$sharedInst = $am.LoadAssetsFile($sharedAssetsPath, $false)
$sharedCldb = $am.LoadClassDatabaseFromPackage($sharedInst.file.Metadata.UnityVersion)
$targetInfo = $sharedInst.file.AssetInfos | Where-Object { $_.PathId -eq $TargetFallbackPathId } | Select-Object -First 1
if ($null -eq $targetInfo) {
    throw "Target fallback asset PathId not found in sharedassets0.assets: $TargetFallbackPathId"
}
$targetName = [AssetsTools.NET.Extra.AssetHelper]::GetAssetNameFast($sharedInst.file, $sharedCldb, $targetInfo)

$inst = $am.LoadAssetsFile($resourcesPath, $false)
$cldb = $am.LoadClassDatabaseFromPackage($inst.file.Metadata.UnityVersion)

$externalIndex = -1
for ($i = 0; $i -lt $inst.file.Metadata.Externals.Count; $i++) {
    if ($inst.file.Metadata.Externals[$i].PathName -eq $TargetExternalAssetFile) {
        $externalIndex = $i
        break
    }
}
if ($externalIndex -lt 0) {
    throw "External dependency not found in resources.assets: $TargetExternalAssetFile"
}
$targetFileId = $externalIndex + 1

$templateSourceInfo = $inst.file.AssetInfos | Where-Object { $_.PathId -eq $FontAssetPathIds[0] } | Select-Object -First 1
if ($null -eq $templateSourceInfo) {
    throw "Template source font asset PathId not found: $($FontAssetPathIds[0])"
}
$templateSourceField = $am.GetBaseField($inst, $templateSourceInfo, [AssetsTools.NET.Extra.AssetReadFlags]::None)
$templateVector = $templateSourceField.Get("m_FallbackFontAssetTable")
$templateArray = $templateVector.Get("Array")
if ($null -eq $templateArray -or $templateArray.Children.Count -lt 1) {
    throw "Template source font asset does not contain a fallback entry to clone."
}
$templatePPtr = $templateArray.Children[0]

$replacers = [System.Collections.Generic.List[AssetsTools.NET.AssetsReplacer]]::new()
$reportLines = [System.Collections.Generic.List[string]]::new()
$reportLines.Add("# Resources Font Fallback Patch")
$reportLines.Add("")
$reportLines.Add("- ResourcesPath = $resourcesPath")
$reportLines.Add("- BackupDir = $backupDir")
$reportLines.Add("- TargetExternalAssetFile = $TargetExternalAssetFile")
$reportLines.Add("- TargetExternalFileId = $targetFileId")
$reportLines.Add("- TargetFallbackPathId = $TargetFallbackPathId")
$reportLines.Add("- TargetFallbackName = $targetName")
$reportLines.Add("")
$reportLines.Add("Patched font vectors:")
$reportLines.Add("")

foreach ($fontPathId in $FontAssetPathIds) {
    $fontInfo = $inst.file.AssetInfos | Where-Object { $_.PathId -eq $fontPathId } | Select-Object -First 1
    if ($null -eq $fontInfo) {
        throw "Font asset PathId not found in resources.assets: $fontPathId"
    }

    $fontName = [AssetsTools.NET.Extra.AssetHelper]::GetAssetNameFast($inst.file, $cldb, $fontInfo)
    $fontField = $am.GetBaseField($inst, $fontInfo, [AssetsTools.NET.Extra.AssetReadFlags]::None)
    $vectorField = $fontField.Get("m_FallbackFontAssetTable")
    $arrayField = $vectorField.Get("Array")

    $oldEntrySummary = "<empty>"
    if ($null -ne $arrayField -and $arrayField.Children.Count -gt 0) {
        $oldEntry = $arrayField.Children[0]
        $oldFileId = (Get-ChildFieldByName -Parent $oldEntry -Name "m_FileID").AsInt
        $oldPathId = (Get-ChildFieldByName -Parent $oldEntry -Name "m_PathID").AsLong
        $oldEntrySummary = "fileID=$oldFileId, pathID=$oldPathId"
    }

    Set-VectorToSinglePPtr -VectorField $vectorField -TemplatePPtr $templatePPtr -FileId $targetFileId -PathId $TargetFallbackPathId

    $replacer = [AssetsTools.NET.AssetsReplacerFromMemory]::new($inst.file, $fontInfo, $fontField)
    $replacers.Add($replacer) | Out-Null

    $reportLines.Add("- PathId $fontPathId (`$fontName`) : $oldEntrySummary -> fileID=$targetFileId, pathID=$TargetFallbackPathId")
}

$tmpInfo = $inst.file.AssetInfos | Where-Object { $_.PathId -eq $TmpSettingsPathId } | Select-Object -First 1
if ($null -eq $tmpInfo) {
    throw "TMP Settings PathId not found in resources.assets: $TmpSettingsPathId"
}

$tmpName = [AssetsTools.NET.Extra.AssetHelper]::GetAssetNameFast($inst.file, $cldb, $tmpInfo)
$tmpField = $am.GetBaseField($inst, $tmpInfo, [AssetsTools.NET.Extra.AssetReadFlags]::None)
$tmpVector = $tmpField.Get("m_fallbackFontAssets")
$tmpArray = $tmpVector.Get("Array")
$oldGlobalCount = if ($null -eq $tmpArray) { 0 } else { $tmpArray.Children.Count }

Set-VectorToSinglePPtr -VectorField $tmpVector -TemplatePPtr $templatePPtr -FileId $targetFileId -PathId $TargetFallbackPathId

$tmpReplacer = [AssetsTools.NET.AssetsReplacerFromMemory]::new($inst.file, $tmpInfo, $tmpField)
$replacers.Add($tmpReplacer) | Out-Null

$reportLines.Add("")
$reportLines.Add("Patched TMP settings:")
$reportLines.Add("")
$reportLines.Add("- PathId $TmpSettingsPathId (`$tmpName`) : old global fallback count = $oldGlobalCount -> 1 entry to fileID=$targetFileId, pathID=$TargetFallbackPathId")

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

if (Test-Path -LiteralPath $resourcesPath) {
    Remove-Item -LiteralPath $resourcesPath -Force
}
[System.IO.File]::Move($tempOutput, $resourcesPath)

Write-Utf8NoBom -Path $reportPath -Lines $reportLines

Write-Output "BackupDir: $backupDir"
Write-Output "TargetExternalFileId: $targetFileId"
Write-Output "TargetFallbackPathId: $TargetFallbackPathId"
Write-Output "TargetFallbackName: $targetName"
Write-Output "PatchedFontAssets: $($FontAssetPathIds -join ', ')"
Write-Output "PatchedTmpSettings: $TmpSettingsPathId"
Write-Output "ReportPath: $reportPath"
