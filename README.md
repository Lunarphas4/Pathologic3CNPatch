# Pathologic 3 简体中文补丁

Pathologic 3 简体中文本地化补丁工程仓库。补丁非官方、非商业、无盈利。

本仓库用于维护源码、脚本、术语表、翻译 overlay 和报告文档；玩家实际安装请下载 GitHub Release 中的压缩包。

## 发布许可

<img width="1199" height="3275" alt="Screenshot_2026-06-13-15-42-32-937_com discord_17" src="https://github.com/user-attachments/assets/0257b2fb-f291-4505-b558-c7993e572f6b" />

## 下载方式

请到本仓库右侧或顶部的 **Releases** 页面下载最新版本：

- 玩家安装包：`Pathologic3CNpatch.zip`
- 解压后双击：`一键安装中文补丁.bat`
- 需要卸载时双击：`一键卸载中文补丁.bat`

不要直接下载 GitHub 页面上的源码 zip 作为玩家补丁。源码 zip 不包含完整的可安装补丁文件。

## 安装方式

1. 退出游戏。
2. 下载 Release 里的 `Pathologic3CNpatch.zip`。
3. 解压压缩包。
4. 打开 `Pathologic3CNpatch` 文件夹。
5. 双击 `一键安装中文补丁.bat`。
6. 按窗口提示确认 Pathologic 3 游戏目录，输入 `Y` 安装。

如果安装器没有自动找到游戏目录：

1. 在 Steam 中右键 `Pathologic 3`。
2. 选择“管理” -> “浏览本地文件”。
3. 复制打开的文件夹路径。
4. 粘贴到安装器窗口。

## 当前版本

- 当前整理版本：`2026-06-13`
- 补丁目录名：`Pathologic3CNpatch`

## 卸载方式

1. 退出游戏。
2. 打开补丁文件夹。
3. 双击 `一键卸载中文补丁.bat`。
4. 确认游戏目录和备份目录，输入 `Y` 卸载。

卸载器默认选择最早的 `P3CN_Backups\cn_patch_*` 备份，也就是第一次安装中文补丁前的状态。卸载成功后会清理补丁生成的备份、报告和临时目录。

如果备份已经被删除，请在 Steam 中使用“验证游戏文件完整性”恢复原版资源。

## 仓库内容

- `src/`：BepInEx 插件源码。
- `tools/`：当前维护需要的核心抽取、写回、校验和打包脚本。
- `localization/overlay_cn_textassets/`：当前简体中文 overlay 文本资产树。
- `localization/glossary/`：术语表、风险句、角色语气和用户术语覆盖。
- `docs/`：当前状态、反馈处理记录和关键校验报告。
- `package/`：可安装补丁的说明与入口脚本示例。

