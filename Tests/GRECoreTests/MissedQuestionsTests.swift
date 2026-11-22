import XCTest
@testable import GRECore

final class MissedQuestionsTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func loadLibrary() throws -> ContentLibrary {
        guard ContentLibrary.bundledContentFolder() != nil else {
            throw XCTSkip("Content folder not built yet")
        }
        return try ContentLibrary.loadBundled()
    }

    func result(_ id: String, _ category: QuestionCategory = .textCompletion, correct: Bool, answered: Bool = true) -> QuestionResult {
        QuestionResult(questionId: id, category: category, topic: "Contrast", difficulty: 3,
                       answered: answered, correct: correct, seconds: 60)
    }

    func hour(_ hour: Int) -> Date { Date(timeIntervalSince1970: 1_795_000_000 + Double(hour) * 3600) }

    func testOnlyTheLatestAnswerCounts() {
        var progress = ProgressData()
        XCTAssertEqual(MissedQuestions.questionIds(in: progress), [])

        progress.drillAttempts = [
            DrillAttempt(setId: "d-tc", date: hour(1), results: [
                result("a", correct: false), result("b", correct: true), result("c", correct: false, answered: false),
            ]),
            DrillAttempt(setId: "d-tc", date: hour(3), results: [
                result("a", correct: true),    // fixed
                result("b", correct: false),   // was right, now wrong
            ]),
        ]
        XCTAssertEqual(MissedQuestions.questionIds(in: progress), ["c", "b"], "the longest-standing miss comes first")

        // A mock test in between is part of the same history: its questions count, and
        // a later drill answer overrides it.
        let section = SectionResult(sectionId: "V1", measure: .verbal, stage: 1, tier: .standard, minutesAllowed: 18,
                                    secondsUsed: 900, questions: [result("c", correct: true), result("m", correct: false, answered: false)])
        progress.mockAttempts = [MockAttempt(id: UUID(), testId: "mock-test-1", startedAt: hour(1), finishedAt: hour(2),
                                             completed: true, sections: [section], essay: nil, verbal: nil, quant: nil, responses: [:])]
        XCTAssertEqual(MissedQuestions.questionIds(in: progress), ["m", "b"])

        progress.drillAttempts.append(DrillAttempt(setId: MissedQuestions.setId(for: .verbal), date: hour(4), results: [
            result("m", correct: true), result("b", correct: true),
        ]))
        XCTAssertEqual(MissedQuestions.questionIds(in: progress), [], "answering a question correctly takes it off the list")
    }

    func testSetsAreSplitByMeasureAndBuiltFromRealQuestions() throws {
        let library = try loadLibrary()
        let verbal = try XCTUnwrap(library.drillSet(id: "d-tc")).questions
        let quant = try XCTUnwrap(library.drillSet(id: "d-qc")).questions
        let mock = try XCTUnwrap(library.mockTests[0].allQuestions.first { $0.stimulusId != nil && $0.category.measure == .verbal })

        var progress = ProgressData()
        XCTAssertNil(MissedQuestions.set(for: .verbal, progress: progress, content: library))

        progress.drillAttempts = [DrillAttempt(setId: "d-tc", date: hour(1), results: [
            result(verbal[0].id, correct: false),
            result(verbal[1].id, correct: true),
            result(quant[0].id, .quantitativeComparison, correct: false),
            result(mock.id, mock.category, correct: false),
            result("no-longer-in-the-app", correct: false),
        ])]

        let verbalSet = try XCTUnwrap(MissedQuestions.set(for: .verbal, progress: progress, content: library))
        XCTAssertEqual(verbalSet.id, "missed-verbal")
        XCTAssertEqual(verbalSet.measure, .verbal)
        XCTAssertEqual(verbalSet.questions.map(\.id), [verbal[0].id, mock.id])
        XCTAssertFalse(verbalSet.isTimed)
        XCTAssertNil(verbalSet.category)
        // A mock-test question brings its passage along.
        XCTAssertNotNil(library.stimulus(for: mock))

        let quantSet = try XCTUnwrap(MissedQuestions.set(for: .quant, progress: progress, content: library))
        XCTAssertEqual(quantSet.id, "missed-quant")
        XCTAssertEqual(quantSet.questions.map(\.id), [quant[0].id])

        // Redoing the set records an attempt under its id; what was answered correctly drops out.
        let redo = verbalSet.makeAttempt(
            responses: [verbal[0].id: Response(blankChoices: (verbal[0].correct ?? []).map { Optional($0) })],
            timeSpent: [:], including: [verbal[0].id], timed: false, date: hour(2)
        )
        XCTAssertEqual(redo.setId, "missed-verbal")
        XCTAssertEqual(redo.results.map(\.correct), [true])
        progress.drillAttempts.append(redo)
        XCTAssertEqual(MissedQuestions.set(for: .verbal, progress: progress, content: library)?.questions.map(\.id), [mock.id])
    }

    func testIdsAreReservedAndAPlanCanPointAtThem() throws {
        let library = try loadLibrary()
        XCTAssertEqual(MissedQuestions.reservedSetIds, ["missed-verbal", "missed-quant"])
        XCTAssertEqual(MissedQuestions.measure(forSetId: "missed-quant"), .quant)
        XCTAssertNil(MissedQuestions.measure(forSetId: "d-tc"))
        XCTAssertNil(library.drillSet(id: "missed-verbal"), "the sets are made from progress, not stored in the library")

        // A coach's file can't take one of the ids.
        let question = try XCTUnwrap(library.drillSet(id: "d-tc")).questions[0]
        let clash = DrillSet(id: "missed-verbal", title: "t", measure: .verbal, summary: "s",
                             questions: [Question(id: "new-q", category: .textCompletion, topic: "Contrast", difficulty: 1,
                                                  format: question.format, prompt: "p", blanks: question.blanks,
                                                  correct: question.correct, explanation: "e")])
        let problems = CoachFolder.problems(sets: [clash], stimuli: [], takenSets: MissedQuestions.reservedSetIds,
                                            takenQuestions: [], takenStimuli: [])
        XCTAssertEqual(problems, ["set id \"missed-verbal\" is already used"])

        // A coach's plan can ask for the missed questions; the task ticks when the set is redone that day or later.
        let file = try JSONDecoder().decode(CoachPlanFile.self, from: Data("""
        { "days": [ { "date": "2026-12-07", "tasks": [
            { "id": "1207-missed-v", "kind": "drill", "ref": "missed-verbal" },
            { "id": "1207-missed-q", "kind": "drill", "ref": "missed-quant", "title": "Quant error log" } ] } ] }
        """.utf8))
        let resolved = CoachPlan.resolve(file, content: library, newCardsPerDay: 20, calendar: calendar)
        XCTAssertEqual(resolved.problems, [])
        let day = try XCTUnwrap(resolved.plan?.days.first)
        XCTAssertEqual(day.tasks.map(\.kind), [.drill("missed-verbal"), .drill("missed-quant")])
        XCTAssertEqual(day.tasks[0].title, "Redo your missed Verbal questions")
        XCTAssertEqual(day.tasks[1].title, "Quant error log")

        var progress = ProgressData()
        XCTAssertFalse(StudyPlan.isDone(day.tasks[0], on: day.date, progress: progress, calendar: calendar))
        progress.drillAttempts.append(DrillAttempt(setId: "missed-verbal", date: day.date.addingTimeInterval(3600), results: []))
        XCTAssertTrue(StudyPlan.isDone(day.tasks[0], on: day.date, progress: progress, calendar: calendar))
        XCTAssertFalse(StudyPlan.isDone(day.tasks[1], on: day.date, progress: progress, calendar: calendar))
    }
}
