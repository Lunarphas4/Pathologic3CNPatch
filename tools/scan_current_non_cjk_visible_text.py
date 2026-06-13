from __future__ import annotations

import argparse
import csv
import re
from collections import Counter
from pathlib import Path


WORKSPACE = Path(r"D:\Pathologic3_CN_Work")
OVERLAY_ROOT = WORKSPACE / "09_patch_work" / "overlay_cn_textassets_20260422"
REPORT_DIR = WORKSPACE / "00_codex_reports"

LINE_RE = re.compile(r"^\ufeff?\{([^}]+)\}\s?(.*)$")
CJK_RE = re.compile(r"[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]")
LATIN_RE = re.compile(r"[A-Za-z]")
CYRILLIC_RE = re.compile(r"[\u0400-\u04FF]")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--index", type=int, required=True)
    return parser.parse_args()


def is_credit_path(rel_path: str) -> bool:
    lower = rel_path.lower()
    return any(token in lower for token in ("credit", "credits", "aftercredits", "postcredits"))


def classify_text(rel_path: str, text: str) -> str | None:
    has_cjk = bool(CJK_RE.search(text))
    has_latin = bool(LATIN_RE.search(text))
    has_cyrillic = bool(CYRILLIC_RE.search(text))
    has_qmark = "?" in text

    if is_credit_path(rel_path) and (has_latin or has_cjk or has_qmark):
        return "credits"
    if has_cyrillic:
        return "cyrillic"
    if has_latin and has_cjk:
        return "mixed_latin_cjk"
    if has_latin:
        return "latin_no_cjk"
    if has_qmark and not has_cjk:
        return "latin_no_cjk"
    return None


def main() -> None:
    args = parse_args()
    scan_path = REPORT_DIR / f"{args.index}_current_non_cjk_visible_text_scan.tsv"
    report_path = REPORT_DIR / f"{args.index}_current_non_cjk_visible_text_scan_report.md"

    rows: list[dict[str, str]] = []
    cn_placeholders = 0

    for path in sorted(OVERLAY_ROOT.rglob("*.txt")):
        rel_path = path.relative_to(OVERLAY_ROOT).as_posix()
        root = rel_path.split("/", 1)[0]
        for line_no, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            match = LINE_RE.match(raw_line)
            if not match:
                continue
            asset_key, text = match.group(1), match.group(2)
            if "[CN]" in text:
                cn_placeholders += 1
            text = text.strip()
            if not text:
                continue
            category = classify_text(rel_path, text)
            if category is None:
                continue
            rows.append(
                {
                    "root": root,
                    "category": category,
                    "file": rel_path,
                    "line_no": str(line_no),
                    "asset_key": asset_key,
                    "text": text,
                }
            )

    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    with scan_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["root", "category", "file", "line_no", "asset_key", "text"],
            delimiter="\t",
        )
        writer.writeheader()
        writer.writerows(rows)

    root_category_counts = Counter((row["root"], row["category"]) for row in rows)
    total_rows = len(rows)
    non_credit_rows = sum(1 for row in rows if row["category"] != "credits")
    pure_untranslated = sum(1 for row in rows if row["category"] in {"cyrillic", "latin_no_cjk"})

    report_lines = [
        "# Current Non-CJK Visible Text Scan",
        "",
        f"- scan_path = {scan_path}",
        f"- cn_placeholders = {cn_placeholders}",
        f"- total_non_cjk_rows = {total_rows}",
        f"- non_credit_rows = {non_credit_rows}",
        f"- pure_untranslated_candidates = {pure_untranslated}",
        "",
        "## Root/category counts",
        "",
        "| count | root, category |",
        "|---:|---|",
    ]
    for (root, category), count in sorted(root_category_counts.items(), key=lambda item: (-item[1], item[0][0], item[0][1])):
        report_lines.append(f"| {count} | {root}, {category} |")

    report_path.write_text("\n".join(report_lines) + "\n", encoding="utf-8")

    print(f"scan_path={scan_path}")
    print(f"report_path={report_path}")
    print(f"cn_placeholders={cn_placeholders}")
    print(f"total_non_cjk_rows={total_rows}")
    print(f"non_credit_rows={non_credit_rows}")
    print(f"pure_untranslated_candidates={pure_untranslated}")


if __name__ == "__main__":
    main()
