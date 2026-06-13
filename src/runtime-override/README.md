# Pathologic3 CN Runtime Override

This plugin is a validation tool for rough translation injection.

Goal:

- override `Localizations.LocalizationService.GetText(string tag)` at runtime
- load translated values from a local TSV
- verify that rough Chinese text can appear correctly in-game before final packaging

Current translation TSV search order:

1. `Pathologic 3\\BepInEx\\plugins\\Pathologic3CnRuntimeOverride\\overrides.tsv`
2. `..\\05_day1_text\\17_batch1_opening_translation_draft.tsv`

Current intended validation source:

- `D:\Pathologic3_CN_Work\05_day1_text\17_batch1_opening_translation_draft.tsv`
