#!/usr/bin/env python3
"""
Export the remaining review blocks as a minimal, Excel-safe sheet.

Two things this handles that a plain CSV dump does not.

Excel treats a cell beginning with "=", "-", "+" or "@" as a formula, so a
line of dialogue starting with a dash is destroyed on save and comes back as
#NAME?. Every text cell is therefore written with a leading apostrophe, which
Excel consumes on display and which this script strips again on import.

The sheet carries only the columns needed to make a decision, so there is no
way to accidentally edit the corpus itself. The merge is by game + seq.

Usage:
    python3 export_review.py lok_corpus_final.csv review_sheet.csv
"""

import csv
import sys

FORMULA_LEAD = ("=", "-", "+", "@")


def armour(text):
    """Prefix a text cell so Excel cannot read it as a formula."""
    return "'" + text if text[:1] in FORMULA_LEAD else text


def strip_armour(text):
    """Undo armour(). Safe to call on cells that were never armoured."""
    if text[:1] == "'" and text[1:2] in FORMULA_LEAD:
        return text[1:]
    return text


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "lok_corpus_final.csv"
    out = sys.argv[2] if len(sys.argv) > 2 else "review_sheet.csv"

    rows = [r for r in csv.DictReader(open(src, encoding="utf-8"))
            if r.get("register") == "review"]

    if not rows:
        print("nothing left to review")
        return

    rows.sort(key=lambda r: (r["game"], int(r["seq"])))

    cols = ["game", "seq", "speaker_canon", "scene", "p_narration",
            "register_manual", "text"]
    with open(out, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for r in rows:
            w.writerow([r["game"], r["seq"], r["speaker_canon"], r["scene"],
                        r["p_narration"], "", armour(r["text"])])

    print("wrote %s (%d rows)" % (out, len(rows)))
    print("fill in register_manual with: narration | dialogue | ambiguous")


if __name__ == "__main__":
    main()
