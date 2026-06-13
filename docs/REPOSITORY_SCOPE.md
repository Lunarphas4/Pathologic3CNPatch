# 仓库整理范围

此目录由 `D:\Pathologic3_CN_Work` 整理而来，目标是形成可以直接上传 GitHub 的维护仓库。

## 已复制

- 自有脚本：`02_tools` 根目录下的 `.ps1` 和 `.py` 文件。
- 插件源码：`09_runtime_override`、`09_runtime_tagsfont`，已排除 `bin/` 和 `obj/`。
- 文本资产：`09_patch_work/overlay_cn_textassets_20260422`。
- 术语和翻译工作表：`06_glossary`、`05_day1_text`。
- 文档：`docs/handoff.md`、`docs/work_in_progress.md` 和少量关键报告。

## 已排除

- 游戏本体、游戏副本、Unity 资源包和 AssetRipper 导出树。
- 第三方工具目录和第三方二进制文件。
- 发布包、压缩包、构建输出。
- 过程备份和历史大文件。

## 注意

`localization/translation_batches/` 与 `localization/overlay_cn_textassets/` 可能包含来自游戏文本的工作材料。若仓库计划公开发布，请先确认公开范围和授权边界；如果只想公开工具链源码，可移除 `localization/` 后再上传。
