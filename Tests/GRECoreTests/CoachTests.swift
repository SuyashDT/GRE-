import XCTest
@testable import GRECore

/// The coach's folder: `plan.json` and `drills-*.json`.
final class CoachTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var folders: [URL] = []

    override func tearDown() {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
        super.tearDown()
    }

    func loadLibrary() throws -> ContentLibrary {
        guard ContentLibrary.bundledContentFolder() != nil else {
            throw XCTSkip("Content folder not built yet")
        }
        return try ContentLibrary.loadBundled()
    }

    func makeFolder(_ files: [String: String]) throws -> CoachFolder {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gre-coach-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folders.append(url)
        for (name, text) in files {
            try Data(text.utf8).write(to: url.appendingPathComponent(name))
        }
        return CoachFolder(url: url)
    }

    func date(_ day: Int, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    func decodePlan(_ json: String) throws -> CoachPlanFile {
        try JSONDecoder().decode(CoachPlanFile.self, from: Data(json.utf8))
    }

    func resolve(_ json: String, library: ContentLibrary) throws -> CoachPlan.Resolved {
        CoachPlan.resolve(try decodePlan(json), content: library, newCardsPerDay: 20, calendar: calendar)
    }

    /// A drills file with one set. `extra` is spliced into the set, e.g. `"timeLimitMinutes": 9,`.
    func drillsJSON(set: String, questions: [String], extra: String = "", measure: String = "verbal",
                    stimulus: String? = nil) -> String {
        let stimuli = stimulus.map { """
            "stimuli": [ { "id": "\($0)", "kind": "passage", "paragraphs": [["Sentence one.", "Sentence two."]] } ],
            """ } ?? ""
        let body = questions.enumerated().map { index, id -> String in
            if index == 0, let stimulus {
                return """
                { "id": "\(id)", "category": "readingComprehension", "topic": "Detail", "difficulty": 2, "format": "single",
                  "stimulusId": "\(stimulus)", "prompt": "What does the passage say?", "options": ["A", "B", "C", "D", "E"],
                  "correct": [1], "explanation": "Sentence two says so directly." }
                """
            }
            return """
            { "id": "\(id)", "category": "textCompletion", "topic": "Contrast", "difficulty": 3, "format": "blanks",
              "prompt": "Although the plan was _____, it failed.", "blanks": [["sound", "flawed", "late", "odd", "new"]],
              "correct": [0], "explanation": "Although signals a contrast with failing." }
            """
        }.joined(separator: ",\n")
        return """
        { \(stimuli)
          "sets": [ { "id": "\(set)", "title": "Set \(set)", "measure": "\(measure)", \(extra)
                      "summary": "A set from the coach.", "questions": [ \(body) ] } ] }
        """
    }

    // MARK: Data folder

    func testDataFolderCanBeMovedWithTheEnvironment() {
        let standard = DataFolder.url(environment: [:])
        XCTAssertEqual(standard.lastPathComponent, "GRE Prep")
        XCTAssertFalse(DataFolder.isOverridden(environment: [:]))
        XCTAssertFalse(DataFolder.isOverridden(environment: [DataFolder.environmentKey: "  "]))

        let moved = DataFolder.url(environment: [DataFolder.environmentKey: "/tmp/gre-prep-test-data"])
        XCTAssertEqual(moved.path, "/tmp/gre-prep-test-data")
        XCTAssertTrue(DataFolder.isOverridden(environment: [DataFolder.environmentKey: "/tmp/gre-prep-test-data"]))
    }

    // MARK: Plan file

    func testPlanFileKeepsGoodItemsAndNotesTheBrokenOnes() throws {
        let file = try decodePlan("""
        { "version": 1, "title": "GRE on Fri 18 Dec", "examDate": "2026-12-18", "updated": "2026-11-22",
          "note": "Lighter days first.", "futureField": { "ignored": true },
          "days": [
            { "date": "2026-11-22", "focus": "Baseline", "tasks": [
                { "id": "a", "kind": "lesson", "ref": "gre-overview" },
                { "id": "b", "kind": "note", "title": "Class", "minutes": "sixty" },
                { "kind": "note", "title": "No id" },
                "not a task",
                { "id": "c", "kind": "vocabulary", "minutes": 30 } ] },
            { "focus": "No date" },
            { "date": "2026-11-23" } ] }
        """)
        XCTAssertEqual(file.title, "GRE on Fri 18 Dec")
        XCTAssertEqual(file.examDate, "2026-12-18")
        XCTAssertEqual(file.days.map(\.date), ["2026-11-22", "2026-11-23"])
        XCTAssertEqual(file.days[0].tasks.map(\.id), ["a", "c"])
        XCTAssertEqual(file.days[1].tasks, [])
        XCTAssertEqual(file.skipped.count, 4)
        XCTAssertTrue(file.skipped.contains { $0.contains("day 2") && $0.contains("missing \"date\"") }, "\(file.skipped)")
        XCTAssertTrue(file.skipped.contains { $0.contains("2026-11-22, task 2") && $0.contains("minutes") }, "\(file.skipped)")
        XCTAssertTrue(file.skipped.contains { $0.contains("2026-11-22, task 3") && $0.contains("missing \"id\"") }, "\(file.skipped)")
        XCTAssertTrue(file.skipped.contains { $0.contains("2026-11-22, task 4") }, "\(file.skipped)")

        XCTAssertThrowsError(try decodePlan("{ \"title\": \"No days\" }"))
        XCTAssertThrowsError(try decodePlan("not json"))
    }

    func testPlanResolvesAgainstTheContent() throws {
        let library = try loadLibrary()
        let resolved = try resolve("""
        { "version": 1, "title": "GRE on Fri 18 Dec", "examDate": "2026-12-18", "updated": "2026-11-22", "note": "Lighter days first.",
          "days": [
            { "date": "2026-11-24", "focus": "Build 1", "tasks": [
                { "id": "1124-tc", "kind": "lesson", "ref": "tc" },
                { "id": "1124-tc-drill", "kind": "drill", "ref": "d-tc" },
                { "id": "1124-gone", "kind": "drill", "ref": "no-such-set" },
                { "id": "1124-new", "kind": "flashmob", "title": "Something new" } ] },
            { "date": "2026-11-22", "focus": "  ", "tasks": [
                { "id": "1122-overview", "kind": "lesson", "ref": "gre-overview" },
                { "id": "1122-mock1", "kind": "mockTest", "ref": "mock-test-1", "title": "Diagnostic: Mock Test 1", "detail": "One sitting.", "minutes": 118 },
                { "id": "1122-class", "kind": "note", "title": "Class with Claude", "detail": "Say \\"class\\" in the chat.", "minutes": 60 },
                { "id": "1122-book", "kind": "note", "title": "Book the exam", "carryOver": true },
                { "id": "1122-vocab", "kind": "vocabulary", "detail": "Your first 20 words.", "minutes": 30 },
                { "id": "1122-vocab", "kind": "vocabulary" } ] },
            { "date": "2026-11-22", "tasks": [ { "id": "dup-day", "kind": "rest" } ] },
            { "date": "24 Nov", "tasks": [ { "id": "bad-date", "kind": "rest" } ] },
            { "date": "2026-12-12", "tasks": [ { "id": "1212-rest", "kind": "rest", "title": "Day off" } ] },
            { "date": "2026-12-18", "tasks": [ { "id": "1218-exam", "kind": "exam" } ] } ] }
        """, library: library)
        let plan = try XCTUnwrap(resolved.plan)

        // Days are sorted, and days that are missing from the file are simply not there.
        XCTAssertEqual(plan.days.map(\.id), ["2026-11-22", "2026-11-24", "2026-12-12", "2026-12-18"])
        XCTAssertEqual(plan.examDate, date(18, month: 12))
        XCTAssertTrue(plan.isCoachPlan)
        XCTAssertEqual(plan.coach?.title, "GRE on Fri 18 Dec")
        XCTAssertEqual(plan.coach?.updated, date(22))
        XCTAssertEqual(plan.coach?.note, "Lighter days first.")
        XCTAssertNil(plan.day(for: date(23), calendar: calendar))

        let first = plan.days[0]
        XCTAssertNil(first.focus, "a blank focus counts as none")
        XCTAssertEqual(first.tasks.map(\.id), ["1122-overview", "1122-mock1", "1122-class", "1122-book", "1122-vocab"])
        XCTAssertEqual(first.tasks.map(\.kind), [.lesson("gre-overview"), .mockTest("mock-test-1"), .note, .note, .vocabulary])
        // Titles, details and minutes come from the content unless the coach gives them.
        let overview = try XCTUnwrap(library.lesson(id: "gre-overview"))
        XCTAssertEqual(first.tasks[0].title, "Lesson: \(overview.title)")
        XCTAssertEqual(first.tasks[0].detail, overview.summary)
        XCTAssertEqual(first.tasks[0].minutes, overview.minutes)
        XCTAssertEqual(first.tasks[1].title, "Diagnostic: Mock Test 1")
        XCTAssertEqual(first.tasks[1].detail, "One sitting.")
        XCTAssertEqual(first.tasks[2].minutes, 60)
        XCTAssertEqual(first.tasks[4].minutes, 30)
        // Only a note the coach marked stays in the catch-up list.
        XCTAssertFalse(first.tasks[2].carriesOver)
        XCTAssertTrue(first.tasks[3].carriesOver)
        XCTAssertTrue(first.tasks[0].carriesOver)
        XCTAssertFalse(first.tasks[2].isTrackedInApp)

        let second = plan.days[1]
        XCTAssertEqual(second.focus, "Build 1")
        XCTAssertEqual(second.tasks.map(\.kind), [.lesson("tc"), .drill("d-tc"), .note, .note])
        XCTAssertEqual(second.tasks[1].title, "Drill: \(try XCTUnwrap(library.drillSet(id: "d-tc")).title)")
        XCTAssertEqual(second.tasks[2].title, "Drill: no-such-set")
        XCTAssertEqual(second.tasks[3].title, "Something new")

        XCTAssertTrue(plan.days[2].isRestDay)
        XCTAssertEqual(plan.days[2].tasks[0].title, "Day off")
        XCTAssertEqual(plan.days[3].phase, .examDay)
        XCTAssertEqual(plan.days[3].tasks.map(\.kind), [.examDay])
        XCTAssertEqual(plan.days[2].phase, .finalWeek)
        XCTAssertEqual(plan.days[0].phase, .practice)

        // Every item that was dropped or downgraded is reported, in one line each.
        XCTAssertEqual(resolved.problems.count, 5, "\(resolved.problems)")
        XCTAssertEqual(plan.coach?.problems, resolved.problems)
        XCTAssertTrue(resolved.problems.contains { $0.contains("no-such-set") && $0.contains("shown as a note") })
        XCTAssertTrue(resolved.problems.contains { $0.contains("flashmob") })
        XCTAssertTrue(resolved.problems.contains { $0.contains("1122-vocab") && $0.contains("used twice") })
        XCTAssertTrue(resolved.problems.contains { $0.contains("2026-11-22 appears twice") })
        XCTAssertTrue(resolved.problems.contains { $0.contains("24 Nov") })
        XCTAssertTrue(resolved.problems.allSatisfy { !$0.contains("\n") })
    }

    func testPlanWithoutUsableDaysIsNotShown() throws {
        let library = try loadLibrary()
        let empty = try resolve("{ \"days\": [] }", library: library)
        XCTAssertNil(empty.plan)
        XCTAssertFalse(empty.problems.isEmpty)
        let badDates = try resolve("{ \"days\": [ { \"date\": \"2026-02-31\", \"tasks\": [] } ] }", library: library)
        XCTAssertNil(badDates.plan)

        // Without an examDate, the day with the exam task is the test day, else the last day.
        let byTask = try resolve("""
        { "days": [ { "date": "2026-12-10", "tasks": [ { "id": "x", "kind": "exam" } ] },
                    { "date": "2026-12-12", "tasks": [ { "id": "y", "kind": "rest" } ] } ] }
        """, library: library)
        XCTAssertEqual(byTask.plan?.examDate, date(10, month: 12))
        let byLastDay = try resolve("{ \"days\": [ { \"date\": \"2026-12-09\", \"tasks\": [ { \"id\": \"y\", \"kind\": \"rest\" } ] } ] }", library: library)
        XCTAssertEqual(byLastDay.plan?.examDate, date(9, month: 12))
    }

    func testDayKeysParseStrictly() {
        XCTAssertEqual(StudyCalendar.date(fromDayKey: "2026-11-22", calendar: calendar), date(22))
        for bad in ["2026-11-31", "2026-13-01", "26-11-22", "2026-11-2", "2026/11/22", "", "tomorrow"] {
            XCTAssertNil(StudyCalendar.date(fromDayKey: bad, calendar: calendar), bad)
        }
    }

    // MARK: Ticking

    func testCoachTasksTickLikeGeneratedOnes() throws {
        let library = try loadLibrary()
        let plan = try XCTUnwrap(resolve("""
        { "examDate": "2026-12-18", "days": [
            { "date": "2026-11-24", "tasks": [
                { "id": "lesson", "kind": "lesson", "ref": "tc" },
                { "id": "drill", "kind": "drill", "ref": "d-tc" },
                { "id": "mock", "kind": "mockTest", "ref": "mock-test-1" },
                { "id": "vocab", "kind": "vocabulary" },
                { "id": "class", "kind": "note", "title": "Class" } ] },
            { "date": "2026-11-26", "tasks": [ { "id": "drill-again", "kind": "drill", "ref": "d-tc" } ] } ] }
        """, library: library).plan)
        let day = plan.days[0]
        let later = plan.days[1]
        func task(_ id: String) throws -> PlanTask { try XCTUnwrap((day.tasks + later.tasks).first { $0.id == id }) }
        func done(_ id: String, _ progress: ProgressData) throws -> Bool {
            let found = try task(id)
            let on = later.tasks.contains(found) ? later.date : day.date
            return StudyPlan.isDone(found, on: on, progress: progress, calendar: calendar)
        }
        var progress = ProgressData()
        for id in ["lesson", "drill", "mock", "vocab", "class", "drill-again"] {
            XCTAssertFalse(try done(id, progress), id)
        }

        progress.lessonsRead.insert("tc")
        XCTAssertTrue(try done("lesson", progress))

        // A drill counts when it was done on or after the task's day, not before.
        progress.drillAttempts.append(DrillAttempt(setId: "d-tc", date: day.date.addingTimeInterval(-3600), results: []))
        XCTAssertFalse(try done("drill", progress))
        progress.drillAttempts.append(DrillAttempt(setId: "d-tc", date: day.date.addingTimeInterval(86400 + 3600), results: []))
        XCTAssertTrue(try done("drill", progress))
        // The second time the drill is planned needs an attempt on or after that second day.
        XCTAssertFalse(try done("drill-again", progress))
        progress.drillAttempts.append(DrillAttempt(setId: "d-tc", date: later.date.addingTimeInterval(60), results: []))
        XCTAssertTrue(try done("drill-again", progress))

        // The same for a mock test: an earlier attempt doesn't count, an unfinished one doesn't either.
        func attempt(finished: Date, completed: Bool) -> MockAttempt {
            MockAttempt(id: UUID(), testId: "mock-test-1", startedAt: finished.addingTimeInterval(-7000), finishedAt: finished,
                        completed: completed, sections: [], essay: nil, verbal: nil, quant: nil, responses: [:])
        }
        progress.mockAttempts = [attempt(finished: day.date.addingTimeInterval(-60), completed: true),
                                 attempt(finished: day.date.addingTimeInterval(7200), completed: false)]
        XCTAssertFalse(try done("mock", progress))
        progress.mockAttempts.append(attempt(finished: day.date.addingTimeInterval(9000), completed: true))
        XCTAssertTrue(try done("mock", progress))

        // Vocabulary counts on the day cards were reviewed.
        let reviewed = day.date.addingTimeInterval(7200)
        progress.cards["w"] = CardState(wordId: "w", ease: 2.5, intervalDays: 1, repetitions: 1, lapses: 0,
                                        due: reviewed, firstSeen: reviewed, lastReviewed: reviewed)
        XCTAssertTrue(try done("vocab", progress))

        // A note is ticked by hand, by its id, and the tick survives the coach rewriting the plan.
        XCTAssertFalse(StudyPlan.isCompletedInApp(try task("class"), on: day.date, progress: progress, calendar: calendar))
        progress.planChecked.insert("class")
        XCTAssertTrue(try done("class", progress))
        let rewritten = try XCTUnwrap(resolve("""
        { "days": [ { "date": "2026-11-25", "tasks": [ { "id": "class", "kind": "note", "title": "Class, moved a day" } ] } ] }
        """, library: library).plan)
        XCTAssertTrue(StudyPlan.isDone(rewritten.days[0].tasks[0], on: rewritten.days[0].date, progress: progress, calendar: calendar))
    }

    func testEarlyStartWarningNamesTheLaterDay() throws {
        let library = try loadLibrary()
        let plan = try XCTUnwrap(resolve("""
        { "days": [ { "date": "2026-11-22", "tasks": [ { "id": "m1", "kind": "mockTest", "ref": "mock-test-1" } ] },
                    { "date": "2026-12-06", "tasks": [ { "id": "m2", "kind": "mockTest", "ref": "mock-test-2" } ] } ] }
        """, library: library).plan)
        let noon: (Date) -> Date = { $0.addingTimeInterval(12 * 3600) }
        XCTAssertEqual(CoachPlan.upcomingDay(forMockTest: "mock-test-2", in: plan, now: noon(date(22)), calendar: calendar), date(6, month: 12))
        XCTAssertNil(CoachPlan.upcomingDay(forMockTest: "mock-test-2", in: plan, now: noon(date(6, month: 12)), calendar: calendar))
        XCTAssertNil(CoachPlan.upcomingDay(forMockTest: "mock-test-2", in: plan, now: noon(date(7, month: 12)), calendar: calendar))
        XCTAssertNil(CoachPlan.upcomingDay(forMockTest: "mock-test-1", in: plan, now: noon(date(22)), calendar: calendar))
        XCTAssertNil(CoachPlan.upcomingDay(forMockTest: "mock-test-2", in: nil, now: noon(date(22)), calendar: calendar))
        // The app's own generated plan never asks.
        let generated = StudyPlan.make(
            settings: StudyPlanSettings(examDate: date(11, month: 12), startDate: date(2), minutesPerDay: 60),
            content: library, newCardsPerDay: 20, calendar: calendar
        )
        XCTAssertFalse(generated.isCoachPlan)
        XCTAssertNil(CoachPlan.upcomingDay(forMockTest: "mock-test-2", in: generated, now: noon(date(2)), calendar: calendar))
    }

    // MARK: Coach sets

    func testCoachSetsAreMergedNewestFirst() throws {
        let library = try loadLibrary()
        let folder = try makeFolder([
            "drills-2026-11-24.json": drillsJSON(set: "coach-1124", questions: ["c24-01", "c24-02"], stimulus: "c24-p1"),
            "drills-2026-11-25.json": drillsJSON(set: "coach-1125", questions: ["c25-01", "c25-02", "c25-03"],
                                                 extra: "\"timeLimitMinutes\": 5, \"note\": \"Aim for 90 seconds a question.\","),
            "notes.txt": "Not for the app.",
        ])
        let coach = folder.load(bundled: library)
        XCTAssertEqual(coach.drillProblems, [])
        XCTAssertEqual(coach.sets.map(\.id), ["coach-1125", "coach-1124"])
        XCTAssertNil(coach.planFile)
        XCTAssertEqual(coach.planProblems, [])

        let timed = coach.sets[0]
        XCTAssertTrue(timed.isTimed)
        XCTAssertEqual(timed.timeLimitMinutes, 5)
        XCTAssertEqual(timed.note, "Aim for 90 seconds a question.")
        XCTAssertNil(timed.category)
        XCTAssertEqual(timed.categoryTitle, "Mixed")
        XCTAssertEqual(timed.categories, [.textCompletion])
        let mixed = coach.sets[1]
        XCTAssertFalse(mixed.isTimed)
        XCTAssertEqual(mixed.categories, [.readingComprehension, .textCompletion])

        let merged = library.adding(coach)
        XCTAssertEqual(merged.coachDrillSets.map(\.id), ["coach-1125", "coach-1124"])
        XCTAssertEqual(merged.bundledDrillSets.map(\.id), library.drills.sets.map(\.id), "bundled sets stay first and unchanged")
        XCTAssertTrue(merged.isCoachSet("coach-1124"))
        XCTAssertFalse(merged.isCoachSet("d-tc"))
        XCTAssertNotNil(merged.drillSet(id: "coach-1125"))
        let passageQuestion = try XCTUnwrap(merged.question(id: "c24-01"))
        XCTAssertEqual(merged.stimulus(for: passageQuestion)?.id, "c24-p1")
        // A mock-test question finds its passage in its own test.
        let mockQuestion = try XCTUnwrap(library.mockTests[0].allQuestions.first { $0.stimulusId != nil })
        XCTAssertEqual(merged.stimulus(for: mockQuestion), library.mockTests[0].stimulus(mockQuestion.stimulusId))

        // Merging again after a reload replaces the coach's sets rather than piling them up.
        let fewer = CoachContent(stimuli: [], sets: [timed])
        let again = merged.adding(fewer)
        XCTAssertEqual(again.coachDrillSets.map(\.id), ["coach-1125"])
        XCTAssertEqual(again.drills.sets.count, library.drills.sets.count + 1)
        XCTAssertEqual(again.drills.stimuli, library.drills.stimuli)
        XCTAssertEqual(library.adding(.empty).drills, library.drills)

        // A plan can point at a coach set once it is merged in.
        let plan = try XCTUnwrap(CoachPlan.resolve(
            try decodePlan("{ \"days\": [ { \"date\": \"2026-11-25\", \"tasks\": [ { \"id\": \"t\", \"kind\": \"drill\", \"ref\": \"coach-1125\" } ] } ] }"),
            content: merged, newCardsPerDay: 20, calendar: calendar
        ).plan)
        XCTAssertEqual(plan.days[0].tasks[0].kind, .drill("coach-1125"))
        XCTAssertEqual(plan.days[0].tasks[0].title, "Timed set: Set coach-1125")
        XCTAssertTrue(plan.coach?.problems.isEmpty == true)
    }

    func testBrokenAndClashingCoachFilesAreLeftOut() throws {
        let library = try loadLibrary()
        let folder = try makeFolder([
            "drills-01-good.json": drillsJSON(set: "coach-good", questions: ["cg-01"]),
            "drills-02-broken.json": "{ \"sets\": [ { \"id\": ",
            "drills-03-set-clash.json": drillsJSON(set: "d-tc", questions: ["cs-01"]),
            "drills-04-question-clash.json": drillsJSON(set: "coach-q", questions: ["d-tc-01"]),
            "drills-05-stimulus-clash.json": drillsJSON(set: "coach-s", questions: ["cx-01"], stimulus: "d-p1"),
            "drills-06-same-as-good.json": drillsJSON(set: "coach-good", questions: ["ch-01"]),
            "drills-07-wrong-measure.json": drillsJSON(set: "coach-m", questions: ["cm-01"], measure: "quant"),
            "drills-08-wrong-category.json": drillsJSON(set: "coach-c", questions: ["cc-01"], extra: "\"category\": \"sentenceEquivalence\","),
            "drills-09-no-questions.json": drillsJSON(set: "coach-e", questions: []),
            "drills-10-missing-passage.json": drillsJSON(set: "coach-p", questions: ["cp-01"], stimulus: "cp-p1")
                .replacingOccurrences(of: "\"stimulusId\": \"cp-p1\"", with: "\"stimulusId\": \"nowhere\""),
            "drills-11-bad-limit.json": drillsJSON(set: "coach-l", questions: ["cl-01"], extra: "\"timeLimitMinutes\": 0,"),
            "drills-12-bad-type.json": drillsJSON(set: "coach-t", questions: ["ct-01"])
                .replacingOccurrences(of: "\"textCompletion\"", with: "\"wordSearch\""),
            "drills-13-also-good.json": drillsJSON(set: "coach-also", questions: ["ca-01"]),
        ])
        let coach = folder.load(bundled: library)
        XCTAssertEqual(coach.sets.map(\.id), ["coach-also", "coach-good"])
        XCTAssertEqual(coach.drillProblems.count, 11, "\(coach.drillProblems)")
        func problem(_ file: String) -> String { coach.drillProblems.first { $0.hasPrefix(file) } ?? "" }
        XCTAssertTrue(problem("drills-02-broken.json").contains("isn't valid JSON"), problem("drills-02-broken.json"))
        XCTAssertTrue(problem("drills-03-set-clash.json").contains("set id \"d-tc\" is already used"))
        XCTAssertTrue(problem("drills-04-question-clash.json").contains("question id \"d-tc-01\" is already used"))
        XCTAssertTrue(problem("drills-05-stimulus-clash.json").contains("stimulus id \"d-p1\" is already used"))
        XCTAssertTrue(problem("drills-06-same-as-good.json").contains("set id \"coach-good\" is already used"))
        XCTAssertTrue(problem("drills-07-wrong-measure.json").contains("not a Quant question"))
        XCTAssertTrue(problem("drills-08-wrong-category.json").contains("Sentence Equivalence"))
        XCTAssertTrue(problem("drills-09-no-questions.json").contains("no questions"))
        XCTAssertTrue(problem("drills-10-missing-passage.json").contains("nowhere"))
        XCTAssertTrue(problem("drills-11-bad-limit.json").contains("time limit"))
        XCTAssertTrue(problem("drills-12-bad-type.json").contains("category"), problem("drills-12-bad-type.json"))
        XCTAssertTrue(coach.drillProblems.allSatisfy { !$0.contains("\n") && $0.contains("was left out") })

        // The bundled content is untouched by any of it.
        XCTAssertEqual(library.adding(coach).bundledDrillSets, library.drills.sets)
    }

    func testFolderReportsAPlanItCannotReadAndNoticesChanges() throws {
        let library = try loadLibrary()
        let missing = CoachFolder(url: FileManager.default.temporaryDirectory.appendingPathComponent("gre-coach-none-\(UUID().uuidString)"))
        XCTAssertEqual(missing.load(bundled: library), .empty)
        XCTAssertEqual(missing.signature(), "")

        let folder = try makeFolder(["plan.json": "{ \"days\": "])
        var coach = folder.load(bundled: library)
        XCTAssertNil(coach.planFile)
        XCTAssertEqual(coach.planProblems.count, 1)
        XCTAssertTrue(coach.planProblems[0].hasPrefix("plan.json couldn't be read"), coach.planProblems[0])

        let before = folder.signature()
        XCTAssertTrue(before.contains("plan.json"))
        try Data("{ \"updated\": \"2026-11-22\", \"days\": [ { \"date\": \"2026-11-22\", \"tasks\": [ { \"id\": \"a\", \"kind\": \"rest\" }, 7 ] } ] }".utf8)
            .write(to: folder.url.appendingPathComponent("plan.json"))
        XCTAssertNotEqual(folder.signature(), before, "a rewritten file changes the signature")
        coach = folder.load(bundled: library)
        XCTAssertEqual(coach.planFile?.days.count, 1)
        XCTAssertEqual(coach.planProblems.count, 1)
        XCTAssertTrue(coach.planProblems[0].hasPrefix("plan.json: 2026-11-22, task 2"), coach.planProblems[0])

        let withPlan = folder.signature()
        try Data(drillsJSON(set: "coach-new", questions: ["cn-01"]).utf8)
            .write(to: folder.url.appendingPathComponent("drills-new.json"))
        XCTAssertNotEqual(folder.signature(), withPlan, "a new file changes the signature")
        XCTAssertEqual(folder.load(bundled: library).sets.map(\.id), ["coach-new"])
        try FileManager.default.removeItem(at: folder.url.appendingPathComponent("plan.json"))
        XCTAssertFalse(folder.signature().contains("plan.json"))
    }

    /// The example in docs/examples/coach is what docs/COACH.md points coaches to, so the app must accept all of it.
    func testTheDocumentedExampleIsAccepted() throws {
        let library = try loadLibrary()
        let example = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/examples/coach", isDirectory: true)
        guard FileManager.default.fileExists(atPath: example.appendingPathComponent("plan.json").path) else {
            throw XCTSkip("docs/examples/coach isn't next to the sources")
        }
        let coach = CoachFolder(url: example).load(bundled: library)
        XCTAssertEqual(coach.drillProblems, [])
        XCTAssertEqual(coach.planProblems, [])
        XCTAssertEqual(coach.sets.map(\.id), ["example-verbal-timed", "example-quant-mixed"])
        XCTAssertEqual(coach.sets.map(\.isTimed), [true, false])

        let merged = library.adding(coach)
        let resolved = CoachPlan.resolve(try XCTUnwrap(coach.planFile), content: merged, newCardsPerDay: 20, calendar: calendar)
        XCTAssertEqual(resolved.problems, [])
        let plan = try XCTUnwrap(resolved.plan)
        XCTAssertEqual(plan.days.count, 5)
        XCTAssertEqual(plan.examDate, date(18, month: 12))
        let kinds = plan.days.flatMap(\.tasks).map(\.kind)
        XCTAssertTrue(kinds.contains(.drill("example-verbal-timed")))
        XCTAssertTrue(kinds.contains(.mockTest("mock-test-2")))
        XCTAssertEqual(kinds.last, .examDay)

        // Every example question accepts its own key, like the bundled ones.
        for question in coach.sets.flatMap(\.questions) {
            var response = Response()
            switch question.format {
            case .single, .multiple, .sentence: response.selected = Set(question.correct ?? [])
            case .blanks: response.blankChoices = (question.correct ?? []).map { Optional($0) }
            case .numeric, .fraction: response.numberText = NumberFormatting.plain(try XCTUnwrap(question.answerValue))
            }
            if question.format == .fraction { response.denominatorText = "1" }
            XCTAssertTrue(question.isCorrect(response), question.id)
        }
    }

    /// Set `GREPREP_COACH_CHECK_DIR` to a real Coach folder to check that the app accepts everything in it.
    func testCoachFolderNamedInTheEnvironmentIsClean() throws {
        guard let path = ProcessInfo.processInfo.environment["GREPREP_COACH_CHECK_DIR"], !path.isEmpty else {
            throw XCTSkip("Set GREPREP_COACH_CHECK_DIR to check a Coach folder")
        }
        let library = try loadLibrary()
        let coach = CoachFolder(url: URL(fileURLWithPath: path, isDirectory: true)).load(bundled: library)
        XCTAssertEqual(coach.drillProblems, [])
        XCTAssertEqual(coach.planProblems, [])
        let merged = library.adding(coach)
        if let file = coach.planFile {
            let resolved = CoachPlan.resolve(file, content: merged, newCardsPerDay: 20)
            XCTAssertNotNil(resolved.plan)
            XCTAssertEqual(resolved.problems, [])
            let tasks = resolved.plan?.days.flatMap(\.tasks) ?? []
            print("Coach plan: \(resolved.plan?.days.count ?? 0) days, \(tasks.count) tasks, test on \(resolved.plan.map { StudyCalendar.dayKey($0.examDate) } ?? "?")")
        }
        print("Coach sets: \(merged.coachDrillSets.map(\.id))")
    }
}
