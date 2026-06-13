param(
    [string]$GameRoot = ""
)

$ErrorActionPreference = "Stop"
$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Resolve-GameRoot {
    param([string]$InputRoot)
    $candidates = @()
    if ($InputRoot) { $candidates += (Resolve-Path -LiteralPath $InputRoot).Path }
    $candidates += (Get-Location).Path
    $candidates += (Split-Path -Parent $PackageRoot)

    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath (Join-Path $candidate "Pathologic3.exe")) -and
            (Test-Path -LiteralPath (Join-Path $candidate "Pathologic3_Data"))) {
            return $candidate
        }
    }
    throw "Game root not found. Run: powershell -ExecutionPolicy Bypass -File .\install_patch.ps1 -GameRoot 'D:\...\Pathologic 3'"
}

function Copy-PayloadItem {
    param([string]$RelPath, [string]$TargetRoot, [string]$BackupRoot)
    $src = Join-Path $PackageRoot $RelPath
    $dst = Join-Path $TargetRoot $RelPath
    if (!(Test-Path -LiteralPath $src)) { return }
    if (Test-Path -LiteralPath $dst) {
        $backup = Join-Path $BackupRoot $RelPath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
        Copy-Item -LiteralPath $dst -Destination $backup -Recurse -Force
    }
    if (Test-Path -LiteralPath $src -PathType Container) {
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        Get-ChildItem -LiteralPath $src -Force | Copy-Item -Destination $dst -Recurse -Force
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}

$TargetRoot = Resolve-GameRoot $GameRoot
$TargetData = Join-Path $TargetRoot "Pathologic3_Data"
$BackupRoot = Join-Path $TargetRoot ("P3CN_Backups\cn_patch_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
$ReportDir = Join-Path $TargetRoot "P3CN_Reports"
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

$runtimePayload = @(
    "BepInEx\config\BepInEx.cfg",
    "BepInEx\core",
    "BepInEx\plugins\Pathologic3CnTagsFontSwap",
    ".doorstop_version",
    "doorstop_config.ini",
    "winhttp.dll"
)
foreach ($rel in $runtimePayload) { Copy-PayloadItem -RelPath $rel -TargetRoot $TargetRoot -BackupRoot $BackupRoot }

$manifestPath = Join-Path $PackageRoot "overlay_manifest.tsv"
$toolsDir = Join-Path $PackageRoot "tools\UABEA"
$assetStudioDir = Join-Path $PackageRoot "tools\AssetStudio"
$patcher = Join-Path $PackageRoot "tools\apply_manifest_to_resources_assets.ps1"
$chiantiFontPatcher = Join-Path $PackageRoot "tools\patch_chianti_fallback_to_notosanssc.ps1"
$resourcesFontPatcher = Join-Path $PackageRoot "tools\patch_resources_fallbacks_to_notosanssc.ps1"
& powershell -ExecutionPolicy Bypass -File $patcher `
    -ManifestPath $manifestPath `
    -GameDataDir $TargetData `
    -ToolsDir $toolsDir `
    -BackupRoot $BackupRoot `
    -ReportDir $ReportDir

& powershell -ExecutionPolicy Bypass -File $chiantiFontPatcher `
    -GameDataDir $TargetData `
    -UabeaDir $toolsDir `
    -AssetStudioDir $assetStudioDir `
    -BackupRoot $BackupRoot `
    -ReportDir $ReportDir

& powershell -ExecutionPolicy Bypass -File $resourcesFontPatcher `
    -GameDataDir $TargetData `
    -UabeaDir $toolsDir `
    -AssetStudioDir $assetStudioDir `
    -BackupRoot $BackupRoot `
    -ReportDir $ReportDir

Write-Host "Installed Pathologic 3 CN patch."
Write-Host "GameRoot: $TargetRoot"
Write-Host "Backup:   $BackupRoot"
Write-Host "Reports:  $ReportDir"
