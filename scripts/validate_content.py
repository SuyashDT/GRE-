#!/usr/bin/env python3
"""Validate GRE Prep content JSON files.

Usage:
  python3 scripts/validate_content.py FILE [FILE ...]
      The app's own content files. The kind is detected from the top-level keys:
        "sections" -> mock test (or a mock-test part)
        "sets"     -> drill library
        "words"    -> vocabulary list
        "lessons"  -> strategy lessons

  python3 scripts/validate_content.py --coach DIR
      A coach folder (docs/COACH.md): its plan.json and drills-*.json, checked the way
      the app reads them, including ids that clash with the app's own content.

  python3 scripts/validate_content.py --plan FILE [--coach DIR]
      One coach plan. Its refs are checked against the app's content and, when --coach
      is given, the drill sets in that folder.

  --content DIR   where the app's own content is (default: Sources/GRECore/Resources/Content)

Exits non-zero and prints every problem found.
"""
import argparse
import datetime
import json
import os
import re
import sys

VERBAL_CATEGORIES = {"textCompletion", "sentenceEquivalence", "readingComprehension"}
QUANT_CATEGORIES = {"quantitativeComparison", "problemSolving", "multipleAnswer",
                    "numericEntry", "dataInterpretation"}
CATEGORIES = VERBAL_CATEGORIES | QUANT_CATEGORIES
FORMATS = {"single", "multiple", "blanks", "numeric", "fraction", "sentence"}
QUANT_TOPICS = {"Arithmetic", "Algebra", "Geometry", "Data Analysis"}
VERBAL_TOPICS = {
    # Text Completion / Sentence Equivalence
    "Contrast", "Continuation", "Cause and Effect", "Definition",
    # Reading Comprehension
    "Main Idea", "Detail", "Inference", "Function", "Strengthen/Weaken",
    "Assumption", "Vocabulary in Context", "Author's Attitude", "Select-in-Passage",
}
MEASURES = {"verbal", "quant"}

errors = []


def err(where, msg):
    errors.append(f"{where}: {msg}")


def is_int_list(v):
    return isinstance(v, list) and all(isinstance(x, int) and not isinstance(x, bool) for x in v)


def check_stimulus(s, where):
    sid = s.get("id")
    if not isinstance(sid, str) or not sid:
        err(where, "stimulus missing id")
    kind = s.get("kind")
    if kind == "passage":
        paras = s.get("paragraphs")
        if not isinstance(paras, list) or not paras:
            err(where, "passage needs non-empty 'paragraphs' (list of lists of sentences)")
            return 0
        n = 0
        for p in paras:
            if not isinstance(p, list) or not p or not all(isinstance(x, str) and x.strip() for x in p):
                err(where, "each paragraph must be a non-empty list of sentence strings")
            else:
                n += len(p)
        return n
    if kind == "data":
        tables = s.get("tables", [])
        charts = s.get("charts", [])
        if not tables and not charts:
            err(where, "data stimulus needs at least one table or chart")
        for t in tables:
            cols = t.get("columns")
            rows = t.get("rows")
            if not isinstance(cols, list) or not cols:
                err(where, "table needs 'columns'")
                continue
            if not isinstance(rows, list) or not rows:
                err(where, "table needs 'rows'")
                continue
            for r in rows:
                if not isinstance(r, list) or len(r) != len(cols) or not all(isinstance(c, str) for c in r):
                    err(where, f"table row {r!r} must be {len(cols)} strings")
        for c in charts:
            if c.get("type") not in {"bar", "line", "pie"}:
                err(where, f"chart type must be bar/line/pie, got {c.get('type')!r}")
            cats = c.get("categories")
            series = c.get("series")
            if not isinstance(cats, list) or not cats:
                err(where, "chart needs 'categories'")
                continue
            if not isinstance(series, list) or not series:
                err(where, "chart needs 'series'")
                continue
            if c.get("type") == "pie" and len(series) != 1:
                err(where, "pie chart must have exactly one series")
            for se in series:
                vals = se.get("values")
                if not isinstance(se.get("name"), str):
                    err(where, "series needs 'name'")
                if not isinstance(vals, list) or len(vals) != len(cats) or not all(
                        isinstance(v, (int, float)) and not isinstance(v, bool) for v in vals):
                    err(where, f"series {se.get('name')!r} needs {len(cats)} numeric values")
        return 0
    err(where, f"stimulus kind must be 'passage' or 'data', got {kind!r}")
    return 0


def check_question(q, where, stimuli, measure=None):
    qid = q.get("id")
    where = f"{where} [{qid}]"
    if not isinstance(qid, str) or not qid:
        err(where, "missing id")
    cat = q.get("category")
    fmt = q.get("format")
    if cat not in CATEGORIES:
        err(where, f"bad category {cat!r}")
    if fmt not in FORMATS:
        err(where, f"bad format {fmt!r}")
    if measure == "verbal" and cat not in VERBAL_CATEGORIES:
        err(where, f"category {cat!r} not allowed in a verbal section")
    if measure == "quant" and cat not in QUANT_CATEGORIES:
        err(where, f"category {cat!r} not allowed in a quant section")
    topic = q.get("topic")
    allowed_topics = QUANT_TOPICS if cat in QUANT_CATEGORIES else VERBAL_TOPICS
    if topic not in allowed_topics:
        err(where, f"topic {topic!r} not in {sorted(allowed_topics)}")
    d = q.get("difficulty")
    if not isinstance(d, int) or not 1 <= d <= 5:
        err(where, "difficulty must be an integer 1-5")
    if not isinstance(q.get("prompt"), str) or not q["prompt"].strip():
        err(where, "missing prompt")
    if not isinstance(q.get("explanation"), str) or len(q.get("explanation", "")) < 20:
        err(where, "explanation missing or too short")

    sid = q.get("stimulusId")
    if sid is not None and sid not in stimuli:
        err(where, f"stimulusId {sid!r} not found")
    if cat == "readingComprehension" and sid is None:
        err(where, "reading comprehension question needs a stimulusId")
    if cat == "dataInterpretation":
        if sid is None:
            err(where, "data interpretation question needs a stimulusId")
        elif stimuli[sid]["kind"] != "data":
            err(where, "data interpretation stimulus must be kind 'data'")
    if cat == "readingComprehension" and sid in stimuli and stimuli[sid]["kind"] != "passage":
        err(where, "reading comprehension stimulus must be kind 'passage'")

    correct = q.get("correct")
    options = q.get("options")

    if cat == "quantitativeComparison":
        if fmt != "single":
            err(where, "quantitative comparison must use format 'single'")
        if options is not None:
            err(where, "quantitative comparison must not list options (the app supplies A-D)")
        if not isinstance(q.get("quantityA"), str) or not isinstance(q.get("quantityB"), str):
            err(where, "quantitative comparison needs quantityA and quantityB strings")
        if not (is_int_list(correct) and len(correct) == 1 and 0 <= correct[0] <= 3):
            err(where, "quantitative comparison 'correct' must be [0..3]")
        return
    if q.get("quantityA") is not None or q.get("quantityB") is not None:
        err(where, "quantityA/quantityB only allowed on quantitative comparison")

    if fmt == "single":
        if not isinstance(options, list) or len(options) < 2:
            err(where, "single needs options")
            return
        if not (is_int_list(correct) and len(correct) == 1 and 0 <= correct[0] < len(options)):
            err(where, "single 'correct' must be one valid index")
    elif fmt == "multiple":
        if not isinstance(options, list) or len(options) < 3:
            err(where, "multiple needs at least 3 options")
            return
        if not is_int_list(correct) or not correct or len(set(correct)) != len(correct) \
                or not all(0 <= c < len(options) for c in correct):
            err(where, "multiple 'correct' must be distinct valid indices")
        elif correct != sorted(correct):
            err(where, "multiple 'correct' must be sorted ascending")
        sc = q.get("selectCount")
        if sc is not None and is_int_list(correct) and sc != len(correct):
            err(where, "selectCount must equal number of correct answers")
        if cat == "sentenceEquivalence":
            if len(options) != 6 or sc != 2 or not is_int_list(correct) or len(correct) != 2:
                err(where, "sentence equivalence needs 6 options, selectCount 2, two correct")
    elif fmt == "blanks":
        blanks = q.get("blanks")
        if cat != "textCompletion":
            err(where, "format 'blanks' is only for text completion")
        if not isinstance(blanks, list) or not 1 <= len(blanks) <= 3:
            err(where, "blanks must be a list of 1-3 option lists")
            return
        need = 5 if len(blanks) == 1 else 3
        for b in blanks:
            if not isinstance(b, list) or len(b) != need or not all(isinstance(x, str) for x in b):
                err(where, f"each blank needs exactly {need} string options")
        if not (is_int_list(correct) and len(correct) == len(blanks)
                and all(0 <= c < need for c in correct)):
            err(where, "blanks 'correct' must have one valid index per blank")
        if len(blanks) > 1 and "(i)" not in q["prompt"]:
            err(where, "multi-blank prompt should mark blanks as (i), (ii), (iii)")
    elif fmt in ("numeric", "fraction"):
        av = q.get("answerValue")
        if not isinstance(av, (int, float)) or isinstance(av, bool):
            err(where, "numeric/fraction needs numeric answerValue")
        if not isinstance(q.get("answerDisplay"), str):
            err(where, "numeric/fraction needs answerDisplay string")
        if cat not in ("numericEntry", "dataInterpretation"):
            err(where, "numeric formats are for numericEntry or dataInterpretation")
    elif fmt == "sentence":
        if sid is None or stimuli.get(sid, {}).get("kind") != "passage":
            err(where, "sentence format needs a passage stimulus")
        else:
            n = stimuli[sid]["_sentences"]
            if not (is_int_list(correct) and len(correct) == 1 and 0 <= correct[0] < n):
                err(where, f"sentence 'correct' must be one index in 0..{n - 1}")


def collect_stimuli(data, where):
    stimuli = {}
    for i, s in enumerate(data.get("stimuli", [])):
        n = check_stimulus(s, f"{where} stimulus #{i}")
        sid = s.get("id")
        if sid in stimuli:
            err(where, f"duplicate stimulus id {sid}")
        stimuli[sid] = dict(s, _sentences=n)
    return stimuli


def check_ids(questions, where):
    seen = set()
    for q in questions:
        if q.get("id") in seen:
            err(where, f"duplicate question id {q.get('id')}")
        seen.add(q.get("id"))


def validate_mock(data, where):
    stimuli = collect_stimuli(data, where)
    allq = []
    for s in data["sections"]:
        sw = f"{where} section {s.get('id')}"
        if s.get("measure") not in MEASURES:
            err(sw, "measure must be verbal or quant")
        if s.get("stage") not in (1, 2):
            err(sw, "stage must be 1 or 2")
        if s.get("tier") not in ("standard", "easier", "harder"):
            err(sw, "tier must be standard/easier/harder")
        if not isinstance(s.get("minutes"), int):
            err(sw, "minutes must be an integer")
        qs = s.get("questions", [])
        expected = 12 if s.get("stage") == 1 else 15
        if len(qs) != expected:
            err(sw, f"expected {expected} questions, found {len(qs)}")
        for q in qs:
            check_question(q, sw, stimuli, s.get("measure"))
        allq.extend(qs)
    check_ids(allq, where)
    used = {q.get("stimulusId") for q in allq}
    for sid in stimuli:
        if sid not in used:
            err(where, f"stimulus {sid} is never used")
    if "essay" in data:
        e = data["essay"]
        for k in ("id", "statement", "instructions"):
            if not isinstance(e.get(k), str) or not e[k].strip():
                err(where, f"essay.{k} missing")
    return len(allq)


def validate_drills(data, where, coach=False):
    """A drill library. The app's own sets are one question type each, untimed, with at
    least 4 questions. A coach's sets (coach=True) may mix the question types of their
    measure, may be timed, may carry a note, and need only one question."""
    stimuli = collect_stimuli(data, where)
    allq = []
    sets = data.get("sets")
    if not isinstance(sets, list) or not sets:
        err(where, "needs a non-empty 'sets' list")
        return 0
    seen_sets = set()
    for s in sets:
        sw = f"{where} set {s.get('id')}"
        for k in ("id", "title", "summary"):
            if not isinstance(s.get(k), str) or not s[k].strip():
                err(sw, f"missing {k}")
        if s.get("id") in seen_sets:
            err(sw, "duplicate set id")
        seen_sets.add(s.get("id"))
        if s.get("measure") not in MEASURES:
            err(sw, "measure must be verbal or quant")
        category = s.get("category")
        if category is None and coach:
            pass  # a mixed set
        elif category not in CATEGORIES:
            err(sw, f"bad category {category!r}")
        limit = s.get("timeLimitMinutes")
        note = s.get("note")
        if coach:
            if limit is not None and (not isinstance(limit, int) or isinstance(limit, bool) or limit < 1):
                err(sw, "timeLimitMinutes must be a whole number of minutes, 1 or more")
            if note is not None and (not isinstance(note, str) or not note.strip()):
                err(sw, "note must be a non-empty string")
        elif limit is not None or note is not None:
            err(sw, "timeLimitMinutes and note are only for a coach's sets")
        qs = s.get("questions", [])
        if not isinstance(qs, list):
            err(sw, "questions must be a list")
            qs = []
        minimum = 1 if coach else 4
        if len(qs) < minimum:
            err(sw, f"a drill set needs at least {minimum} question{'s' if minimum > 1 else ''}")
        for q in qs:
            check_question(q, sw, stimuli, s.get("measure"))
            if category is not None and q.get("category") != category:
                err(sw, f"question {q.get('id')} category differs from set category")
        allq.extend(qs)
    check_ids(allq, where)
    used = {q.get("stimulusId") for q in allq}
    if coach:
        for sid in stimuli:
            if sid not in used:
                err(where, f"stimulus {sid} is never used")
    return len(allq)


# ---------------------------------------------------------------------------
# Coach folder: plan.json and drills-*.json (docs/COACH.md)

PLAN_KINDS = ("lesson", "drill", "mockTest", "vocabulary", "note", "rest", "exam")
PLAN_KINDS_WITH_REF = {"lesson": "lessons", "drill": "sets", "mockTest": "tests"}
DEFAULT_CONTENT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                               "Sources", "GRECore", "Resources", "Content")


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:  # noqa: BLE001
        err(path, f"cannot parse JSON: {e}")
        return None


def natural_key(name):
    """Sorts file names the way the app does: drills-2 before drills-10."""
    return [int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", name)]


def content_ids(folder):
    """Ids used by the app's own content: what a coach's files must not reuse, and what a plan can point to."""
    # The app makes these two sets itself, from the questions the learner last got wrong.
    ids = {"lessons": set(), "sets": {"missed-verbal", "missed-quant"}, "tests": set(),
           "questions": set(), "stimuli": set()}
    try:
        names = sorted(os.listdir(folder))
    except OSError as e:
        err(folder, f"cannot read the content folder: {e}")
        return ids
    for name in names:
        if not name.endswith(".json"):
            continue
        with open(os.path.join(folder, name), encoding="utf-8") as f:
            data = json.load(f)
        ids["stimuli"].update(s.get("id") for s in data.get("stimuli", []))
        if "sections" in data:
            ids["tests"].add(data.get("id"))
            for section in data["sections"]:
                ids["questions"].update(q.get("id") for q in section.get("questions", []))
        elif "sets" in data:
            for s in data["sets"]:
                ids["sets"].add(s.get("id"))
                ids["questions"].update(q.get("id") for q in s.get("questions", []))
        elif "lessons" in data:
            ids["lessons"].update(l.get("id") for l in data["lessons"])
    return ids


def validate_coach_drills(folder, ids):
    """Checks every drills-*.json in a coach folder, oldest name first as the app does, and
    adds the sets it accepts to `ids`. A file with any problem is left out by the app."""
    names = [n for n in os.listdir(folder) if n.startswith("drills-") and n.endswith(".json")]
    for name in sorted(names, key=natural_key):
        path = os.path.join(folder, name)
        data = load_json(path)
        if data is None:
            continue
        if not isinstance(data, dict) or "sets" not in data:
            err(path, "needs a 'sets' list")
            continue
        before = len(errors)
        n = validate_drills(data, path, coach=True)
        sets = [s for s in data.get("sets", []) if isinstance(s, dict)]
        questions = [q for s in sets for q in s.get("questions", []) if isinstance(q, dict)]
        for s in sets:
            if s.get("id") in ids["sets"]:
                err(path, f"set id {s.get('id')!r} is already used")
        for q in questions:
            if q.get("id") in ids["questions"]:
                err(path, f"question id {q.get('id')!r} is already used")
        for s in data.get("stimuli", []):
            if s.get("id") in ids["stimuli"]:
                err(path, f"stimulus id {s.get('id')!r} is already used")
        if len(errors) > before:
            continue  # the app leaves the whole file out
        ids["sets"].update(s.get("id") for s in sets)
        ids["questions"].update(q.get("id") for q in questions)
        ids["stimuli"].update(s.get("id") for s in data.get("stimuli", []))
        timed = sum(1 for s in sets if s.get("timeLimitMinutes"))
        print(f"{path}: coach drills, {len(sets)} set{'s' if len(sets) != 1 else ''} "
              f"({timed} timed), {n} questions")


def parse_day(text):
    if not isinstance(text, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        return None
    try:
        return datetime.date.fromisoformat(text)
    except ValueError:
        return None


def validate_plan(path, ids):
    data = load_json(path)
    if data is None:
        return
    if not isinstance(data, dict):
        err(path, "a plan must be a JSON object")
        return
    if data.get("version", 1) != 1:
        err(path, f"version must be 1, got {data.get('version')!r}")
    for key in ("title", "note"):
        if key in data and (not isinstance(data[key], str) or not data[key].strip()):
            err(path, f"{key} must be a non-empty string")
    for key in ("examDate", "updated"):
        if key in data and parse_day(data[key]) is None:
            err(path, f"{key} must be a date like 2026-12-11, got {data[key]!r}")
    exam_date = parse_day(data.get("examDate"))
    days = data.get("days")
    if not isinstance(days, list) or not days:
        err(path, "needs a non-empty 'days' list")
        return
    seen_days, seen_tasks, task_count = set(), set(), 0
    for i, day in enumerate(days):
        if not isinstance(day, dict):
            err(path, f"day #{i + 1} must be an object")
            continue
        date = parse_day(day.get("date"))
        where = f"{path} {day.get('date')}"
        if date is None:
            err(path, f"day #{i + 1}: date must be like 2026-11-22, got {day.get('date')!r}")
        elif date in seen_days:
            err(where, "this day appears twice")
        seen_days.add(date)
        if "focus" in day and (not isinstance(day["focus"], str) or not day["focus"].strip()):
            err(where, "focus must be a non-empty string")
        tasks = day.get("tasks")
        if not isinstance(tasks, list) or not tasks:
            err(where, "needs a non-empty 'tasks' list")
            continue
        for j, task in enumerate(tasks):
            if not isinstance(task, dict):
                err(where, f"task #{j + 1} must be an object")
                continue
            tid = task.get("id")
            tw = f"{where} [{tid}]"
            task_count += 1
            if not isinstance(tid, str) or not tid.strip():
                err(where, f"task #{j + 1} needs an id")
            elif tid in seen_tasks:
                err(tw, "task id is used twice in the plan")
            seen_tasks.add(tid)
            kind = task.get("kind")
            if kind not in PLAN_KINDS:
                err(tw, f"kind must be one of {', '.join(PLAN_KINDS)}, got {kind!r}")
                continue
            ref = task.get("ref")
            if kind in PLAN_KINDS_WITH_REF:
                if not isinstance(ref, str) or not ref:
                    err(tw, f"a {kind} task needs a ref")
                elif ref not in ids[PLAN_KINDS_WITH_REF[kind]]:
                    err(tw, f"ref {ref!r} is not a {kind} in the app's content"
                            + (" or the coach folder" if kind == "drill" else ""))
            elif ref is not None:
                err(tw, f"a {kind} task takes no ref")
            for key in ("title", "detail"):
                if key in task and (not isinstance(task[key], str) or not task[key].strip()):
                    err(tw, f"{key} must be a non-empty string")
            if kind == "note" and "title" not in task:
                err(tw, "a note needs a title")
            minutes = task.get("minutes")
            if minutes is not None and (not isinstance(minutes, int) or isinstance(minutes, bool) or minutes < 0):
                err(tw, "minutes must be a whole number, 0 or more")
            if "carryOver" in task:
                if not isinstance(task["carryOver"], bool):
                    err(tw, "carryOver must be true or false")
                elif kind != "note":
                    err(tw, "carryOver is only for notes; lessons, drills and mock tests carry over anyway")
            if kind == "exam" and exam_date and date and date != exam_date:
                err(tw, f"the exam task is on {date}, but examDate is {exam_date}")
    print(f"{path}: coach plan, {len(seen_days)} days, {task_count} tasks"
          + (f", test on {exam_date}" if exam_date else ""))


def validate_words(data, where):
    seen = set()
    for i, w in enumerate(data["words"]):
        ww = f"{where} word #{i} ({w.get('word')})"
        for k in ("word", "partOfSpeech", "definition", "example"):
            if not isinstance(w.get(k), str) or not w[k].strip():
                err(ww, f"missing {k}")
        if not isinstance(w.get("synonyms"), list):
            err(ww, "synonyms must be a list")
        if w.get("tier") not in (1, 2, 3):
            err(ww, "tier must be 1, 2 or 3")
        key = str(w.get("word", "")).lower()
        if key in seen:
            err(ww, "duplicate word")
        seen.add(key)
    return len(data["words"])


def validate_lessons(data, where):
    seen = set()
    for l in data["lessons"]:
        lw = f"{where} lesson {l.get('id')}"
        for k in ("id", "title", "summary"):
            if not isinstance(l.get(k), str) or not l[k].strip():
                err(lw, f"missing {k}")
        if l.get("measure") not in ("verbal", "quant", "writing", "general"):
            err(lw, "measure must be verbal/quant/writing/general")
        if l.get("category") is not None and l["category"] not in CATEGORIES:
            err(lw, f"bad category {l['category']!r}")
        blocks = l.get("blocks")
        if not isinstance(blocks, list) or not blocks:
            err(lw, "needs blocks")
        else:
            for b in blocks:
                if not isinstance(b.get("heading"), str) or not isinstance(b.get("body"), str):
                    err(lw, "each block needs heading and body strings")
        for k in ("keyTips", "commonTraps"):
            if not isinstance(l.get(k), list) or not all(isinstance(x, str) for x in l[k]):
                err(lw, f"{k} must be a list of strings")
        if not isinstance(l.get("minutes"), int):
            err(lw, "minutes must be an integer")
        if l.get("id") in seen:
            err(lw, "duplicate id")
        seen.add(l.get("id"))
    return len(data["lessons"])


def main(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("files", nargs="*")
    parser.add_argument("--coach")
    parser.add_argument("--plan")
    parser.add_argument("--content", default=DEFAULT_CONTENT)
    parser.add_argument("-h", "--help", action="store_true")
    args = parser.parse_args(argv)
    if args.help or not (args.files or args.coach or args.plan):
        print(__doc__)
        sys.exit(0 if args.help else 2)

    if args.coach or args.plan:
        ids = content_ids(args.content)
        if args.coach:
            if not os.path.isdir(args.coach):
                err(args.coach, "is not a folder")
            else:
                validate_coach_drills(args.coach, ids)
                plan = os.path.join(args.coach, "plan.json")
                if os.path.exists(plan):
                    validate_plan(plan, ids)
        if args.plan:
            validate_plan(args.plan, ids)

    for path in args.files:
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except Exception as e:  # noqa: BLE001
            err(path, f"cannot parse JSON: {e}")
            continue
        if "sections" in data:
            n = validate_mock(data, path)
            print(f"{path}: mock test, {n} questions")
        elif "sets" in data:
            n = validate_drills(data, path)
            print(f"{path}: drills, {n} questions")
        elif "words" in data:
            n = validate_words(data, path)
            print(f"{path}: vocabulary, {n} words")
        elif "lessons" in data:
            n = validate_lessons(data, path)
            print(f"{path}: lessons, {n} lessons")
        else:
            err(path, "unknown file kind")
    if errors:
        print(f"\n{len(errors)} problem(s):")
        for e in errors:
            print("  - " + e)
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main(sys.argv[1:])
