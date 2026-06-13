from __future__ import annotations

import hashlib
import shutil
import sys
import zipfile
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GAME_ROOT = ROOT / "Pathologic 3"
GAME_DATA = GAME_ROOT / "Pathologic3_Data"
OUT_ROOT = ROOT / "10_release_packages"


def copy_file(src: Path, dst: Path) -> None:
    if not src.is_file():
        raise FileNotFoundError(src)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def copy_tree(src: Path, dst: Path) -> None:
    if not src.is_dir():
        raise FileNotFoundError(src)
    for item in src.rglob("*"):
        if item.is_file():
            copy_file(item, dst / item.relative_to(src))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def make_install_script() -> str:
    return r'''param(
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

$TargetRoot = Resolve-GameRoot $GameRoot
$BackupRoot = Join-Path $TargetRoot ("P3CN_Backups\cn_patch_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

$payload = @(
    "Pathologic3_Data\resources.assets",
    "Pathologic3_Data\sharedassets0.assets",
    "Pathologic3_Data\sharedassets0.assets.resS",
    "BepInEx\config\BepInEx.cfg",
    "BepInEx\core",
    "BepInEx\plugins\Pathologic3CnTagsFontSwap",
    ".doorstop_version",
    "doorstop_config.ini",
    "winhttp.dll"
)

foreach ($rel in $payload) {
    $src = Join-Path $PackageRoot $rel
    $dst = Join-Path $TargetRoot $rel
    if (!(Test-Path -LiteralPath $src)) { continue }

    if (Test-Path -LiteralPath $dst) {
        $backup = Join-Path $BackupRoot $rel
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

Write-Host "Installed Pathologic 3 CN patch."
Write-Host "GameRoot: $TargetRoot"
Write-Host "Backup:   $BackupRoot"
'''


def make_restore_script() -> str:
    return r'''param(
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

Get-ChildItem -LiteralPath $BackupRoot -Force | Copy-Item -Destination $GameRoot -Recurse -Force
Write-Host "Restored backup."
Write-Host "GameRoot: $GameRoot"
Write-Host "Backup:   $BackupRoot"
'''


def make_readme(name: str) -> str:
    return f"""# Pathologic 3 中文补丁安装说明

包名：`{name}`

## 最简单安装方法

1. 先退出游戏。
2. 打开你的游戏安装文件夹。
   - 这个文件夹里应该能看到 `Pathologic3.exe`。
3. 把本补丁压缩包里的所有文件，解压到游戏安装文件夹里。
   - 如果系统提示“是否替换文件”，选“替换”。
4. 在游戏安装文件夹的空白处按住 Shift，再点鼠标右键。
5. 选择“在此处打开 PowerShell 窗口”。
6. 复制下面这一行，粘贴进去，按回车：

```powershell
powershell -ExecutionPolicy Bypass -File .\\install_patch.ps1
```

7. 看到 `Installed Pathologic 3 CN patch.` 就安装完成。
8. 启动游戏，在设置里选择简体中文。

## 如果第 6 步失败

大概率是你没有在游戏安装文件夹里打开 PowerShell。

请确认当前文件夹里能看到：

```text
Pathologic3.exe
Pathologic3_Data
install_patch.ps1
```

然后重新运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\\install_patch.ps1
```

## Steam 版常见位置

如果你不知道游戏在哪里，可以在 Steam 里这样找：

1. 右键游戏。
2. 点“管理”。
3. 点“浏览本地文件”。

打开的那个文件夹就是游戏安装文件夹。

## 卸载补丁

安装时会自动备份被覆盖的文件，备份位置类似：

```text
Pathologic 3\\P3CN_Backups\\cn_patch_20260602_154633
```

要卸载时，在游戏安装文件夹打开 PowerShell，然后运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\\restore_from_backup.ps1 -BackupRoot ".\\P3CN_Backups\\cn_patch_你的备份时间"
```

把 `cn_patch_你的备份时间` 换成你电脑里实际看到的备份文件夹名。

## 本补丁包含

- 游戏中文文本。
- 中文字体资产。
- 修正悬浮文字和部分标签文字显示的字体插件。
- BepInEx 启动所需文件。
"""


def main() -> int:
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    name = f"Pathologic3_CN_Patch_{stamp}"
    package_dir = OUT_ROOT / name
    zip_path = OUT_ROOT / f"{name}.zip"

    if package_dir.exists() or zip_path.exists():
        raise FileExistsError(name)

    package_dir.mkdir(parents=True)

    for filename in ("resources.assets", "sharedassets0.assets", "sharedassets0.assets.resS"):
        copy_file(GAME_DATA / filename, package_dir / "Pathologic3_Data" / filename)

    for filename in (".doorstop_version", "doorstop_config.ini", "winhttp.dll"):
        copy_file(GAME_ROOT / filename, package_dir / filename)

    copy_tree(GAME_ROOT / "BepInEx" / "core", package_dir / "BepInEx" / "core")
    copy_file(GAME_ROOT / "BepInEx" / "config" / "BepInEx.cfg", package_dir / "BepInEx" / "config" / "BepInEx.cfg")
    copy_tree(
        GAME_ROOT / "BepInEx" / "plugins" / "Pathologic3CnTagsFontSwap",
        package_dir / "BepInEx" / "plugins" / "Pathologic3CnTagsFontSwap",
    )

    evidence_dir = package_dir / "evidence"
    for report in (
        "60_resources_assets_patch_report.md",
        "62_resources_assets_overlay_verification.md",
        "290_localization_quality_report.md",
        "292_urgent_localization_fix_bilingual_review.md",
        "293_urgent_localization_fixes_applied.tsv",
    ):
        src = ROOT / "00_codex_reports" / report
        if src.exists():
            copy_file(src, evidence_dir / report)

    write_text(package_dir / "install_patch.ps1", make_install_script())
    write_text(package_dir / "restore_from_backup.ps1", make_restore_script())
    write_text(package_dir / "README_安装说明.md", make_readme(name))

    checksum_lines = []
    for path in sorted(p for p in package_dir.rglob("*") if p.is_file()):
        rel = path.relative_to(package_dir).as_posix()
        checksum_lines.append(f"{sha256_file(path)}  {rel}")
    write_text(package_dir / "SHA256SUMS.txt", "\n".join(checksum_lines) + "\n")

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for path in sorted(p for p in package_dir.rglob("*") if p.is_file()):
            zf.write(path, arcname=f"{name}/{path.relative_to(package_dir).as_posix()}")

    print(f"PACKAGE_DIR={package_dir}")
    print(f"ZIP_PATH={zip_path}")
    print(f"FILES={sum(1 for p in package_dir.rglob('*') if p.is_file())}")
    print(f"ZIP_SIZE={zip_path.stat().st_size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
