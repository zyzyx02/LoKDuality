#!/usr/bin/env python3
"""
Apply the per-game narrator constraint and merge manual review decisions.

The constraint is a fact about the games, not something inferred from the text:
only the playable protagonist narrates, and only in the games where he is
playable.

    Blood Omen      Kain
    Blood Omen 2    Kain
    Soul Reaver     Raziel
    Soul Reaver 2   Raziel
    Defiance        Kain and Raziel

Any block attributed to another speaker is spoken dialogue by definition, so
the constraint overrides both the classifier and the manual pass. Where a
manual decision disagrees with it, the row is written to a conflict file
rather than being silently overwritten, because a disagreement usually means
either a speaker-label problem in the source transcript or a genuine edge case
worth looking at.

Precedence, highest first:
    1. narrator constraint
    2. manual decision from the review queue
    3. explicit marker in the source transcript
    4. classifier prediction

Usage:
    python3 merge_manual.py lok_corpus_labelled.csv [review_queue_coded.csv]
"""

import csv
import collections
import sys

ALLOWED_NARRATORS = {
    "Blood Omen": {"Kain"},
    "Blood Omen 2": {"Kain"},
    "Soul Reaver": {"Raziel"},
    "Soul Reaver 2": {"Raziel"},
    "Defiance": {"Kain", "Raziel"},
}

# Column the manual pass is expected to fill in the edited review queue.
MANUAL_COL = "register_manual"
VALID_MANUAL = {"narration", "dialogue", "ambiguous"}

OUT_MAIN = "lok_corpus_final.csv"
OUT_CONFLICT = "constraint_conflicts.csv"


def guard_paths(inputs, outputs):
    """Refuse to write over an input file. A hand-edited file is not recoverable."""
    import os
    ins = {os.path.abspath(p) for p in inputs if p}
    for p in outputs:
        if p and os.path.abspath(p) in ins:
            sys.exit("error: refusing to write '%s' - it is an input file." % p)
        if p and os.path.exists(p):
            sys.exit("error: '%s' already exists. Move or rename it first." % p)


def key(row):
    return (row["game"], row["seq"])


def load_manual(path):
    """Read the hand-coded review queue. Returns dict keyed by (game, seq)."""
    out = {}
    with open(path, encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        if MANUAL_COL not in reader.fieldnames:
            sys.exit("error: %s has no '%s' column. Columns found: %s"
                     % (path, MANUAL_COL, ", ".join(reader.fieldnames or [])))
        for r in reader:
            val = (r.get(MANUAL_COL) or "").strip().lower().lstrip("'")
            if not val:
                continue
            if val not in VALID_MANUAL:
                sys.exit("error: unexpected value '%s' in %s at game=%s seq=%s"
                         % (val, MANUAL_COL, r.get("game"), r.get("seq")))
            out[(r["game"], r["seq"])] = val
    return out


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "lok_corpus_labelled.csv"
    manual_path = sys.argv[2] if len(sys.argv) > 2 else None

    guard_paths([src, manual_path], [OUT_MAIN, OUT_CONFLICT])

    rows = list(csv.DictReader(open(src, encoding="utf-8")))
    manual = load_manual(manual_path) if manual_path else {}
    if manual_path:
        print("manual decisions read : %d" % len(manual))

    unknown_game = {r["game"] for r in rows} - set(ALLOWED_NARRATORS)
    if unknown_game:
        sys.exit("error: no narrator rule for game(s): %s" % ", ".join(unknown_game))

    conflicts = []
    stats = collections.Counter()
    matched = set()

    for r in rows:
        if r["type"] != "speech":
            continue

        k = key(r)

        # 2. manual decision
        if k in manual:
            matched.add(k)
            r["register"] = manual[k]
            r["register_source"] = "manual"
            r["p_narration"] = ""
            stats["manual"] += 1

        # 1. narrator constraint, applied last so it takes precedence
        permitted = ALLOWED_NARRATORS[r["game"]]
        if r["register"] == "narration" and r["speaker_canon"] not in permitted:
            if r["register_source"] == "manual":
                conflicts.append(dict(r))
                stats["conflict_manual"] += 1
            elif r["register_source"] in ("explicit_paren", "explicit_vo"):
                # A source marker contradicting the constraint means the
                # transcript itself is inconsistent. Worth seeing.
                conflicts.append(dict(r))
                stats["conflict_explicit"] += 1
            else:
                stats["constraint_fixed_model"] += 1
            r["register"] = "dialogue"
            r["register_source"] = "constraint"

        # Any remaining "review" row involving a non-permitted speaker is
        # also settled by the constraint.
        elif r["register"] == "review" and r["speaker_canon"] not in permitted:
            r["register"] = "dialogue"
            r["register_source"] = "constraint"
            r["p_narration"] = ""
            stats["constraint_settled_review"] += 1

    stale = set(manual) - matched
    if stale:
        print("warning: %d manual rows did not match any corpus row" % len(stale))
        for k in list(stale)[:5]:
            print("   game=%s seq=%s" % k)

    print()
    for k in ("manual", "constraint_fixed_model", "constraint_settled_review",
              "conflict_manual", "conflict_explicit"):
        print("  %-26s %5d" % (k, stats[k]))

    speech = [r for r in rows if r["type"] == "speech"]
    left = [r for r in speech if r["register"] == "review"]
    print("\n  still marked 'review'      %5d blocks, %d words"
          % (len(left), sum(len(r["text"].split()) for r in left)))
    amb = [r for r in speech if r["register"] == "ambiguous"]
    print("  marked 'ambiguous'         %5d blocks, %d words"
          % (len(amb), sum(len(r["text"].split()) for r in amb)))

    cols = list(rows[0].keys())
    with open(OUT_MAIN, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print("\nwrote %s" % OUT_MAIN)

    if conflicts:
        with open(OUT_CONFLICT, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
            w.writeheader()
            w.writerows(conflicts)
        print("wrote %s (%d rows) - check these by hand"
              % (OUT_CONFLICT, len(conflicts)))


if __name__ == "__main__":
    main()
