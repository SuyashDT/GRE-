# GRE Prep for Mac

A native macOS app (SwiftUI) for GRE General Test preparation, with a full-length
mock test built to the **current shorter GRE format**, essay grading by Claude through
**Claude Code**, practice drills, vocabulary flashcards, strategy lessons and a progress
dashboard.

## What's inside

| | |
| --- | --- |
| **Mock Test 1** | Analyze an Issue essay, two Verbal and two Quant sections. Section 2 of each measure adapts to how you did in section 1. 84 original questions (the easier and harder second sections are both included). |
| **Exam interface** | Modelled on the real test: Quit / Exit Section / Review / Mark / Back / Next, a section timer you can hide, a Review screen, the on-screen calculator (order of operations, memory, Transfer Display), and an essay editor with spell-check turned off. |
| **Score report** | Estimated Verbal and Quant scores (130–170) with likely range, which second-section tier you reached, per-question correctness and timing, and full explanations. |
| **Essay grading** | Claude grades the essay on the 0–6 Issue rubric through the Claude Code CLI, with a score per criterion, strengths, improvements and next steps. You can also score it yourself against the rubric. |
| **Practice drills** | 58 untimed questions in 8 sets, one per question type, with an explanation after each answer. |
| **Vocabulary** | 320 high-frequency GRE words with definitions, example sentences and synonyms, scheduled with spaced repetition (SM-2). |
| **Strategy lessons** | 15 lessons: test format, pacing, the Issue essay, every question type, the calculator and a quant review. |
| **Dashboard** | Score history, accuracy by question type and content area, time per question against target pace, study streak and suggested next steps. |

### The test format it follows

The GRE has used this shorter format since 22 September 2023:

| Section | Questions | Time |
| --- | --- | --- |
| Analytical Writing (always first): Analyze an Issue | 1 essay | 30 min |
| Verbal Reasoning, section 1 | 12 | 18 min |
| Verbal Reasoning, section 2 (adaptive) | 15 | 23 min |
| Quantitative Reasoning, section 1 | 12 | 21 min |
| Quantitative Reasoning, section 2 (adaptive) | 15 | 26 min |
| **Total** | | **1 h 58 min**, no scheduled break, no unscored section |

## Requirements

- macOS 14 Sonoma or later
- Xcode 15.3 or later (or just the Xcode Command Line Tools) to build
- [Claude Code](https://claude.com/claude-code), signed in, for essay grading (optional)

## Build and run

**In Xcode:** open `Package.swift`, choose the **GREPrep** scheme and **My Mac**, then press **⌘R**.

**As a normal app you can keep in Applications:**

```sh
scripts/build-app.sh          # or: scripts/build-app.sh --universal
open "build/GRE Prep.app"
```

**From Terminal for a quick try:** `swift run GREPrep`

**Without building:** every push builds the app on GitHub Actions. Download
`GRE-Prep-app` from the run's **Artifacts**, unzip it and move it to Applications.
That build is signed ad hoc, not notarized, so macOS blocks the first launch. On macOS 14,
right-click the app and choose **Open**. On macOS 15 or later, try to open it once, then go to
**System Settings → Privacy & Security** and click **Open Anyway**. On any version you can
instead run `xattr -dr com.apple.quarantine "/Applications/GRE Prep.app"`.

## Essay grading with Claude Code

The app runs your local `claude` command in print mode. It never asks for an API key;
it uses whatever login Claude Code already has (a Claude Pro, Max, Team or Enterprise
plan, or a Console account).

1. Install Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`
2. Run `claude` once and sign in.
3. In the app, open **Settings → Essay Grading** and click **Check Claude Code**.

When a mock test ends, the essay is sent to Claude, unless you turn that off in Settings
and grade on demand. The command is roughly:

```sh
claude -p "<instruction>" --output-format json --json-schema '<grade schema>' \
  --system-prompt '<GRE rater rubric>' --model opus --tools "" --safe-mode --no-session-persistence
```

The essay goes in on stdin. The command runs in an empty temporary folder with tools
disabled, so nothing on your Mac is read or changed. If your Claude Code version
doesn't know one of the newer flags, the app retries with a minimal set. The app
looks for `claude` in `~/.local/bin`, Homebrew and npm locations, then in your login
shell's `PATH`. You can also set the path in Settings. A grading uses a small amount of
your Claude plan's usage. Pick **Sonnet** in Settings for faster grading that uses less.

## A note on scores

ETS doesn't publish how raw scores convert to scaled scores. The Verbal and Quant
numbers are estimates from a model of section-level adaptive scoring: the harder
second section opens up the top of the 130–170 scale, and the easier one caps scores
in the mid-150s. Treat them as a practice gauge, not a prediction. The same goes for
the essay score from Claude.

All questions, passages, lessons and example sentences are original material written
for this app, in the style of the real test. They are not ETS questions.

## Project layout

```
Package.swift
Sources/GRECore/          platform-independent logic (also builds on Linux)
  Models/                 questions, passages, mock tests, drills, vocabulary, lessons
  Engine/                 answer checking, adaptive routing and scoring, calculator, spaced repetition
  Progress/               saved progress, analytics
  AI/                     essay prompt, Claude Code runner and output parsing
  Resources/Content/      all study content as JSON
Sources/GREPrep/          the SwiftUI app
Tests/GRECoreTests/       unit tests, including checks that every answer key is gradable
scripts/build-app.sh      builds "GRE Prep.app"
scripts/validate_content.py   checks content files
docs/CONTENT_FORMAT.md    how to add questions, drills, words and lessons
```

Progress is saved to `~/Library/Application Support/GRE Prep/progress.json`.

## Development

```sh
swift test                                                   # runs on macOS or Linux
python3 scripts/validate_content.py Sources/GRECore/Resources/Content/*.json
```

To add a second mock test, add `mock-test-2.json` next to `mock-test-1.json`. The app
loads every `mock-test-*.json` it finds. See [docs/CONTENT_FORMAT.md](docs/CONTENT_FORMAT.md).
