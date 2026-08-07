#!/usr/bin/env python3
"""
Legacy of Kain transcript parser.

Reads the five raw transcript files, which use three different formatting
conventions, and emits one normalised CSV:

    game, scene_id, seq, speaker, type, register, register_source, text

type      : "speech" or "action"
register  : "narration", "dialogue", or "unlabelled"
register_source :
    "explicit_vo"     - speaker label carried a voice-over marker (SR2)
    "explicit_paren"  - text was parenthesised inside a speech block (BO1, BO2)
    "none"            - no explicit marker present in the source (SR1, Defiance)

Rows with register_source == "none" are left as "unlabelled" on purpose.
Classifying them is a separate step, and the explicitly marked games are the
reference data for that step.

Usage:
    python3 parse_lok.py INPUT_DIR OUTPUT_CSV
"""

import csv
import os
import re
import sys

# ----------------------------------------------------------------------------
# Per-file configuration
# ----------------------------------------------------------------------------

FILES = [
    # filename, game label, speaker style, scene-header regex
    ("legacy_of_kain_transcript.txt", "Blood Omen",   "angle", r"^\s*\d+\.\d+\s*-\s*(.+?)\s*$"),
    ("soul_reaver_transcript.txt",    "Soul Reaver",  "colon", r"^\*{3,}(.+?)\*{3,}\s*$"),
    ("soul_reaver2_transcript.txt",   "Soul Reaver 2","colon", r"^\*{3,}(.+?)\*{3,}\s*$"),
    ("blood_omen2_transcript.txt",    "Blood Omen 2", "angle", r"^\s*\d+\.\d+\s*-\s*(.+?)\s*$"),
    ("defiance_transcript.txt",       "Defiance",     "colon", r"^\s*\((\d+)\)\s*$"),
]

ANGLE_SPEAKER = re.compile(r"^<([^>]{1,50})>\s*$")
COLON_SPEAKER = re.compile(r"^([A-Z][A-Za-z0-9 #.'/-]{0,40}):\s*$")
ACTION_OPEN = ("[",)

# Voice-over markers appended to a speaker label, e.g. "Raziel V.O.:"
VO_SUFFIX = re.compile(r"\s+V\.?O\.?$", re.IGNORECASE)

# A parenthesised span. Used for BO1 / BO2, where round brackets inside a
# speech block mark internal monologue rather than spoken lines.
# The second alternative catches an opening bracket that is never closed,
# which happens in the source transcripts (a block may end with "]" or with
# no closing mark at all). Without it those blocks are silently read as
# spoken dialogue and poison the reference set.
PAREN_SPAN = re.compile(r"\(([^()]*)\)|\(([^()]*)$")

# Short parentheticals in Defiance and SR2 are performance directions
# ("(Laughing)", "(Sneering)", "(Screams in agony)"), not narration.
# Games where round brackets genuinely mark narration:
PAREN_IS_NARRATION = {"Blood Omen", "Blood Omen 2"}



# Round brackets inside a speech block are performance directions in these
# games ("(Laughing)", "(To Raziel)"), not part of the spoken line. They are
# stripped so that word counts describe speech only.
PERF_DIRECTION_GAMES = {"Defiance", "Soul Reaver", "Soul Reaver 2"}
PAREN_ANY = re.compile(r"\(([^()]*)\)")


def strip_performance_directions(game, text):
    if game not in PERF_DIRECTION_GAMES or "(" not in text:
        return text
    cleaned = re.sub(r"\s+", " ", PAREN_ANY.sub(" ", text)).strip()
    return cleaned if cleaned else text


def read_lines(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return [ln.rstrip("\r\n") for ln in fh]


def parse_file(path, game, style, scene_re):
    """Return a list of dict rows for one transcript."""
    speaker_re = ANGLE_SPEAKER if style == "angle" else COLON_SPEAKER
    scene_pat = re.compile(scene_re)

    rows = []
    scene_id = 0
    scene_name = ""
    seq = 0

    cur_speaker = None
    buf = []

    def flush():
        nonlocal cur_speaker, buf, seq
        if cur_speaker is None:
            buf = []
            return
        text = " ".join(x.strip() for x in buf if x.strip())
        text = re.sub(r"\s+", " ", text).strip()
        text = strip_performance_directions(game, text)
        raw_speaker = cur_speaker
        cur_speaker, buf = None, []
        if not text:
            return
        for row in split_register(game, text, raw_speaker):
            seq += 1
            row.update(game=game, scene_id=scene_id, scene=scene_name, seq=seq)
            rows.append(row)

    def split_register(game, text, raw_speaker):
        """Split one speech block into register-tagged segments."""
        speaker, is_vo = normalise_speaker(raw_speaker)

        if is_vo:
            return [dict(speaker=speaker, type="speech",
                         register="narration", register_source="explicit_vo",
                         text=text)]

        if game not in PAREN_IS_NARRATION or "(" not in text:
            return [dict(speaker=speaker, type="speech",
                         register="unlabelled", register_source="none",
                         text=text)]

        # Round brackets mark internal monologue in this game. Walk the string
        # and emit alternating narration / dialogue segments.
        out, pos = [], 0
        for m in PAREN_SPAN.finditer(text):
            before = text[pos:m.start()].strip()
            if before:
                out.append(dict(speaker=speaker, type="speech",
                                register="dialogue",
                                register_source="explicit_paren",
                                text=before))
            inside = (m.group(1) if m.group(1) is not None else m.group(2))
            inside = inside.strip().rstrip("]")
            if inside:
                out.append(dict(speaker=speaker, type="speech",
                                register="narration",
                                register_source="explicit_paren",
                                text=inside))
            pos = m.end()
        tail = text[pos:].strip()
        if tail:
            out.append(dict(speaker=speaker, type="speech",
                            register="dialogue",
                            register_source="explicit_paren",
                            text=tail))
        return out or [dict(speaker=speaker, type="speech",
                            register="unlabelled", register_source="none",
                            text=text)]

    for ln in read_lines(path):
        stripped = ln.strip()

        m_scene = scene_pat.match(ln)
        if m_scene:
            flush()
            scene_id += 1
            scene_name = m_scene.group(1).strip()
            continue

        if stripped.startswith("+") and set(stripped) == {"+"}:
            continue

        m_sp = speaker_re.match(ln)
        if m_sp:
            flush()
            cur_speaker = m_sp.group(1).strip()
            continue

        if stripped.startswith(ACTION_OPEN):
            flush()
            seq += 1
            rows.append(dict(game=game, scene_id=scene_id, scene=scene_name,
                             seq=seq, speaker="", type="action",
                             register="", register_source="",
                             text=stripped))
            continue

        if cur_speaker is not None:
            if stripped == "":
                flush()
            else:
                buf.append(stripped)

    flush()
    return rows


def normalise_speaker(raw):
    """Strip a voice-over marker from a speaker label. Returns (name, is_vo)."""
    name = raw.strip().rstrip(".")
    if VO_SUFFIX.search(name):
        return VO_SUFFIX.sub("", name).strip(), True
    return name, False


def main():
    in_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    out_csv = sys.argv[2] if len(sys.argv) > 2 else "lok_corpus.csv"

    all_rows = []
    for fname, game, style, scene_re in FILES:
        path = os.path.join(in_dir, fname)
        if not os.path.exists(path):
            sys.stderr.write("missing: %s\n" % path)
            continue
        rows = parse_file(path, game, style, scene_re)
        all_rows.extend(rows)
        sys.stderr.write("%-14s %5d rows\n" % (game, len(rows)))

    cols = ["game", "scene_id", "scene", "seq", "speaker",
            "type", "register", "register_source", "text"]
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(all_rows)
    sys.stderr.write("wrote %s (%d rows)\n" % (out_csv, len(all_rows)))


if __name__ == "__main__":
    main()
