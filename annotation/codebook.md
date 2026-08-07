# Codebook

One row per unit in `lok_register_annotation.csv`. The dialogue text is not
included; `text_sha1` allows a rebuilt row to be verified against the text
used in the study.

| Column | Type | Description |
|---|---|---|
| `game` | string | One of Blood Omen, Soul Reaver, Soul Reaver 2, Blood Omen 2, Defiance. |
| `scene_id` | integer | Sequential scene number within the game, from the transcript's own section markers. |
| `scene` | string | Scene title as given in the transcript, where one exists. |
| `seq` | integer | Sequential position within the game. Together with `game` this is the join key. |
| `speaker` | string | Speaker label exactly as it appears in the transcript. Empty for stage directions. |
| `speaker_canon` | string | Canonical speaker. Case variants and one transcription error are folded. `Sarafan Raziel` is kept distinct from `Raziel`; a `Raziel V.O.` label is folded to `Raziel`. |
| `type` | string | `speech` or `action`. Stage directions are `action` and are excluded from all analyses. |
| `register` | string | `narration` or `dialogue`. Empty for stage directions. |
| `register_source` | string | How the label was obtained. See below. |
| `p_narration` | float | Classifier probability of narration. Populated only where `register_source` is `model`. |
| `n_words` | integer | Whitespace-delimited token count of the text. |
| `text_sha1` | string | First 12 hex characters of the SHA-1 of the text. |

## Values of `register_source`

| Value | Meaning |
|---|---|
| `explicit_paren` | Round brackets inside a `<Kain>` block in Blood Omen or Blood Omen 2, the convention those transcripts use for internal monologue. An unclosed bracket runs to the end of the block. |
| `explicit_vo` | The speaker label carried a voice-over marker, `Raziel V.O.` in Soul Reaver 2. |
| `none` | No marker, in a game where narration is marked. Dialogue by the same convention. |
| `constraint` | Assigned by the narrator constraint: the speaker cannot narrate in that game, so the block is dialogue. |
| `manual` | Hand-coded against the rule set in `docs/annotation_procedure.md`. |
| `model` | Assigned by the logistic classifier described in the paper. |

Precedence, highest first: narrator constraint, manual decision, explicit
marking in the source, classifier.

## Register definitions

**Narration.** First-person commentary addressed to the player, outside the
exchange taking place in the scene. Typically past tense, reporting or
reflecting on events.

**Dialogue.** Speech addressed to another character present in the scene.

## The narrator constraint

| Game | Characters permitted to narrate |
|---|---|
| Blood Omen | Kain |
| Soul Reaver | Raziel |
| Soul Reaver 2 | Raziel |
| Blood Omen 2 | Kain |
| Defiance | Kain and Raziel |

Any block attributed to any other speaker is dialogue by definition.
