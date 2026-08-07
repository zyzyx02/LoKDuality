#!/usr/bin/env python3
"""
Rebuild the annotated corpus from your own copies of the source transcripts.

The repository ships the register annotation without the dialogue text. This
script parses your transcript files, joins the annotation back onto them by
game and sequence number, and writes the full corpus that the analysis scripts
expect.

Every joined row is verified against a hash of the text recorded when the
annotation was made, so a transcript that differs from the one used in the
study will be reported rather than silently producing different numbers.

Usage:
    python3 scripts/rebuild_corpus.py TRANSCRIPT_DIR OUTPUT_CSV

TRANSCRIPT_DIR must contain the five files named in
annotation/source_manifest.csv.
"""

import csv
import hashlib
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ANNOTATION = os.path.join(REPO, "annotation", "lok_register_annotation.csv")
MANIFEST = os.path.join(REPO, "annotation", "source_manifest.csv")
PARSER = os.path.join(HERE, "parse_lok.py")

ANNOTATION_COLS = ["register", "register_source", "p_narration", "speaker_canon"]


def sha1_12(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]


def check_manifest(transcript_dir):
    """Compare the user's transcripts against the ones used in the study."""
    ok = True
    with open(MANIFEST, encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            path = os.path.join(transcript_dir, row["file"])
            if not os.path.exists(path):
                print("missing: %s" % path)
                ok = False
                continue
            digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
            if digest != row["sha256"]:
                print("differs from the study copy: %s" % row["file"])
                print("  expected %s" % row["sha256"][:16])
                print("  found    %s" % digest[:16])
                ok = False
    return ok


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    transcript_dir = sys.argv[1]
    out_csv = sys.argv[2] if len(sys.argv) > 2 else "lok_corpus_final.csv"

    if os.path.exists(out_csv):
        sys.exit("error: '%s' already exists. Move or rename it first." % out_csv)

    identical = check_manifest(transcript_dir)
    if identical:
        print("source transcripts match the study copies")
    else:
        print("\nOne or more transcripts differ. The rebuild will continue, and")
        print("every block that does not match will be listed at the end.\n")

    parsed = os.path.join(os.path.dirname(out_csv) or ".", "_parsed_tmp.csv")
    if os.path.exists(parsed):
        os.remove(parsed)
    subprocess.run([sys.executable, PARSER, transcript_dir, parsed], check=True)

    ann = {}
    with open(ANNOTATION, encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            ann[(r["game"], r["seq"])] = r

    rows, mismatched, unmatched = [], [], []
    with open(parsed, encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            key = (r["game"], r["seq"])
            a = ann.get(key)
            if a is None:
                unmatched.append(key)
                continue
            if a["text_sha1"] and sha1_12(r["text"]) != a["text_sha1"]:
                mismatched.append(key)
            for c in ANNOTATION_COLS:
                r[c] = a.get(c, "")
            r["n_words"] = len(r["text"].split())
            rows.append(r)

    os.remove(parsed)

    cols = ["game", "scene_id", "scene", "seq", "speaker", "speaker_canon",
            "type", "register", "register_source", "p_narration", "text"]
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    print("\nwrote %s (%d rows)" % (out_csv, len(rows)))
    print("annotation rows joined : %d of %d" % (len(rows), len(ann)))
    print("text hash mismatches   : %d" % len(mismatched))
    print("parsed rows unmatched  : %d" % len(unmatched))

    for label, items in (("mismatched", mismatched), ("unmatched", unmatched)):
        if items:
            print("\nfirst %s rows:" % label)
            for k in items[:10]:
                print("   game=%s seq=%s" % k)

    if mismatched or unmatched:
        print("\nThe rebuilt corpus is not identical to the one used in the")
        print("study. Results computed from it will differ. See the README")
        print("section on reproducing the corpus.")


if __name__ == "__main__":
    main()
