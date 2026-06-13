$ErrorActionPreference = "Stop"

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-GameRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        return ((Test-Path -LiteralPath (Join-Path $Path "Pathologic3.exe")) -and
            (Test-Path -LiteralPath (Join-Path $Path "Pathologic3_Data")))
    }
    catch {
        return $false
    }
}

function Normalize-InputPath {
    param([string]$Path)
    if ($null -eq $Path) { return "" }
    return $Path.Trim().Trim('"')
}

function Find-GameRoot {
    $candidates = @(
        (Split-Path -Parent $PackageRoot),
        (Split-Path -Parent (Split-Path -Parent $PackageRoot)),
        "${env:ProgramFiles(x86)}\Steam\steamapps\common\Pathologic 3",
        "${env:ProgramFiles}\Steam\steamapps\common\Pathologic 3",
        "D:\SteamLibrary\steamapps\common\Pathologic 3",
        "E:\SteamLibrary\steamapps\common\Pathologic 3",
        "F:\SteamLibrary\steamapps\common\Pathologic 3"
    )

    foreach ($candidate in $candidates) {
        if (Test-GameRoot $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return ""
}

function Ask-GameRoot {
    while ($true) {
        Clear-Host
        Write-Host "Pathologic 3 CN Patch Uninstaller"
        Write-Host ""
        Write-Host "Game folder was not found automatically."
        Write-Host ""
        Write-Host "How to find it in Steam:"
        Write-Host "1. Right click Pathologic 3"
        Write-Host "2. Manage"
        Write-Host "3. Browse local files"
        Write-Host "4. Copy the opened folder path"
        Write-Host ""
        Write-Host "The correct folder contains:"
        Write-Host "  Pathologic3.exe"
        Write-Host "  Pathologic3_Data"
        Write-Host ""

        $inputPath = Normalize-InputPath (Read-Host "Paste game folder path here")
        if (Test-GameRoot $inputPath) {
            return (Resolve-Path -LiteralPath $inputPath).Path
        }

        Write-Host ""
        Write-Host "This is not a valid Pathologic 3 game folder:"
        Write-Host $inputPath
        Write-Host ""
        Read-Host "Press Enter to try again"
    }
}

function Find-OriginalBackup {
    param([string]$GameRoot)
    $backupDir = Join-Path $GameRoot "P3CN_Backups"
    if (!(Test-Path -LiteralPath $backupDir)) { return "" }

    $backup = Get-ChildItem -LiteralPath $backupDir -Directory -Filter "cn_patch_*" -ErrorAction SilentlyContinue |
        Sort-Object Name |
        Select-Object -First 1

    if ($backup) { return $backup.FullName }
    return ""
}

function Ask-BackupRoot {
    while ($true) {
        Clear-Host
        Write-Host "Pathologic 3 CN Patch Uninstaller"
        Write-Host ""
        Write-Host "No backup was found automatically."
        Write-Host ""
        Write-Host "Backup folders are usually under:"
        Write-Host "  Pathologic 3\P3CN_Backups\cn_patch_timestamp"
        Write-Host ""

        $inputPath = Normalize-InputPath (Read-Host "Paste backup folder path here")
        if (Test-Path -LiteralPath $inputPath) {
            return (Resolve-Path -LiteralPath $inputPath).Path
        }

        Write-Host ""
        Write-Host "Backup folder not found:"
        Write-Host $inputPath
        Write-Host ""
        Read-Host "Press Enter to try again"
    }
}

function Confirm-Uninstall {
    param([string]$GameRoot, [string]$BackupRoot)

    while ($true) {
        Clear-Host
        Write-Host "Pathologic 3 CN Patch Uninstaller"
        Write-Host ""
        Write-Host "Game folder:"
        Write-Host "  $GameRoot"
        Write-Host ""
        Write-Host "Backup to restore:"
        Write-Host "  $BackupRoot"
        Write-Host ""
        Write-Host "The uninstaller chooses the oldest backup by default."
        Write-Host "That is usually the original state before the first CN patch install."
        Write-Host ""
        Write-Host "Y = uninstall and restore this backup"
        Write-Host "N = choose another backup"
        Write-Host "C = cancel"
        Write-Host ""

        $answer = (Read-Host "Choose Y/N/C").Trim().ToUpperInvariant()
        if ($answer -eq "Y") { return "Uninstall" }
        if ($answer -eq "N") { return "ChooseBackup" }
        if ($answer -eq "C") { return "Cancel" }
    }
}

function Remove-PatchPayload {
    param([string]$GameRoot, [string]$BackupRoot)

    $items = @(
        "BepInEx\config\BepInEx.cfg",
        "BepInEx\core",
        "BepInEx\plugins\Pathologic3CnTagsFontSwap",
        ".doorstop_version",
        "doorstop_config.ini",
        "winhttp.dll"
    )

    foreach ($rel in $items) {
        $path = Join-Path $GameRoot $rel
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }

    $bepInExBackup = Join-Path $BackupRoot "BepInEx"
    $bepInExDir = Join-Path $GameRoot "BepInEx"
    if (!(Test-Path -LiteralPath $bepInExBackup) -and (Test-Path -LiteralPath $bepInExDir)) {
        Remove-Item -LiteralPath $bepInExDir -Recurse -Force
    }
}

function Remove-GeneratedArtifacts {
    param([string]$GameRoot)

    $fixedDirs = @(
        "P3CN_Reports",
        "P3CN_Backups"
    )

    foreach ($rel in $fixedDirs) {
        $path = Join-Path $GameRoot $rel
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }

    $patterns = @(
        "resources_assets_patch_*",
        "resources_font_fallback_patch_*",
        "sharedassets0_font_patch_*"
    )

    foreach ($pattern in $patterns) {
        Get-ChildItem -LiteralPath $GameRoot -Directory -Filter $pattern -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
    }

    foreach ($rel in @("BepInEx\config", "BepInEx\plugins", "BepInEx")) {
        $path = Join-Path $GameRoot $rel
        if ((Test-Path -LiteralPath $path) -and -not (Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

function Schedule-PackageFolderRemoval {
    param([string]$GameRoot)

    try {
        $packageDir = Split-Path -Parent $PackageRoot
        if (!(Test-Path -LiteralPath $packageDir)) { return }

        $resolvedPackageDir = (Resolve-Path -LiteralPath $packageDir).Path.TrimEnd("\")
        $resolvedGameRoot = (Resolve-Path -LiteralPath $GameRoot).Path.TrimEnd("\")
        $packageParent = (Split-Path -Parent $resolvedPackageDir).TrimEnd("\")
        if ($packageParent -ine $resolvedGameRoot) { return }

        $cleanupCmd = Join-Path $env:TEMP ("p3cn_cleanup_" + [guid]::NewGuid().ToString("N") + ".cmd")
        $lines = @(
            "@echo off",
            "timeout /t 3 /nobreak >nul 2>nul",
            "rmdir /s /q `"$resolvedPackageDir`" >nul 2>nul",
            "del `"%~f0`" >nul 2>nul"
        )
        [System.IO.File]::WriteAllLines($cleanupCmd, $lines, [System.Text.Encoding]::ASCII)
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$cleanupCmd`"" -WindowStyle Hidden
        Write-Host "Patch package folder will be removed after this window closes:"
        Write-Host "  $resolvedPackageDir"
    }
    catch {
        Write-Host "Could not schedule patch package folder cleanup:"
        Write-Host $_.Exception.Message
    }
}

try {
    $gameRoot = Find-GameRoot
    if (-not $gameRoot) {
        $gameRoot = Ask-GameRoot
    }

    $backupRoot = Find-OriginalBackup $gameRoot
    if (-not $backupRoot) {
        $backupRoot = Ask-BackupRoot
    }

    while ($true) {
        $decision = Confirm-Uninstall $gameRoot $backupRoot
        if ($decision -eq "Cancel") {
            Write-Host ""
            Write-Host "Cancelled. No files were changed."
            exit 0
        }
        if ($decision -eq "ChooseBackup") {
            $backupRoot = Ask-BackupRoot
            continue
        }
        break
    }

    Clear-Host
    Write-Host "Uninstalling..."
    Write-Host ""

    Remove-PatchPayload -GameRoot $gameRoot -BackupRoot $backupRoot
    & (Join-Path $PackageRoot "restore_from_backup.ps1") -BackupRoot $backupRoot -GameRoot $gameRoot
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "restore_from_backup.ps1 failed with exit code $LASTEXITCODE"
    }
    Remove-GeneratedArtifacts $gameRoot
    Schedule-PackageFolderRemoval $gameRoot

    Write-Host ""
    Write-Host "Uninstall finished."
    exit 0
}
catch {
    Write-Host ""
    Write-Host "Uninstall failed:"
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Please close the game and run this uninstaller again."
    exit 1
}
