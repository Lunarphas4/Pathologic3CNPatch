param(
    [Parameter(Mandatory=$true)][string]$BackupRoot,
    [string]$GameRoot = ""
)

$ErrorActionPreference = "Stop"

if (!$GameRoot) {
    $GameRoot = Split-Path -Parent (Split-Path -Parent $BackupRoot)
}

if (!(Test-Path -LiteralPath $BackupRoot)) {
    throw "BackupRoot not found: $BackupRoot"
}
if (!(Test-Path -LiteralPath (Join-Path $GameRoot "Pathologic3.exe"))) {
    throw "GameRoot not found or invalid: $GameRoot"
}

function Copy-BackupTreeToGameRoot {
    param([string]$SourceRoot, [string]$TargetRoot)

    $assetBackupNames = @(
        "resources_assets_patch_*",
        "resources_font_fallback_patch_*",
        "sharedassets0_font_patch_*"
    )

    foreach ($child in Get-ChildItem -LiteralPath $SourceRoot -Force) {
        $isAssetBackup = $false
        foreach ($pattern in $assetBackupNames) {
            if ($child.Name -like $pattern) {
                $isAssetBackup = $true
                break
            }
        }
        if ($isAssetBackup) { continue }

        $dst = Join-Path $TargetRoot $child.Name
        Copy-Item -LiteralPath $child.FullName -Destination $dst -Recurse -Force
    }
}

function Restore-AssetFiles {
    param(
        [string]$BackupRoot,
        [string]$GameDataDir,
        [string]$PreferredPattern,
        [string]$FallbackPattern,
        [string[]]$FileNames,
        [switch]$RequirePrimary
    )

    $backupDir = Get-ChildItem -LiteralPath $BackupRoot -Directory -Filter $PreferredPattern -ErrorAction SilentlyContinue |
        Sort-Object Name |
        Select-Object -First 1

    if (($null -eq $backupDir) -and $FallbackPattern) {
        $backupDir = Get-ChildItem -LiteralPath $BackupRoot -Directory -Filter $FallbackPattern -ErrorAction SilentlyContinue |
            Sort-Object Name |
            Select-Object -First 1
    }

    if ($null -eq $backupDir) {
        if ($RequirePrimary) {
            throw "Required asset backup folder not found: $PreferredPattern"
        }
        return
    }

    foreach ($name in $FileNames) {
        $src = Join-Path $backupDir.FullName $name
        $dst = Join-Path $GameDataDir $name
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination $dst -Force
            $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
            $dstHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
            if ($srcHash -ne $dstHash) {
                throw "Restore verification failed for $name"
            }
        }
        elseif ($RequirePrimary -and $name -eq $FileNames[0]) {
            throw "Required asset backup file not found: $src"
        }
    }
}

$GameDataDir = Join-Path $GameRoot "Pathologic3_Data"
if (!(Test-Path -LiteralPath $GameDataDir)) {
    throw "Game data folder not found: $GameDataDir"
}

Copy-BackupTreeToGameRoot -SourceRoot $BackupRoot -TargetRoot $GameRoot
Restore-AssetFiles -BackupRoot $BackupRoot -GameDataDir $GameDataDir -PreferredPattern "resources_assets_patch_*" -FallbackPattern "resources_font_fallback_patch_*" -FileNames @("resources.assets", "resources.assets.resS") -RequirePrimary
Restore-AssetFiles -BackupRoot $BackupRoot -GameDataDir $GameDataDir -PreferredPattern "sharedassets0_font_patch_*" -FallbackPattern "" -FileNames @("sharedassets0.assets", "sharedassets0.assets.resS")

Write-Host "Restored backup."
Write-Host "GameRoot: $GameRoot"
Write-Host "Backup:   $BackupRoot"
