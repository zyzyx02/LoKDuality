# Annotation procedure

## Manual coding rule set

The 22 blocks coded by hand were decided against this rule set, applied in
order. The same rules should be used for any extension of the corpus.

1. Does the block address someone present in the scene? If yes, `dialogue`.
2. Is it a past-tense report of events, delivered from outside the exchange?
   If yes, `narration`.
3. Do other speakers alternate with it inside the same scene block? If yes,
   `dialogue`.
4. If none of the above decides it, consult the surrounding blocks in the
   transcript by `scene_id`.
5. If still undecided, `ambiguous`. Such blocks are excluded from analysis and
   their word count reported. None arose in the study.

## Why the constraint overrides everything

The rule that only the playable protagonist narrates is a fact about the
games, not an inference from the text. It was applied last and given the
highest precedence.

Where it contradicted a classifier output, the classifier was overruled
silently and the row marked `constraint`. Where it would have contradicted a
manual decision or an explicit source marker, the row was written to a
conflict file for inspection instead. No such conflict arose.

Applied to the material, the constraint corrected 98 classifier assignments
and settled 118 of the 140 blocks the classifier had flagged as uncertain,
leaving 22 for manual coding.

## Why the constraint is necessary

The classifier reaches 0.888 accuracy under leave-one-group-out
cross-validation, where a group is one game-speaker pair. Applied to the 907
blocks spoken by characters who cannot narrate in that game, it labelled 216
as narration, an error rate of 23.8 per cent.

The two figures are not directly comparable, since narration is absent by
construction from the second set. The gap is nonetheless informative. The
surface features of register, past-tense reporting and the absence of
address, fire on any long reflective monologue, including those by characters
who are structurally incapable of narrating.

## Handling of the source transcripts

Three formatting conventions appear across the five files.

| Game | Speaker label | Scene marker |
|---|---|---|
| Blood Omen | `<Name>` | numbered chapter heading |
| Soul Reaver | `Name:` | `*****TITLE*****` |
| Soul Reaver 2 | `Name:` | `*****Title*****` |
| Blood Omen 2 | `<Name>` | numbered chapter heading |
| Defiance | `NAME:` | numbered section |

Two irregularities required specific handling.

In ten Blood Omen blocks and one Blood Omen 2 block the opening bracket is
never closed; the block ends with a square bracket or with no closing mark. A
parser requiring balanced brackets reads these as spoken lines, which places
narration in the reference set as dialogue. The parser treats an unclosed
bracket as running to the end of the block.

In Defiance and Soul Reaver 2, round brackets mark performance directions
rather than narration. Thirteen blocks carried such a direction inside the
spoken text; these 37 words are stripped.
