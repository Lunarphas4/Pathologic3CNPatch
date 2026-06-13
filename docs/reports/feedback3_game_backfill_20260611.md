# feedback/3 回填游戏记录

时间：2026-06-11 19:24

## 回填目标

- Overlay：`D:\Pathologic3_CN_Work\09_patch_work\overlay_cn_textassets_20260422`
- 游戏副本：`D:\Pathologic3_CN_Work\Pathologic 3`
- 写入文件：`D:\Pathologic3_CN_Work\Pathologic 3\Pathologic3_Data\resources.assets`

## 执行结果

使用 `02_tools/apply_overlay_to_resources_assets.ps1` 按 ResourceManager 路径精确写回。

- overlay_files = 9340
- mapped_to_pathid = 9340
- replacers_written = 43
- already_matched_skipped = 9297
- unmapped_overlay = 0
- pathids_missing_after_pass = 0
- backup_dir = `D:\Pathologic3_CN_Work\09_patch_work\game_file_backups\resources_assets_patch_20260611_192029`

## 验证结果

使用 `02_tools/verify_resources_assets_overlay.ps1` 验证。

- exact_matches = 9340
- mismatched_instances = 0
- pathids_missing_in_resources = 0

## 新补丁包

- package_dir = `D:\Pathologic3_CN_Work\10_release_packages\Pathologic3_CN_Patch_20260611_192446`
- zip_path = `D:\Pathologic3_CN_Work\10_release_packages\Pathologic3_CN_Patch_20260611_192446.zip`
- files = 36
- zip_size = 447196866 bytes

本轮未启动游戏做画面验证。
