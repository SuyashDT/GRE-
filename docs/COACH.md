# Coach files

A coach (a tutor, or Claude) can steer GRE Prep without rebuilding it, by writing files into one folder:

```
~/Library/Application Support/GRE Prep/Coach/
  plan.json        the study plan the app shows
  drills-*.json    extra practice sets, timed or untimed
```

- The app only reads this folder. It never writes, moves or deletes anything in it.
- The coach writes only inside this folder. Progress stays in `progress.json` next to it, which the coach can read: see [What the coach can read back](#what-the-coach-can-read-back).
- The app reads the folder when it opens, each time it comes back to the front, and every 20 seconds while it is open. A running mock test or timed set is never interrupted; the folder is read when it ends.
- A file the app can't use is left out, and one line on the screen it belongs to says why: the Study Plan screen for `plan.json`, Practice Drills for a drills file. Nothing in this folder can stop the app's own content from loading.
- Other files in the folder are ignored.

Check the folder before the learner sees it:

```sh
python3 scripts/validate_content.py --coach "$HOME/Library/Application Support/GRE Prep/Coach"
```

A complete example is in [docs/examples/coach](examples/coach).

## plan.json

When this file exists and can be read, the Study Plan screen, today's plan on the Dashboard and the sidebar badge show it in place of the plan the app generates. The screen says the plan is from the coach and when it was last updated. Remove the file and the app's own plan comes back.

```json
{
  "version": 1,
  "title": "GRE on Fri 11 Dec",
  "examDate": "2026-12-11",
  "updated": "2026-11-22",
  "note": "IELTS comes first, so GRE is lighter until 5 Dec.",
  "days": [
    {
      "date": "2026-11-22",
      "focus": "Baseline",
      "tasks": [
        { "id": "1122-overview", "kind": "lesson", "ref": "gre-overview" },
        { "id": "1122-mock1", "kind": "mockTest", "ref": "mock-test-1",
          "title": "Diagnostic: Mock Test 1", "detail": "One sitting. No pausing.", "minutes": 118 },
        { "id": "1122-class", "kind": "note", "title": "Class with Claude",
          "detail": "Say \"class\" in the chat.", "minutes": 60 },
        { "id": "1122-vocab", "kind": "vocabulary", "detail": "Your first 20 words.", "minutes": 30 }
      ]
    }
  ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `version` | no | `1`. |
| `title` | no | Shown after "From your coach". |
| `examDate` | no | The test date. Without it, the day that holds the `exam` task is used, else the last day. |
| `updated` | no | When the coach last changed the plan. Shown on the screen. |
| `note` | no | One line from the coach, shown at the top of the plan. |
| `days` | yes | The days, in any order. Days may be missing; a missing day shows nothing. |
| `days[].date` | yes | A local calendar day, `yyyy-MM-dd`. Each day once. |
| `days[].focus` | no | A headline for the day, such as "Baseline". |
| `days[].tasks` | yes | The day's tasks, in the order to show them. |

### Tasks

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique in the plan. Ticks are stored by id, so keep an id the same when you rewrite the plan and the tick stays. |
| `kind` | yes | See the table below. |
| `ref` | for `lesson`, `drill`, `mockTest` | The id of the lesson, drill set or mock test. |
| `title`, `detail`, `minutes` | no | Default to the lesson's, set's or test's own, as in a generated plan. A `note` needs a `title`. |
| `carryOver` | no | For a `note`: `true` keeps it in the Catch up list until it is ticked. |

| `kind` | `ref` | Button | Ticks itself when |
| --- | --- | --- | --- |
| `lesson` | a lesson id, such as `tc` | Read | the lesson has been read |
| `drill` | a drill set id: the app's own, a coach's, or `missed-verbal` / `missed-quant` | Practise | the set was done on or after the task's day |
| `mockTest` | `mock-test-1` or `mock-test-2` | Go to Test | the test was completed on or after the task's day |
| `vocabulary` | none | Study | any card was reviewed that day |
| `note` | none | none | never: the learner ticks it. Use it for anything outside the app, such as a class or an official practice test |
| `rest` | none | none | never, and it has no tick. A day whose only task is `rest` is shown as a rest day |
| `exam` | none | none | never: the learner can tick it, but it doesn't count towards progress |

- An unknown `kind`, or a `ref` that doesn't exist, is shown as a note, and the Study Plan screen says so in one line. So a plan can name a coach set before the set's file is written, at the cost of that line.
- Unfinished `lesson`, `drill` and `mockTest` tasks from earlier days stay in the Catch up list, as in a generated plan. A `note` does only with `carryOver`.
- Any task except `rest` can be ticked by hand.
- Starting a mock test that the plan has on a later day asks first, and names that day. This keeps a dress rehearsal new.

Ids to use in `ref`:

- Lessons: `gre-overview`, `vocab-strategy`, `quant-review`, `tc`, `qc`, `calculator`, `se`, `ps`, `awa-issue`, `rc`, `ma`, `ne`, `rc-arguments`, `di`, `pacing`
- The app's drill sets: `d-tc`, `d-se`, `d-rc`, `d-qc`, `d-ps`, `d-ma`, `d-ne`, `d-di`
- The missed questions: `missed-verbal`, `missed-quant` (see below)
- Mock tests: `mock-test-1`, `mock-test-2`

### Missed questions

The app keeps two sets of its own, shown at the top of Practice Drills when they have anything in them: every Verbal question, and every Quant question, whose latest answer was wrong or left blank, in a drill, a coach's set or a mock test. Answering a question correctly anywhere takes it off the list. A plan can send the learner there with a `drill` task whose `ref` is `missed-verbal` or `missed-quant`; the task ticks itself when the set is redone on or after that day. If nothing is missed that day, the learner ticks it by hand. A coach's own sets may not use these two ids.

### If something is wrong

A day or task that can't be read is left out and the rest of the plan is shown, with one line on the Study Plan screen naming the first problem. If the whole file can't be read (it isn't valid JSON, or has no `days`), the app shows its own plan and says the coach's couldn't be read.

## drills-*.json

Any file named `drills-` something `.json` adds practice sets. They appear in Practice Drills under "From your coach", newest file name first, so date the names: `drills-2026-11-24-verbal.json`.

The format is the app's own [drill library](CONTENT_FORMAT.md#drill-library), with the same question and stimulus rules, plus three optional fields on a set:

```json
{
  "stimuli": [ { "id": "c1124-p1", "kind": "passage", "paragraphs": [["Sentence one.", "Sentence two."]] } ],
  "sets": [
    {
      "id": "coach-1124-verbal",
      "title": "Tue 24 Nov: Verbal from your Mock Test 1 mistakes",
      "measure": "verbal",
      "summary": "Text Completion and Reading Comprehension, the two types you missed most.",
      "timeLimitMinutes": 18,
      "note": "Predict the word before you look at the choices.",
      "questions": [ … ]
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `category` | Leave it out for a set that mixes question types. The set is then shown as "Mixed". Every question must still belong to the set's `measure`. With a `category`, every question must be of that type. |
| `timeLimitMinutes` | Makes the set a timed one. It runs like a section of the real test: a countdown, free movement between questions, Mark and Review, the calculator for Quant, and no answers until the learner finishes or the time runs out. Then the results show every explanation. The real test allows 18 minutes for 12 Verbal questions and 21 for 12 Quant. |
| `note` | A line from the coach, shown on the set. |

`stimuli` may be left out when no question needs one. A set needs at least one question.

Ids must be new: a set id, question id or stimulus id that the app's own content or an earlier coach file already uses makes the app leave the whole file out. Start coach ids with something of your own, such as `coach-1124-`.

Without `timeLimitMinutes` a set runs like the app's own drills: one question at a time, with the answer and the explanation after each.

## What the coach can read back

Results are saved in `~/Library/Application Support/GRE Prep/progress.json` as drill attempts, the same as the app's own drills, so the Dashboard counts them. Read the file; don't write it.

```json
{
  "setId": "coach-1124-verbal",
  "date": "2026-11-24T05:10:00Z",
  "timed": true,
  "timeLimitMinutes": 18,
  "secondsUsed": 1012.5,
  "results": [
    { "questionId": "c1124-01", "category": "textCompletion", "topic": "Contrast", "difficulty": 3,
      "answered": true, "correct": false, "seconds": 96.2,
      "response": { "selected": [], "blankChoices": [3], "numberText": "", "denominatorText": "" } }
  ]
}
```

- `response` is what the learner answered, so you can see which wrong answer was picked: `selected` holds option indexes (or the sentence index for select-in-passage), `blankChoices` one option index for each blank, `numberText` the number typed, and `denominatorText` the bottom of a fraction. A question the learner left blank has no `response`.
- `seconds` is the time spent looking at that question.
- A timed attempt lists every question in the set. An untimed one lists the questions the learner checked or skipped.
- Attempts saved before coach sets existed have no `timed` and no `response`.

Mock test attempts are under `mockAttempts`, with every answer in `responses`.

## Checking a build without touching real data

Set `GREPREP_DATA_DIR` to another folder and the app keeps `progress.json` and looks for `Coach/` there instead:

```sh
GREPREP_DATA_DIR="$(mktemp -d)" swift run GREPrep
```

Launch arguments open a screen and can save a picture of the window. The `-UITestBackground YES` argument keeps the window invisible and takes no focus, so a check can run while someone is using the Mac:

```sh
DATA="$(mktemp -d)" && cp -R docs/examples/coach "$DATA/Coach"
GREPREP_DATA_DIR="$DATA" "build/GRE Prep.app/Contents/MacOS/GREPrep" \
  -UITestScreen studyPlan -UITestBackground YES -UITestSnapshot /tmp/plan.png
```

`-UITestScreen` takes `dashboard`, `studyPlan`, `mockTests`, `drills`, `vocabulary` or `lessons`. `-UITestDrill <set id>` opens a set, and `-UITestStartTimed YES` starts it if it is timed.
