from __future__ import annotations

import csv
import re
from collections import Counter
from datetime import datetime
from pathlib import Path


WORKSPACE = Path(r"D:\Pathologic3_CN_Work")
OVERLAY_ROOT = WORKSPACE / "09_patch_work" / "overlay_cn_textassets_20260422"
SOURCE_ROOT = (
    WORKSPACE
    / "08_assetripper_export"
    / "full_export_20260421"
    / "ExportedProject"
    / "Assets"
    / "Resources"
)
VIDEO_ROOT = WORKSPACE / "Pathologic 3" / "Pathologic3_Data" / "StreamingAssets" / "Videos"
REPORT_DIR = WORKSPACE / "00_codex_reports"

REPORT_INDEX = 282
ISSUE_TSV = REPORT_DIR / f"{REPORT_INDEX}_ending_text_check.tsv"
MISSING_TSV = REPORT_DIR / f"{REPORT_INDEX}_ending_source_missing_overlay.tsv"
VIDEO_TSV = REPORT_DIR / f"{REPORT_INDEX}_ending_video_inventory.tsv"
SUMMARY_MD = REPORT_DIR / f"{REPORT_INDEX}_ending_text_check_report.md"

LINE_RE = re.compile(r"^\ufeff?\{([^}]+)\}\s?(.*)$")
CJK_RE = re.compile(r"[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]")
LATIN_RE = re.compile(r"[A-Za-z]")
CYRILLIC_RE = re.compile(r"[\u0400-\u04FF]")
MOJIBAKE_MARKERS = (
    "\ufffd",
    "\u9521",
    "\u00c3",
    "\u00c2",
    "\u00d0",
    "\u00d1",
    "\u9205",
    "\u923b",
    "\u93b4",
    "\u9435",
    "\u6d93",
    "\u6d60",
    "\u7d1d",
    "\u9291",
    "\u951b",
    "\u7019",
    "\u75c9",
)
INVISIBLE_ONLY_RE = re.compile(r"^[\s\u200b\u200c\u200d\u2060\ufeff]+$")

ENDING_PATH_TOKENS = (
    "/day12/",
    "/day10/day10_q17_escape_ending/",
    "/day10_q17_escape_ending/",
    "day12_q3_youknownothing_ending",
    "day12_q3.1_youdidnothing_ending",
    "day12_q4_aglayahasalreadywon",
    "day12_q5_beforethefinals",
    "day12_q6_rot_ending",
    "day12_q7_savingofpolyhedron",
    "day12_q8_immortality_ending",
    "day12_q9_priceofmiracle_ending",
    "day12_q10_destroyingofpolyhedron",
    "day12_q11_miracleseeker_ending",
    "day12_q12_academician_ending",
    "day12_q13_bullatthepolyhedron",
    "day12_q14_cursedstreet_ending",
    "day12_q15_mybranchiscalled",
    "day12_q16_visitingpolyhedron",
    "day12_q17_aftertheend",
    "day12_q18_ratwatson",
    "day12_q19_secretroom",
)

ENDING_KEY_TOKENS = (
    ".Day12.",
    ".Day10_Q17_Escape_Ending.",
    "Day12_Q3_YouKnowNothing_Ending",
    "Day12_Q3.1_YouDidNothing_Ending",
    "Day12_Q4_AglayaHasAlreadyWon",
    "Day12_Q5_BeforeTheFinals",
    "Day12_Q6_Rot_Ending",
    "Day12_Q7_SavingOfPolyhedron",
    "Day12_Q8_Immortality_Ending",
    "Day12_Q9_PriceOfMiracle_Ending",
    "Day12_Q10_DestroyingOfPolyhedron",
    "Day12_Q11_MiracleSeeker_Ending",
    "Day12_Q12_Academician_Ending",
    "Day12_Q13_BullAtThePolyhedron",
    "Day12_Q14_CursedStreet_Ending",
    "Day12_Q15_MyBranchIsCalled",
    "Day12_Q16_VisitingPolyhedron",
    "Day12_Q17_AfterTheEnd",
    "Day12_Q18_RatWatson",
    "Day12_Q19_SecretRoom",
)


def read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8-sig").splitlines()


def rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def is_ending_path(rel_path: str) -> bool:
    lower = "/" + rel_path.replace("\\", "/").lower()
    return any(token in lower for token in ENDING_PATH_TOKENS)


def is_ending_key(asset_key: str) -> bool:
    return any(token in asset_key for token in ENDING_KEY_TOKENS)


def parse_text_file(path: Path, root: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    rel_path = rel(path, root)
    for line_no, raw_line in enumerate(read_lines(path), 1):
        match = LINE_RE.match(raw_line)
        if not match:
            continue
        asset_key, text = match.group(1), match.group(2)
        if not (is_ending_path(rel_path) or is_ending_key(asset_key)):
            continue
        rows.append(
            {
                "file": rel_path,
                "line_no": str(line_no),
                "asset_key": asset_key,
                "text": text,
            }
        )
    return rows


def recover_gbk_mojibake(text: str) -> str | None:
    try:
        recovered = text.encode("gbk").decode("utf-8")
    except UnicodeError:
        return None
    if recovered != text and CJK_RE.search(recovered):
        return recovered
    return None


def classify_issue(text: str) -> str | None:
    stripped = text.strip()
    has_cjk = bool(CJK_RE.search(text))
    has_latin = bool(LATIN_RE.search(text))
    has_cyrillic = bool(CYRILLIC_RE.search(text))

    if text == "":
        return "empty_text"
    if stripped == "" or INVISIBLE_ONLY_RE.match(text):
        return "invisible_or_whitespace_only"
    if "[CN]" in text:
        return "cn_placeholder"
    if any(marker in text for marker in MOJIBAKE_MARKERS) or recover_gbk_mojibake(text):
        return "mojibake_candidate"
    if has_cyrillic:
        return "cyrillic_leftover"
    if has_latin and not has_cjk:
        return "latin_no_cjk"
    if has_latin and has_cjk:
        return "mixed_latin_cjk"
    if "?" in text and not has_cjk:
        return "question_no_cjk"
    return None


def scan_overlay() -> tuple[list[dict[str, str]], dict[str, dict[str, str]], Counter]:
    issue_rows: list[dict[str, str]] = []
    overlay_by_key: dict[str, dict[str, str]] = {}
    file_counter: Counter = Counter()

    for path in sorted(OVERLAY_ROOT.rglob("*_Chinese_Simplified.txt")):
        file_rows = parse_text_file(path, OVERLAY_ROOT)
        if not file_rows:
            continue
        file_counter["ending_overlay_files"] += 1
        for row in file_rows:
            overlay_by_key[row["asset_key"]] = row
            file_counter["ending_overlay_lines"] += 1
            issue = classify_issue(row["text"])
            if issue is None:
                continue
            issue_rows.append(
                {
                    "issue": issue,
                    "file": row["file"],
                    "line_no": row["line_no"],
                    "asset_key": row["asset_key"],
                    "text": row["text"].strip(),
                    "recovered_text": recover_gbk_mojibake(row["text"].strip()) or "",
                }
            )
    return issue_rows, overlay_by_key, file_counter


def scan_source_missing(overlay_by_key: dict[str, dict[str, str]]) -> tuple[list[dict[str, str]], Counter]:
    missing_rows: list[dict[str, str]] = []
    counters: Counter = Counter()

    for path in sorted(SOURCE_ROOT.rglob("*_English.txt")):
        file_rows = parse_text_file(path, SOURCE_ROOT)
        if not file_rows:
            continue
        counters["ending_source_files"] += 1
        for row in file_rows:
            counters["ending_source_lines"] += 1
            if row["asset_key"] in overlay_by_key:
                counters["source_keys_found_in_overlay"] += 1
                continue
            counters["source_keys_missing_overlay"] += 1
            missing_rows.append(
                {
                    "file": row["file"],
                    "line_no": row["line_no"],
                    "asset_key": row["asset_key"],
                    "english_text": row["text"].strip(),
                }
            )
    return missing_rows, counters


def scan_videos() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for path in sorted(VIDEO_ROOT.glob("cutscene_Final_*.webm")):
        stat = path.stat()
        rows.append(
            {
                "file": rel(path, VIDEO_ROOT),
                "bytes": str(stat.st_size),
                "mb": f"{stat.st_size / 1024 / 1024:.1f}",
                "last_write_time": datetime.fromtimestamp(stat.st_mtime).isoformat(timespec="seconds"),
            }
        )
    return rows


def write_tsv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def write_summary(
    issue_rows: list[dict[str, str]],
    missing_rows: list[dict[str, str]],
    video_rows: list[dict[str, str]],
    overlay_counts: Counter,
    source_counts: Counter,
) -> None:
    issue_counts = Counter(row["issue"] for row in issue_rows)
    issue_file_counts = Counter(row["file"] for row in issue_rows)
    missing_file_counts = Counter(row["file"] for row in missing_rows)

    lines = [
        "# Ending Text Check",
        "",
        f"- generated_at = {datetime.now().isoformat(timespec='seconds')}",
        f"- overlay_root = {OVERLAY_ROOT}",
        f"- source_root = {SOURCE_ROOT}",
        f"- video_root = {VIDEO_ROOT}",
        f"- issue_tsv = {ISSUE_TSV}",
        f"- missing_overlay_tsv = {MISSING_TSV}",
        f"- video_tsv = {VIDEO_TSV}",
        "",
        "## Scope",
        "",
        "This scan is read-only. It checks ending-related localized TextAsset rows and the final cutscene video inventory.",
        "It does not prove quest trigger correctness or in-game layout/font behavior.",
        "",
        "## Totals",
        "",
        f"- ending_video_files = {len(video_rows)}",
        f"- ending_overlay_files = {overlay_counts['ending_overlay_files']}",
        f"- ending_overlay_lines = {overlay_counts['ending_overlay_lines']}",
        f"- ending_source_files = {source_counts['ending_source_files']}",
        f"- ending_source_lines = {source_counts['ending_source_lines']}",
        f"- source_keys_found_in_overlay = {source_counts['source_keys_found_in_overlay']}",
        f"- source_keys_missing_overlay = {source_counts['source_keys_missing_overlay']}",
        f"- issue_rows = {len(issue_rows)}",
        "",
        "## Issue Counts",
        "",
        "| count | issue |",
        "|---:|---|",
    ]
    for issue, count in issue_counts.most_common():
        lines.append(f"| {count} | {issue} |")

    lines.extend(["", "## Top Issue Files", "", "| count | file |", "|---:|---|"])
    for file, count in issue_file_counts.most_common(20):
        lines.append(f"| {count} | `{file}` |")

    lines.extend(["", "## Top Missing Overlay Source Files", "", "| count | source file |", "|---:|---|"])
    for file, count in missing_file_counts.most_common(20):
        lines.append(f"| {count} | `{file}` |")

    lines.extend(["", "## Video Inventory", "", "| MB | file |", "|---:|---|"])
    for row in video_rows:
        lines.append(f"| {row['mb']} | `{row['file']}` |")

    lines.extend(["", "## First 30 Issues", "", "| issue | file:line | asset key | text |", "|---|---|---|---|"])
    for row in issue_rows[:30]:
        text = (row.get("recovered_text") or row["text"]).replace("|", "\\|")
        if len(text) > 120:
            text = text[:117] + "..."
        lines.append(f"| {row['issue']} | `{row['file']}:{row['line_no']}` | `{row['asset_key']}` | {text} |")

    SUMMARY_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    issue_rows, overlay_by_key, overlay_counts = scan_overlay()
    missing_rows, source_counts = scan_source_missing(overlay_by_key)
    video_rows = scan_videos()

    write_tsv(ISSUE_TSV, ["issue", "file", "line_no", "asset_key", "text", "recovered_text"], issue_rows)
    write_tsv(MISSING_TSV, ["file", "line_no", "asset_key", "english_text"], missing_rows)
    write_tsv(VIDEO_TSV, ["file", "bytes", "mb", "last_write_time"], video_rows)
    write_summary(issue_rows, missing_rows, video_rows, overlay_counts, source_counts)

    print(f"summary={SUMMARY_MD}")
    print(f"issues={len(issue_rows)} -> {ISSUE_TSV}")
    print(f"missing_overlay={len(missing_rows)} -> {MISSING_TSV}")
    print(f"videos={len(video_rows)} -> {VIDEO_TSV}")


if __name__ == "__main__":
    main()
