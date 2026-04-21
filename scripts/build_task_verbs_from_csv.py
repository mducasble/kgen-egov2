#!/usr/bin/env python3
"""Regenerate EgoCapture/Resources/task_verbs.json from docs/activities_verbs.csv.

Run from repo root:
  python3 scripts/build_task_verbs_from_csv.py

Expects columns: task_category_code, verbs_pt, verbs_en, verbs_es (pipe-separated).
"""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "docs/activities_verbs.csv"
OUT = ROOT / "EgoCapture/Resources/task_verbs.json"


def split_pipe(s: str) -> list[str]:
    s = (s or "").strip()
    if not s:
        return []
    return [x.strip() for x in s.split("|") if x.strip()]


def main() -> None:
    rows = list(csv.DictReader(CSV_PATH.open(encoding="utf-8-sig")))
    entries = []
    for r in rows:
        pt = split_pipe(r.get("verbs_pt", ""))
        en = split_pipe(r.get("verbs_en", ""))
        es = split_pipe(r.get("verbs_es", ""))
        if len(pt) != len(en) or len(pt) != len(es):
            raise SystemExit(
                f"Verb count mismatch for {r.get('task_category_code')!r}: "
                f"pt={len(pt)} en={len(en)} es={len(es)}"
            )
        entries.append(
            {
                "task_category_code": r["task_category_code"].strip(),
                "verbs_pt": pt,
                "verbs_en": en,
                "verbs_es": es,
            }
        )
    payload = {
        "schema_version": "1.0.0",
        "generated_at": "2026-04-21",
        "entries": entries,
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(entries)} entries to {OUT}")


if __name__ == "__main__":
    main()
