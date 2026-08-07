#!/usr/bin/env python3
"""
Register classifier for the Legacy of Kain corpus.

Three of the five games mark narration explicitly in the source transcript:

    Blood Omen     round brackets inside a <Kain> block
    Blood Omen 2   round brackets inside a <Kain> block
    Soul Reaver 2  a "Raziel V.O.:" speaker label

Those blocks form the reference set. A logistic regression on eight surface
features is fitted to them, evaluated by leave-one-group-out cross-validation
where a group is one game-speaker pair, and then applied to the two games with
no marker at all (Soul Reaver, Defiance) plus Kain's lines in Soul Reaver 2.

Blocks whose predicted probability falls inside the uncertainty band are
written out for manual adjudication rather than being silently assigned.

Usage:
    python3 classify_register.py lok_corpus.csv lok_corpus_labelled.csv
"""

import csv
import re
import sys

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GroupKFold, cross_val_predict
from sklearn.metrics import classification_report, confusion_matrix

# Blocks with predicted probability in this band go to manual review.
BAND = (0.35, 0.65)

SECOND = re.compile(r"\b(you|your|yours|yourself|thee|thy|thou|thine)\b", re.I)
FIRST = re.compile(r"\b(i|me|my|mine|myself|we|us|our)\b", re.I)
PAST = re.compile(
    r"\b(\w+ed|was|were|had|did|saw|came|went|knew|felt|found|took|stood|"
    r"left|told|thought|became|began|held|spoke|lay|rose|fell|made|gave|"
    r"sought|bore|drew)\b", re.I)
PRESENT = re.compile(r"\b(is|are|am|do|does|will|shall|can|must|have|has)\b", re.I)

FEATURE_NAMES = [
    "second_person_rate", "first_person_rate", "past_rate", "present_rate",
    "question_rate", "exclam_rate", "log_length", "has_second_person",
]


def guard_paths(inputs, outputs):
    """Refuse to write over an input file. A hand-edited file is not recoverable."""
    import os
    ins = {os.path.abspath(p) for p in inputs if p}
    for p in outputs:
        if p and os.path.abspath(p) in ins:
            sys.exit("error: refusing to write '%s' - it is an input file." % p)
        if p and os.path.exists(p):
            sys.exit("error: '%s' already exists. Move or rename it first." % p)


def canonical_speaker(name):
    """Fold case variants and known typos. Distinct characters stay distinct."""
    n = " ".join(name.split()).strip()
    fixes = {
        "tomb guaridan": "Tomb Guardian",
        "janos": "Janos Audron",
    }
    key = n.lower()
    if key in fixes:
        return fixes[key]
    # Sarafan Raziel is the past human Raziel and must not merge with Raziel.
    if key == "sarafan raziel":
        return "Sarafan Raziel"
    return n.title() if n.isupper() else n


def features(text):
    words = text.split()
    n = max(len(words), 1)
    return [
        len(SECOND.findall(text)) / n,
        len(FIRST.findall(text)) / n,
        len(PAST.findall(text)) / n,
        len(PRESENT.findall(text)) / n,
        text.count("?") / n,
        text.count("!") / n,
        float(np.log1p(n)),
        1.0 if SECOND.search(text) else 0.0,
    ]


def build_reference(rows):
    """Return (rows, labels, groups) for the explicitly marked material."""
    ref = []
    for r in rows:
        game, sp, src = r["game"], r["speaker_canon"], r["register_source"]
        if game in ("Blood Omen", "Blood Omen 2") and sp == "Kain":
            # In these two games the bracket convention covers the whole file:
            # bracketed is narration, everything else is spoken.
            lab = "narration" if r["register"] == "narration" else "dialogue"
            ref.append((r, lab))
        elif game == "Soul Reaver 2" and sp == "Raziel":
            lab = "narration" if src == "explicit_vo" else "dialogue"
            ref.append((r, lab))
    return ref


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "lok_corpus.csv"
    out = sys.argv[2] if len(sys.argv) > 2 else "lok_corpus_labelled.csv"

    guard_paths([src], [out, "review_queue.csv"])

    rows = list(csv.DictReader(open(src, encoding="utf-8")))
    for r in rows:
        r["speaker_canon"] = canonical_speaker(r["speaker"]) if r["speaker"] else ""

    speech = [r for r in rows if r["type"] == "speech"]
    ref = build_reference(speech)

    X = np.array([features(r["text"]) for r, _ in ref])
    y = np.array([1 if lab == "narration" else 0 for _, lab in ref])
    groups = np.array(["%s|%s" % (r["game"], r["speaker_canon"]) for r, _ in ref])

    print("reference blocks : %d  (narration %d, dialogue %d)"
          % (len(y), int(y.sum()), int((1 - y).sum())))
    print("reference words  : %d"
          % sum(len(r["text"].split()) for r, _ in ref))
    print("groups           : %s" % ", ".join(sorted(set(groups))))
    print()

    clf = LogisticRegression(max_iter=2000, class_weight="balanced")
    pred = cross_val_predict(clf, X, y, cv=GroupKFold(n_splits=3), groups=groups)
    print("Leave-one-group-out cross-validation")
    print(classification_report(y, pred,
                                target_names=["dialogue", "narration"], digits=3))
    print("confusion matrix (rows true, cols predicted):")
    print(confusion_matrix(y, pred))
    print()

    clf.fit(X, y)
    print("fitted coefficients")
    for name, coef in sorted(zip(FEATURE_NAMES, clf.coef_[0]),
                             key=lambda t: -abs(t[1])):
        print("  %-22s %+7.3f" % (name, coef))
    print()

    # Apply to everything not covered by an explicit marker.
    ref_ids = {id(r) for r, _ in ref}
    todo = [r for r in speech if id(r) not in ref_ids]
    if todo:
        P = clf.predict_proba(np.array([features(r["text"]) for r in todo]))[:, 1]
        for r, p in zip(todo, P):
            r["p_narration"] = "%.4f" % p
            if BAND[0] <= p <= BAND[1]:
                r["register"] = "review"
                r["register_source"] = "model_uncertain"
            else:
                r["register"] = "narration" if p > 0.5 else "dialogue"
                r["register_source"] = "model"

    for r, lab in ref:
        r["register"] = lab
        r["p_narration"] = ""

    for r in rows:
        r.setdefault("p_narration", "")

    n_review = sum(1 for r in speech if r["register"] == "review")
    w_review = sum(len(r["text"].split()) for r in speech if r["register"] == "review")
    print("model-assigned blocks : %d" % sum(
        1 for r in speech if r["register_source"] == "model"))
    print("flagged for review    : %d blocks, %d words" % (n_review, w_review))

    cols = ["game", "scene_id", "scene", "seq", "speaker", "speaker_canon",
            "type", "register", "register_source", "p_narration", "text"]
    with open(out, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print("wrote %s" % out)

    with open("review_queue.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows([r for r in speech if r["register"] == "review"])
    print("wrote review_queue.csv")


if __name__ == "__main__":
    main()
