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
        $PackageRoot,
        (Split-Path -Parent $PackageRoot),
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
        Write-Host "Pathologic 3 CN Patch Installer"
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

function Confirm-Install {
    param([string]$GameRoot)

    while ($true) {
        Clear-Host
        Write-Host "Pathologic 3 CN Patch Installer"
        Write-Host ""
        Write-Host "Patch folder:"
        Write-Host "  $PackageRoot"
        Write-Host ""
        Write-Host "Game folder:"
        Write-Host "  $GameRoot"
        Write-Host ""
        Write-Host "The patch will be installed into the Game folder above."
        Write-Host ""
        Write-Host "Y = install"
        Write-Host "N = choose another game folder"
        Write-Host "C = cancel"
        Write-Host ""

        $answer = (Read-Host "Choose Y/N/C").Trim().ToUpperInvariant()
        if ($answer -eq "Y") { return "Install" }
        if ($answer -eq "N") { return "ChooseAgain" }
        if ($answer -eq "C") { return "Cancel" }
    }
}

try {
    $gameRoot = Find-GameRoot
    if (-not $gameRoot) {
        $gameRoot = Ask-GameRoot
    }

    while ($true) {
        $decision = Confirm-Install $gameRoot
        if ($decision -eq "Cancel") {
            Write-Host ""
            Write-Host "Cancelled. No files were changed."
            exit 0
        }
        if ($decision -eq "ChooseAgain") {
            $gameRoot = Ask-GameRoot
            continue
        }
        break
    }

    Clear-Host
    Write-Host "Installing..."
    Write-Host ""

    & (Join-Path $PackageRoot "install_patch.ps1") -GameRoot $gameRoot
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "install_patch.ps1 failed with exit code $LASTEXITCODE"
    }

    Write-Host ""
    Write-Host "Install finished."
    Write-Host "Start the game and choose Simplified Chinese in settings."
    exit 0
}
catch {
    Write-Host ""
    Write-Host "Install failed:"
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Please close the game and run this installer again."
    exit 1
}
