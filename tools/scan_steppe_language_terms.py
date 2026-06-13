from __future__ import annotations

import csv
import re
from collections import Counter, defaultdict
from pathlib import Path


WORKSPACE = Path(r"D:\Pathologic3_CN_Work")
OVERLAY_ROOT = WORKSPACE / "09_patch_work" / "overlay_cn_textassets_20260422"
REPORT_DIR = WORKSPACE / "00_codex_reports"
REPORT_INDEX = 283

OCCURRENCES_TSV = REPORT_DIR / f"{REPORT_INDEX}_steppe_language_occurrences.tsv"
SUMMARY_TSV = REPORT_DIR / f"{REPORT_INDEX}_steppe_language_terms_summary.tsv"
REPORT_MD = REPORT_DIR / f"{REPORT_INDEX}_steppe_language_report.md"

LINE_RE = re.compile(r"^\ufeff?\{([^}]+)\}\s?(.*)$")
TOKEN_RE = re.compile(r"[A-Za-zÀ-ÖØ-öø-ÿĀ-ſƀ-ɏ\u0400-\u04FF][A-Za-zÀ-ÖØ-öø-ÿĀ-ſƀ-ɏ\u0400-\u04FF'’-]*")
CJK_RE = re.compile(r"[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]")
SPECIAL_STEPPE_RE = re.compile(r"[үҮөӨһҺüÜöÖäÄëË]")

HTML_TAGS = {"i", "b", "br", "size", "color", "alpha"}
NON_STEPPE = {
    "inputactions",
    "weapon",
    "inventory",
    "tablet",
    "tags",
    "ctrl",
    "shift",
    "space",
    "mouse",
    "pathologic",
    "english",
    "russian",
    "chinese",
    "simplified",
    "final",
    "day",
    "old",
    "new",
    "intro",
    "doctor",
    "bachelor",
    "haruspex",
    "changeling",
    "sticky",
    "victor",
    "rubin",
    "aglaya",
    "eva",
    "lara",
    "maria",
    "khan",
    "andrey",
    "peter",
    "georgiy",
    "anna",
    "vlad",
    "rat",
    "prophet",
    "seigneur",
    "eccelenza",
    "mon",
    "ami",
    "ave",
    "alea",
    "iacta",
    "est",
    "nota",
    "bene",
    "opus",
    "pretium",
    "satur",
    "venter",
    "non",
    "studet",
    "libenter",
}

SEED_TERMS = {
    "abarba",
    "abarga",
    "adyr",
    "akhai",
    "basagan",
    "bayarla",
    "bayartai",
    "bee",
    "bide",
    "bidenkhee",
    "boddho",
    "bodkho",
    "bokhir",
    "boleesh",
    "booha",
    "bos",
    "delkheye",
    "duulana",
    "dur",
    "duran",
    "ekhe",
    "emshen",
    "ene",
    "erdem",
    "gansal",
    "gazar",
    "ghazar",
    "ghuib",
    "gurim",
    "gürwhal",
    "hayn",
    "halkhinai",
    "hoorakha",
    "khaanagүy",
    "khaanashye",
    "khari",
    "kharaan",
    "kharaal",
    "khatanghe",
    "khatanger",
    "khatar",
    "kheerei",
    "khele",
    "khelekhe",
    "khezhe",
    "khezyeeshye",
    "khezyeeshye",
    "khoyedorkhi",
    "khubn",
    "khun",
    "khүlisael",
    "khүn",
    "khүsiye",
    "khulgaylaa",
    "malghai",
    "menkhu",
    "mende",
    "muu",
    "myy",
    "naada",
    "namaiye",
    "namaye",
    "namduu",
    "nanghin",
    "naran",
    "naydanab",
    "neghe",
    "noukher",
    "nyuurtai",
    "odongh",
    "odong",
    "olon",
    "oilgonogüish",
    "oyohon",
    "shabnak",
    "shabnak-adyr",
    "shaghna",
    "sharkhayaa",
    "shee",
    "shekhen",
    "shi",
    "shuhan",
    "shүүberilkhe",
    "suok",
    "sülööl",
    "sүlөөtei",
    "tahalbabdhi",
    "takhal",
    "talh",
    "teghel",
    "temdegh",
    "tenegh",
    "terenei",
    "tere",
    "tiime",
    "tiimel",
    "twyrine",
    "twyrine",
    "twyre",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyrine",
    "twyre",
    "udhar",
    "ukhedel",
    "urmaan",
    "usadhadag",
    "uydhartay",
    "ykhekhe",
    "yohotoy",
    "yshөө",
    "zaluu",
    "zaluushuulai",
    "zhegtei",
    "zherkheshtey",
    "zürkhen",
    "үghi",
    "үshөө",
}

PHRASE_SEEDS = {
    "be te kharaan",
    "shi baha ykhekhe gazhe naydanab",
    "zaluushuulai shuhan ghazar delkheye uhalkhan boltogoi",
    "bide bagha khүsiye tahalbabdhi",
    "hayn halkhinai temdegh",
    "gansal shuhan muue usadhadag",
    "terenei shuhan gazar delkheye khaluulan bayg le",
    "yshөө neghe khari khүn gazarhyemnai debhazhe bayna",
    "tere khaa khaanagүy khaanashye ügy",
}


def normalize(token: str) -> str:
    return token.strip("'’-").lower()


def likely_steppe_token(token: str, text: str, asset_key: str, rel_path: str) -> bool:
    norm = normalize(token)
    if len(norm) < 3 or norm in HTML_TAGS or norm in NON_STEPPE:
        return False
    if norm in SEED_TERMS:
        return True
    if SPECIAL_STEPPE_RE.search(token):
        return True
    lower_context = f"{asset_key} {rel_path} {text}".lower()
    if any(marker in lower_context for marker in ("steppe", "odong", "tuutey", "oktay", "vlad sacrifice", "vlad_sacrifice", "burakh", "khatang", "shabnak")):
        return bool(re.search(r"kh|gh|sh|zh|aa|ee|uu|oo|ү|ө|һ|ü|ö", norm))
    return False


def classify_render(term: str, text: str) -> tuple[str, str]:
    escaped = re.escape(term)
    gloss_match = re.search(escaped + r"\s*[（(]([^）)]+)[）)]", text, flags=re.IGNORECASE)
    if gloss_match:
        return "retained_with_gloss", gloss_match.group(1)
    if re.search(escaped, text, flags=re.IGNORECASE):
        return "retained_no_gloss", ""
    return "translated_or_absent", ""


def write_tsv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    occurrence_rows: list[dict[str, str]] = []
    by_term: dict[str, list[dict[str, str]]] = defaultdict(list)

    for path in sorted(OVERLAY_ROOT.rglob("*_Chinese_Simplified.txt")):
        rel_path = path.relative_to(OVERLAY_ROOT).as_posix()
        if rel_path.startswith("ui/credits/"):
            continue
        for line_no, raw_line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
            match = LINE_RE.match(raw_line)
            if not match:
                continue
            asset_key, text = match.group(1), match.group(2)
            if not CJK_RE.search(text):
                continue
            seen_terms: set[str] = set()
            for phrase in PHRASE_SEEDS:
                if phrase.lower() in text.lower():
                    seen_terms.add(phrase)
            for token in TOKEN_RE.findall(text):
                if likely_steppe_token(token, text, asset_key, rel_path):
                    seen_terms.add(token)
            for term in sorted(seen_terms, key=lambda item: item.lower()):
                mode, gloss = classify_render(term, text)
                row = {
                    "term": term,
                    "term_norm": normalize(term),
                    "render_mode": mode,
                    "gloss": gloss,
                    "file": rel_path,
                    "line_no": str(line_no),
                    "asset_key": asset_key,
                    "text": text,
                }
                occurrence_rows.append(row)
                by_term[normalize(term)].append(row)

    summary_rows: list[dict[str, str]] = []
    for term_norm, rows in sorted(by_term.items(), key=lambda item: (-len(item[1]), item[0])):
        display_terms = Counter(row["term"] for row in rows)
        modes = Counter(row["render_mode"] for row in rows)
        glosses = Counter(row["gloss"] for row in rows if row["gloss"])
        sample = rows[0]
        summary_rows.append(
            {
                "term_norm": term_norm,
                "display_forms": "; ".join(f"{term}={count}" for term, count in display_terms.most_common(6)),
                "occurrences": str(len(rows)),
                "render_modes": "; ".join(f"{mode}={count}" for mode, count in modes.most_common()),
                "glosses": "; ".join(f"{gloss}={count}" for gloss, count in glosses.most_common(8)),
                "sample_file": sample["file"],
                "sample_line_no": sample["line_no"],
                "sample_text": sample["text"],
            }
        )

    write_tsv(
        OCCURRENCES_TSV,
        ["term", "term_norm", "render_mode", "gloss", "file", "line_no", "asset_key", "text"],
        occurrence_rows,
    )
    write_tsv(
        SUMMARY_TSV,
        ["term_norm", "display_forms", "occurrences", "render_modes", "glosses", "sample_file", "sample_line_no", "sample_text"],
        summary_rows,
    )

    mode_counts = Counter(row["render_mode"] for row in occurrence_rows)
    potentially_inconsistent = [
        row
        for row in summary_rows
        if ";" in row["render_modes"] or ";" in row["glosses"] or ";" in row["display_forms"]
    ]
    lines = [
        "# Steppe Language Term Scan",
        "",
        f"- overlay_root = {OVERLAY_ROOT}",
        f"- occurrences_tsv = {OCCURRENCES_TSV}",
        f"- summary_tsv = {SUMMARY_TSV}",
        f"- occurrence_rows = {len(occurrence_rows)}",
        f"- unique_terms = {len(summary_rows)}",
        "",
        "## Render Mode Counts",
        "",
        "| count | mode |",
        "|---:|---|",
    ]
    for mode, count in mode_counts.most_common():
        lines.append(f"| {count} | {mode} |")
    lines.extend(["", "## Most Frequent Terms", "", "| count | term | render modes | glosses |", "|---:|---|---|---|"])
    for row in summary_rows[:80]:
        lines.append(f"| {row['occurrences']} | `{row['term_norm']}` | {row['render_modes']} | {row['glosses']} |")
    lines.extend(["", "## Potentially Inconsistent Terms", "", "| count | term | forms | modes | glosses |", "|---:|---|---|---|---|"])
    for row in potentially_inconsistent[:80]:
        lines.append(f"| {row['occurrences']} | `{row['term_norm']}` | {row['display_forms']} | {row['render_modes']} | {row['glosses']} |")
    REPORT_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"occurrences={len(occurrence_rows)} -> {OCCURRENCES_TSV}")
    print(f"unique_terms={len(summary_rows)} -> {SUMMARY_TSV}")
    print(f"report={REPORT_MD}")


if __name__ == "__main__":
    main()
