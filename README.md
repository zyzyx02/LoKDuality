# Register and character in the Legacy of Kain series

Corpus annotation and analysis code for a study separating narration from
dialogue across the five Legacy of Kain games (1996 to 2003), and asking
whether the resemblance between the two protagonists is a property of the
characters or of the narrative role they occupy.

The corpus contains 1,768 speech blocks and 39,247 words, annotated for
register as narration or dialogue, with the provenance of every label
recorded.

---

## What this repository does not contain

**The dialogue text is not distributed here.** Two separate reasons.

The source transcripts are community work, produced and published by
individual contributors, and are not ours to redistribute. The dialogue
itself is the intellectual property of the rights holders of the games.

What is published instead is a *stand-off annotation*: one row per speech
block, carrying the speaker, the register label, the provenance of that label
and a hash of the text, but not the text. Together with your own copies of the
transcripts and the parser in `scripts/`, this reconstructs the full corpus
exactly. The procedure is in **Reproducing the corpus** below.

This is the usual arrangement for corpora built on material that cannot be
redistributed, and it costs nothing in reproducibility: the rebuild is
verified block by block against the hashes recorded when the annotation was
made.

---

## Repository layout

```
.
├── README.md
├── LICENCE                       code, MIT
├── LICENCE-DATA                  annotation, CC BY 4.0
├── CITATION.cff
│
├── annotation/
│   ├── lok_register_annotation.csv    the annotation, without text
│   ├── source_manifest.csv            sha256 of each source transcript
│   └── codebook.md                    column definitions and label rules
│
├── scripts/                      corpus construction, Python 3
│   ├── parse_lok.py              transcripts to a normalised schema
│   ├── classify_register.py      register classifier and evaluation
│   ├── merge_manual.py           narrator constraint and manual decisions
│   ├── export_review.py          Excel-safe sheet for hand coding
│   └── rebuild_corpus.py         rebuild the full corpus from your own copies
│
├── analysis/                     analysis, R 4.3
│   ├── lok_common.R              loading, cells, helpers
│   ├── 01_nrc_profiles.R         NRC emotion profiles and contrasts
│   ├── 02_lexical_diversity.R    MTLD and TTR at a common token budget
│   ├── 03_pairwise_similarity.R  tf-idf cosine, permutation test
│   ├── 04_sensitivity.R          three nested corpus restrictions
│   └── 05_figures.R              the six figures
│
├── data/                         derived results, no dialogue text
│   ├── out_nrc_profiles.csv
│   ├── out_nrc_contrasts.csv
│   ├── out_lexical_diversity.csv
│   ├── out_similarity_matrix.csv
│   ├── out_similarity_pairs.csv
│   ├── out_sensitivity.csv
│   └── review_sheet_coded.csv    the 22 hand-coded blocks
│
├── figures/                      the six figures, PNG at 600 dpi
└── docs/
    └── annotation_procedure.md   the full labelling procedure
```

`data/out_nrc_block_scores.csv` is deliberately absent. It is keyed to blocks
and is regenerated on the first run of `01_nrc_profiles.R`.

---

## Reproducing the corpus

You need your own copies of the five transcripts. `annotation/source_manifest.csv`
lists the filename, byte size and sha256 of each file used in the study, so
that a copy obtained elsewhere can be checked against it.

```bash
python3 scripts/rebuild_corpus.py path/to/transcripts lok_corpus_final.csv
```

The script parses your files, joins the annotation on `game` and `seq`, and
verifies each block against the recorded text hash. Expected output:

```
source transcripts match the study copies
annotation rows joined : 2505 of 2505
text hash mismatches   : 0
parsed rows unmatched  : 0
```

If your transcripts differ from the study copies, the script still produces a
corpus but lists every block that failed verification. Results computed from
such a corpus will not match the published numbers, and the difference should
be reported alongside them.

### Building the annotation from scratch

The annotation shipped here is the output of the following chain. Running it
reproduces `annotation/lok_register_annotation.csv` up to the manual step,
which requires human judgement on 22 blocks.

```bash
python3 scripts/parse_lok.py path/to/transcripts lok_corpus.csv
python3 scripts/classify_register.py lok_corpus.csv lok_corpus_labelled.csv
python3 scripts/export_review.py lok_corpus_labelled.csv review_sheet.csv
# hand code the register_manual column, save as review_sheet_coded.csv
python3 scripts/merge_manual.py lok_corpus_labelled.csv review_sheet_coded.csv
```

`data/review_sheet_coded.csv` contains the decisions made in the study, so the
chain can be run without repeating the manual pass.

The scripts refuse to overwrite an existing output file. Remove or rename
previous outputs before rerunning.

---

## Running the analysis

R 4.3 or later, with `readr`, `dplyr`, `tidyr`, `stringr`, `ggplot2`,
`syuzhet` and, for one figure, `ggrepel`.

```bash
cd analysis
export LOK_CORPUS=../lok_corpus_final.csv
Rscript 01_nrc_profiles.R
Rscript 02_lexical_diversity.R
LOK_NPERM=2000 Rscript 03_pairwise_similarity.R
Rscript 04_sensitivity.R
Rscript 05_figures.R
```

Order matters: `05_figures.R` reads the `out_*.csv` files produced by the
first four.

Two environment variables control the runs. `LOK_CORPUS` points at the corpus,
defaulting to `lok_corpus_final.csv` in the working directory. `LOK_NPERM`
sets the number of permutation replicates in script 03, defaulting to 500; the
published figure of p = 0.001 comes from 2,000, at which the observed
difference falls below every permuted value.

Random seeds are fixed, so repeated runs of the same script on the same corpus
give identical output.

The NRC lexicon is not redistributed. `01_nrc_profiles.R` uses the copy
bundled with the `syuzhet` package.

---

## The annotation

Register labels come from five sources, in decreasing order of directness. The
`register_source` column records which applied to each block.

| Source | Blocks | Words | Share of words |
|---|---:|---:|---:|
| `explicit_paren`, `explicit_vo` | 214 | 8,745 | 22.3% |
| `none`, unmarked within a marked game | 383 | 5,886 | 15.0% |
| `constraint`, narrator role | 216 | 7,745 | 19.7% |
| `manual` | 22 | 330 | 0.8% |
| `model` | 933 | 16,541 | 42.1% |

57.9 per cent of the running text carries a label that does not depend on the
classifier, which is what makes the sensitivity analysis in `04_sensitivity.R`
possible.

The narrator constraint states that only the playable protagonist narrates,
and only in the games where he is playable: Kain in the two *Blood Omen*
titles, Raziel in the two *Soul Reaver* titles, and both in *Defiance*. It
overrides every other source, including the classifier and the manual pass.
Full definitions are in `annotation/codebook.md` and the reasoning in
`docs/annotation_procedure.md`.

---

## Known limitations

Recorded here so that anyone reusing the annotation knows what they are
getting.

The reference labels come from community transcripts rather than from
development materials, so the marking conventions were applied by transcribers
and are not perfectly consistent. At least one *Blood Omen* block is narration
by content while carrying no bracket.

*Defiance* marks stage directions with round brackets on their own lines
rather than with square brackets. Its 132 direction paragraphs are discarded
at parsing rather than retained as rows, so the 737 stage directions in the
corpus come from four transcripts, not five.

Thirteen blocks in *Defiance* and *Soul Reaver 2* carried a short performance
direction inside the spoken text. These 37 words are removed by
`strip_performance_directions` in the parser.

The classifier reaches 0.888 accuracy under leave-one-group-out
cross-validation but assigns narration to 23.8 per cent of blocks spoken by
characters who cannot narrate. Register is recoverable from surface features;
the narrator role is not, and must be imposed structurally.

---

## Licence

Code in `scripts/` and `analysis/` is released under the MIT Licence.

The annotation in `annotation/` and the derived results in `data/` are
released under CC BY 4.0. The annotation is our own work. It refers to
dialogue we do not own and do not distribute.

The source transcripts belong to their contributors and are not included. The
dialogue they transcribe belongs to the rights holders of the games.

## Citation

See `CITATION.cff`. Please cite the paper rather than the repository where
both are relevant.
