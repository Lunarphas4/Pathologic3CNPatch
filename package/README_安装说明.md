# Pathologic 3 中文补丁安装说明

包名: `Pathologic3CNpatch`

## 最简单安装方法

1. 先退出游戏。
2. 解压这个补丁压缩包。
3. 打开解压出来的文件夹。
4. 双击 `一键安装中文补丁.bat`。
5. 确认 `Game folder` 是 Pathologic 3 游戏目录，输入 `Y` 安装。
6. 如果地址不对，输入 `N` 后粘贴正确目录。

## 本版内容

更新日期: 2026-06-13。包含 feedback/3 未修改项补改、Khulan 统一为 库兰、病人名和草原语补注统一。

- 当前中文文本 manifest。
- 字体方块修复流程。
- `Pathologic3CnTagsFontSwap` 0.8.11：已修复按 Q 聚焦卡顿热路径。
- BepInEx 启动所需文件。

## 版权安全说明

本补丁不包含完整游戏资源文件，不包含：

```text
Pathologic3_Data/resources.assets
Pathologic3_Data/sharedassets*.assets
Pathologic3_Data/*.resS
```

安装器会读取玩家本机已有的游戏文件，并把中文文本和字体修复写入本机副本。

## 怎么找到游戏安装文件夹

Steam 版：右键 `Pathologic 3` -> “管理” -> “浏览本地文件”。

正确目录里应该能看到：

```text
Pathologic3.exe
Pathologic3_Data
```

## 备用 PowerShell 安装方式

```powershell
powershell -ExecutionPolicy Bypass -File .\patch_files\install_patch.ps1
```

如果补丁文件夹不在游戏目录里，请改用：

```powershell
powershell -ExecutionPolicy Bypass -File .\patch_files\install_patch.ps1 -GameRoot "your game folder path"
```

## 卸载补丁

安装时会自动备份被修改或覆盖的文件，备份位置类似：

```text
Pathologic 3\P3CN_Backups\cn_patch_timestamp
```

最简单卸载方法：

1. 先退出游戏。
2. 双击 `一键卸载中文补丁.bat`。
3. 确认游戏目录和要恢复的备份，输入 `Y` 卸载。

卸载器会默认选择最早的 `P3CN_Backups\cn_patch_*` 备份，也就是第一次安装中文补丁前的状态。卸载成功后会恢复被修改的游戏资源，并清理补丁生成的备份、报告和临时目录。若补丁包解压在游戏目录里，卸载窗口关闭后也会删除补丁包文件夹。

备用 PowerShell 卸载方式：

```powershell
powershell -ExecutionPolicy Bypass -File .\patch_files\restore_from_backup.ps1 -BackupRoot "your backup folder path"
```

如果找不到备份，也可以在 Steam 里验证游戏文件完整性来恢复官方文件。
