# Content format

All study content lives in `Sources/GRECore/Resources/Content/` as JSON. The app
decodes these files at launch, so you can add questions, drills, words or lessons
without touching Swift code. Run the validator after every edit:

```sh
python3 scripts/validate_content.py Sources/GRECore/Resources/Content/*.json
```

| File | Contents |
| --- | --- |
| `mock-test-1.json` | One full-length mock test (essay + 6 sections, adaptive) |
| `drills-verbal.json`, `drills-quant.json` | Untimed practice sets by question type |
| `vocabulary.json` | Flashcard words |
| `lessons.json` | Strategy lessons |

Text fields are plain text with light Markdown (`*italic*`, `**bold**`). Maths uses
Unicode (x², √, π, ≤, ≥, ×, ÷, °, −) and slashes for fractions — there is no LaTeX.
There are no images; describe geometry in words ("A right triangle has legs 6 and 8…").

## Question

```jsonc
{
  "id": "m1-v1-01",                 // unique across all files
  "category": "textCompletion",     // see categories below
  "topic": "Contrast",              // see topics below
  "difficulty": 3,                  // 1 (easiest) – 5 (hardest)
  "format": "blanks",               // single | multiple | blanks | numeric | fraction | sentence
  "stimulusId": "m1-p1",            // optional: the passage or data set this question uses
  "prompt": "Question stem…",
  "options": ["…"],                 // single / multiple
  "blanks": [["…","…","…"]],        // blanks: 1 blank → 5 options; 2–3 blanks → 3 options each
  "selectCount": 2,                 // multiple: exact number to pick (omit for "select all that apply")
  "correct": [1],                   // see below
  "quantityA": "…", "quantityB": "…",   // quantitative comparison only
  "answerValue": 12.5,              // numeric / fraction
  "answerDisplay": "12.5",          // numeric / fraction: how the answer is shown in review
  "entryPrefix": "$", "entrySuffix": "%",  // optional labels around the numeric entry box
  "explanation": "Why the answer is right and the traps are wrong."
}
```

`correct` by format:

- `single` — `[index]`
- `multiple` — sorted indices of every correct option
- `blanks` — one option index per blank, in blank order
- `sentence` — `[sentenceIndex]`, counting every sentence in the passage from 0
  (across paragraphs)
- `numeric` / `fraction` — omit; use `answerValue`. Equivalent fractions are
  accepted (6/8 = 3/4), as on the real test.

### Categories and how to build each

| Category | Measure | Format | Notes |
| --- | --- | --- | --- |
| `textCompletion` | verbal | `blanks` | Mark blanks in the prompt as `(i) _____`, `(ii) _____`, `(iii) _____`; single-blank prompts use `_____`. |
| `sentenceEquivalence` | verbal | `multiple` | Exactly 6 options, `selectCount: 2`, two correct. |
| `readingComprehension` | verbal | `single`, `multiple` (select all that apply, 3 options, no `selectCount`), or `sentence` | Needs a `passage` stimulus. |
| `quantitativeComparison` | quant | `single` | No `options` — the app shows the four standard choices. `correct`: 0 = A greater, 1 = B greater, 2 = equal, 3 = cannot be determined. |
| `problemSolving` | quant | `single` | Five options. |
| `multipleAnswer` | quant | `multiple` | "Select all that apply" style; may set `selectCount` when the stem says "Indicate two…". |
| `numericEntry` | quant | `numeric` or `fraction` | |
| `dataInterpretation` | quant | any quant format | Needs a `data` stimulus. |

### Topics

- Quant: `Arithmetic`, `Algebra`, `Geometry`, `Data Analysis`
- Text Completion / Sentence Equivalence: `Contrast`, `Continuation`,
  `Cause and Effect`, `Definition`
- Reading Comprehension: `Main Idea`, `Detail`, `Inference`, `Function`,
  `Strengthen/Weaken`, `Assumption`, `Vocabulary in Context`, `Author's Attitude`,
  `Select-in-Passage`

## Stimulus

```jsonc
// Reading passage. Each paragraph is a list of sentences, so select-in-passage
// questions can refer to a sentence by index.
{ "id": "m1-p1", "kind": "passage", "title": "optional",
  "paragraphs": [["Sentence one.", "Sentence two."], ["Next paragraph."]] }

// Data set for data interpretation.
{ "id": "m1-d1", "kind": "data", "title": "Regional Sales, 2021–2024",
  "intro": "optional sentence shown above the data",
  "tables": [{ "title": "optional", "columns": ["Year", "North", "South"],
               "rows": [["2021", "120", "95"]] }],
  "charts": [{ "title": "…", "type": "bar", "xLabel": "Year", "yLabel": "Units (thousands)",
               "categories": ["2021", "2022"],
               "series": [{ "name": "North", "values": [120, 135] }] }] }
```

Chart `type` is `bar`, `line` or `pie` (pie: exactly one series). Each series has
one value per category.

## Mock test

```jsonc
{
  "id": "mock-1", "title": "…", "description": "…", "formatVersion": "2023-09 shorter GRE",
  "essay": { "id": "…", "statement": "…", "instructions": "…", "minutes": 30 },
  "order": ["verbal-1", "quant-1", "verbal-2", "quant-2"],
  "routing": { "verbal": 7, "quant": 7 },   // stage-1 correct answers needed for the harder stage 2
  "stimuli": [ … ],
  "sections": [
    { "id": "V1",  "measure": "verbal", "stage": 1, "tier": "standard", "minutes": 18, "questions": [12 questions] },
    { "id": "V2E", "measure": "verbal", "stage": 2, "tier": "easier",   "minutes": 23, "questions": [15] },
    { "id": "V2H", "measure": "verbal", "stage": 2, "tier": "harder",   "minutes": 23, "questions": [15] },
    { "id": "Q1",  "measure": "quant",  "stage": 1, "tier": "standard", "minutes": 21, "questions": [12] },
    { "id": "Q2E", "measure": "quant",  "stage": 2, "tier": "easier",   "minutes": 26, "questions": [15] },
    { "id": "Q2H", "measure": "quant",  "stage": 2, "tier": "harder",   "minutes": 26, "questions": [15] }
  ]
}
```

## Drill library

```jsonc
{ "stimuli": [ … ],
  "sets": [ { "id": "d-tc", "title": "Text Completion", "measure": "verbal",
              "category": "textCompletion", "summary": "…", "questions": [ … ] } ] }
```

## Vocabulary

```jsonc
{ "words": [ { "word": "laconic", "partOfSpeech": "adjective",
               "definition": "using very few words",
               "example": "His laconic reply—\"No.\"—ended the meeting.",
               "synonyms": ["terse", "succinct"], "tier": 1 } ] }
```

`tier`: 1 = most frequent on the GRE, 3 = less common.

## Lessons

```jsonc
{ "lessons": [ { "id": "tc", "title": "Text Completion", "measure": "verbal",
                 "category": "textCompletion", "minutes": 6, "summary": "…",
                 "blocks": [ { "heading": "…", "body": "Markdown paragraphs…" } ],
                 "keyTips": ["…"], "commonTraps": ["…"],
                 "example": { "question": "…", "walkthrough": "…" },   // optional
                 "drillId": "d-tc" } ] }                               // optional
```

`measure`: `verbal`, `quant`, `writing` or `general`.
