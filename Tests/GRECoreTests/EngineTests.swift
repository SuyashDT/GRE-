import XCTest
@testable import GRECore

final class AnswerCheckingTests: XCTestCase {
    func q(_ format: AnswerFormat, category: QuestionCategory = .problemSolving, options: [String]? = nil,
           blanks: [[String]]? = nil, selectCount: Int? = nil, correct: [Int]? = nil,
           value: Double? = nil) -> Question {
        Question(id: "t", category: category, topic: "Arithmetic", difficulty: 3, format: format,
                 prompt: "p", options: options, blanks: blanks, selectCount: selectCount,
                 correct: correct, answerValue: value, answerDisplay: value.map { "\($0)" },
                 explanation: "explanation text here")
    }

    func testSingleChoice() {
        let question = q(.single, options: ["a", "b", "c", "d", "e"], correct: [2])
        XCTAssertEqual(question.state(of: nil), .unanswered)
        XCTAssertTrue(question.isCorrect(Response(selected: [2])))
        XCTAssertFalse(question.isCorrect(Response(selected: [1])))
    }

    func testSentenceEquivalenceNeedsBoth() {
        let question = q(.multiple, category: .sentenceEquivalence, options: ["a", "b", "c", "d", "e", "f"],
                         selectCount: 2, correct: [1, 4])
        XCTAssertEqual(question.state(of: Response(selected: [1])), .incomplete)
        XCTAssertFalse(question.isCorrect(Response(selected: [1])))
        XCTAssertTrue(question.isCorrect(Response(selected: [4, 1])))
        XCTAssertFalse(question.isCorrect(Response(selected: [1, 3])))
    }

    func testSelectAllThatApplyHasNoPartialCredit() {
        let question = q(.multiple, options: ["a", "b", "c"], correct: [0, 2])
        XCTAssertEqual(question.state(of: Response(selected: [0])), .answered)
        XCTAssertFalse(question.isCorrect(Response(selected: [0])))
        XCTAssertTrue(question.isCorrect(Response(selected: [0, 2])))
    }

    func testBlanks() {
        let question = q(.blanks, category: .textCompletion,
                         blanks: [["a", "b", "c"], ["d", "e", "f"]], correct: [2, 0])
        XCTAssertEqual(question.state(of: Response(blankChoices: [2, nil])), .incomplete)
        XCTAssertTrue(question.isCorrect(Response(blankChoices: [2, 0])))
        XCTAssertFalse(question.isCorrect(Response(blankChoices: [2, 1])))
        XCTAssertEqual(question.correctAnswerText, "i. c; ii. d")
    }

    func testNumericEntry() {
        let question = q(.numeric, category: .numericEntry, value: 12.5)
        XCTAssertTrue(question.isCorrect(Response(numberText: "12.5")))
        XCTAssertTrue(question.isCorrect(Response(numberText: "12.50")))
        XCTAssertFalse(question.isCorrect(Response(numberText: "12.4")))
        XCTAssertEqual(question.state(of: Response(numberText: "1.2.3")), .incomplete)
        XCTAssertEqual(AnswerChecker.parse(".5"), 0.5)
        XCTAssertEqual(AnswerChecker.parse(AnswerChecker.normalized("−3")), -3)
        XCTAssertNil(AnswerChecker.parse("3-"))
        XCTAssertTrue(q(.numeric, category: .numericEntry, value: 1500).isCorrect(Response(numberText: "1,500")))
    }

    func testFractionAcceptsEquivalentForms() {
        let question = q(.fraction, category: .numericEntry, value: 7.0 / 12.0)
        XCTAssertTrue(question.isCorrect(Response(numberText: "7", denominatorText: "12")))
        XCTAssertTrue(question.isCorrect(Response(numberText: "14", denominatorText: "24")))
        XCTAssertFalse(question.isCorrect(Response(numberText: "7", denominatorText: "13")))
        XCTAssertEqual(question.state(of: Response(numberText: "7", denominatorText: "0")), .incomplete)
        XCTAssertEqual(question.state(of: Response(numberText: "7")), .incomplete)
    }

    func testQuantitativeComparisonOptions() {
        let question = Question(id: "qc", category: .quantitativeComparison, topic: "Algebra", difficulty: 2,
                                format: .single, prompt: "x > 0", correct: [3], quantityA: "x", quantityB: "x²",
                                explanation: "Depends on whether x is less than 1.")
        XCTAssertEqual(question.displayOptions.count, 4)
        XCTAssertTrue(question.correctAnswerText.hasPrefix("D."))
    }
}

final class ScoringTests: XCTestCase {
    func testRouting() {
        XCTAssertEqual(ScoreEstimator.route(stage1Correct: 7, threshold: 7), .harder)
        XCTAssertEqual(ScoreEstimator.route(stage1Correct: 6, threshold: 7), .easier)
    }

    func testScaleEndpoints() {
        let perfect = ScoreEstimator.estimate(measure: .quant, stage1Correct: 12, stage1Count: 12,
                                              stage2Correct: 15, stage2Count: 15, tier: .harder, threshold: 7)
        XCTAssertEqual(perfect.scaled, 170)
        XCTAssertEqual(perfect.high, 170)
        let zero = ScoreEstimator.estimate(measure: .verbal, stage1Correct: 0, stage1Count: 12,
                                           stage2Correct: 0, stage2Count: 15, tier: .easier, threshold: 7)
        XCTAssertEqual(zero.scaled, 130)
        XCTAssertEqual(zero.low, 130)
        let easierBest = ScoreEstimator.estimate(measure: .verbal, stage1Correct: 6, stage1Count: 12,
                                                 stage2Correct: 15, stage2Count: 15, tier: .easier, threshold: 7)
        XCTAssertEqual(easierBest.scaled, ScoreEstimator.easierPathCeiling)
    }

    func testHarderPathBeatsEasierPathForSameRawScore() {
        let harder = ScoreEstimator.estimate(measure: .verbal, stage1Correct: 7, stage1Count: 12,
                                             stage2Correct: 8, stage2Count: 15, tier: .harder, threshold: 7)
        let easier = ScoreEstimator.estimate(measure: .verbal, stage1Correct: 6, stage1Count: 12,
                                             stage2Correct: 9, stage2Count: 15, tier: .easier, threshold: 7)
        XCTAssertEqual(harder.rawCorrect, easier.rawCorrect)
        XCTAssertGreaterThan(harder.scaled, easier.scaled)
    }

    func testScoresAreMonotonic() {
        for tier in [TestSection.Tier.easier, .harder] {
            var previous = 0
            for stage2 in 0...15 {
                let stage1 = tier == .harder ? 9 : 4
                let score = ScoreEstimator.estimate(measure: .quant, stage1Correct: stage1, stage1Count: 12,
                                                    stage2Correct: stage2, stage2Count: 15, tier: tier, threshold: 7).scaled
                XCTAssertGreaterThanOrEqual(score, previous)
                previous = score
            }
        }
    }
}

final class ExamRunTests: XCTestCase {
    func makeQuestion(_ id: String, measure: Measure) -> Question {
        Question(id: id, category: measure == .verbal ? .textCompletion : .problemSolving,
                 topic: measure == .verbal ? "Contrast" : "Arithmetic", difficulty: 3,
                 format: measure == .verbal ? .blanks : .single, prompt: "p",
                 options: measure == .quant ? ["1", "2", "3", "4", "5"] : nil,
                 blanks: measure == .verbal ? [["a", "b", "c", "d", "e"]] : nil,
                 correct: [0], explanation: "explanation text here")
    }

    func makeSection(_ id: String, _ measure: Measure, stage: Int, tier: TestSection.Tier) -> TestSection {
        let count = stage == 1 ? 12 : 15
        return TestSection(id: id, measure: measure, stage: stage, tier: tier, minutes: 20,
                           questions: (1...count).map { makeQuestion("\(id)-\($0)", measure: measure) })
    }

    func makeTest() -> MockTest {
        MockTest(
            id: "mock-test", title: "T", description: "D", formatVersion: "x",
            essay: EssayTask(id: "e", statement: "S", instructions: "I", minutes: 30),
            order: ["verbal-1", "quant-1", "verbal-2", "quant-2"],
            routing: .init(verbal: 7, quant: 7),
            stimuli: [],
            sections: [
                makeSection("V1", .verbal, stage: 1, tier: .standard),
                makeSection("V2E", .verbal, stage: 2, tier: .easier),
                makeSection("V2H", .verbal, stage: 2, tier: .harder),
                makeSection("Q1", .quant, stage: 1, tier: .standard),
                makeSection("Q2E", .quant, stage: 2, tier: .easier),
                makeSection("Q2H", .quant, stage: 2, tier: .harder),
            ]
        )
    }

    func answer(_ run: inout ExamRun, _ section: TestSection, correctCount: Int) {
        for (index, question) in section.questions.enumerated() {
            let choice = index < correctCount ? 0 : 1
            if question.format == .blanks {
                run.responses[question.id] = Response(blankChoices: [choice])
            } else {
                run.responses[question.id] = Response(selected: [choice])
            }
        }
    }

    func testAdaptiveRoutingAndAttempt() throws {
        var run = ExamRun(test: makeTest())
        XCTAssertEqual(run.steps, [.essay, .section(.verbal, stage: 1), .section(.quant, stage: 1),
                                   .section(.verbal, stage: 2), .section(.quant, stage: 2)])
        XCTAssertNil(run.currentSection())
        run.essayText = "One two three."
        run.advance()

        let verbal1 = try XCTUnwrap(run.currentSection())
        XCTAssertEqual(verbal1.id, "V1")
        answer(&run, verbal1, correctCount: 10)
        run.advance()

        let quant1 = try XCTUnwrap(run.currentSection())
        XCTAssertEqual(quant1.id, "Q1")
        answer(&run, quant1, correctCount: 3)
        run.advance()

        let verbal2 = try XCTUnwrap(run.currentSection())
        XCTAssertEqual(verbal2.id, "V2H", "10/12 on stage 1 should route to the harder section")
        answer(&run, verbal2, correctCount: 12)
        run.advance()

        let quant2 = try XCTUnwrap(run.currentSection())
        XCTAssertEqual(quant2.id, "Q2E", "3/12 on stage 1 should route to the easier section")
        // Asking again must not re-route.
        XCTAssertEqual(run.currentSection()?.id, "Q2E")
        answer(&run, quant2, correctCount: 15)
        run.advance()
        XCTAssertTrue(run.isFinished)

        let attempt = run.makeAttempt()
        XCTAssertTrue(attempt.completed)
        XCTAssertEqual(attempt.sections.map(\.sectionId), ["V1", "Q1", "V2H", "Q2E"])
        XCTAssertEqual(attempt.verbal?.rawCorrect, 22)
        XCTAssertEqual(attempt.verbal?.stage2Tier, .harder)
        XCTAssertEqual(attempt.quant?.rawCorrect, 18)
        XCTAssertLessThanOrEqual(attempt.quant?.scaled ?? 999, ScoreEstimator.easierPathCeiling)
        XCTAssertEqual(attempt.essay?.wordCount, 3)
    }

    func testQuittingEarlyIsIncomplete() {
        var run = ExamRun(test: makeTest())
        run.advance()
        _ = run.currentSection()
        let attempt = run.makeAttempt()
        XCTAssertFalse(attempt.completed)
        XCTAssertNil(attempt.verbal)
    }
}

final class SpacedRepetitionTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testIntervalsGrow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = SpacedRepetition.review(nil, wordId: "w", rating: .good, now: now, calendar: calendar)
        XCTAssertEqual(state.intervalDays, 1)
        state = SpacedRepetition.review(state, wordId: "w", rating: .good, now: now, calendar: calendar)
        XCTAssertEqual(state.intervalDays, 3)
        state = SpacedRepetition.review(state, wordId: "w", rating: .good, now: now, calendar: calendar)
        XCTAssertEqual(state.intervalDays, 8)
        let easy = SpacedRepetition.review(state, wordId: "w", rating: .easy, now: now, calendar: calendar)
        XCTAssertGreaterThan(easy.intervalDays, 8)
        XCTAssertGreaterThan(easy.ease, state.ease)
    }

    func testAgainResetsAndLowersEase() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var state = SpacedRepetition.review(nil, wordId: "w", rating: .good, now: now, calendar: calendar)
        state = SpacedRepetition.review(state, wordId: "w", rating: .good, now: now, calendar: calendar)
        let missed = SpacedRepetition.review(state, wordId: "w", rating: .again, now: now, calendar: calendar)
        XCTAssertEqual(missed.intervalDays, 0)
        XCTAssertEqual(missed.repetitions, 0)
        XCTAssertEqual(missed.lapses, 1)
        XCTAssertLessThan(missed.ease, state.ease)
        XCTAssertEqual(missed.due.timeIntervalSince(now), 600, accuracy: 1)
        XCTAssertGreaterThanOrEqual(missed.ease, SpacedRepetition.minimumEase)
    }

    func testQueueRespectsNewCardLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let words = (0..<30).map {
            VocabWord(word: "word\($0)", partOfSpeech: "noun", definition: "d", example: "e", synonyms: [], tier: 1)
        }
        var cards: [String: CardState] = [:]
        // Two cards seen yesterday and now due; three new cards already introduced today.
        let yesterday = now.addingTimeInterval(-86_400)
        for word in words.prefix(2) {
            cards[word.id] = CardState(wordId: word.id, ease: 2.5, intervalDays: 1, repetitions: 1, lapses: 0,
                                       due: now.addingTimeInterval(-60), firstSeen: yesterday, lastReviewed: yesterday)
        }
        for word in words[2..<5] {
            cards[word.id] = CardState(wordId: word.id, ease: 2.5, intervalDays: 1, repetitions: 1, lapses: 0,
                                       due: now.addingTimeInterval(86_400), firstSeen: now, lastReviewed: now)
        }
        let queue = SpacedRepetition.queue(words: words, cards: cards, newPerDay: 10, now: now, calendar: calendar)
        XCTAssertEqual(queue.prefix(2).map(\.id), ["word0", "word1"])
        XCTAssertEqual(queue.count, 2 + 7)
    }

    func testStreak() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let days: Set<String> = [0, 1, 2, 4].reduce(into: []) { set, offset in
            set.insert(StudyCalendar.dayKey(now.addingTimeInterval(-86_400 * Double(offset)), calendar: calendar))
        }
        XCTAssertEqual(StudyCalendar.streak(days: days, now: now, calendar: calendar), 3)
        XCTAssertEqual(StudyCalendar.streak(days: [], now: now, calendar: calendar), 0)
    }
}

final class CalculatorTests: XCTestCase {
    func run(_ keys: [CalculatorKey]) -> CalculatorEngine {
        var calculator = CalculatorEngine()
        keys.forEach { calculator.press($0) }
        return calculator
    }

    func digits(_ text: String) -> [CalculatorKey] {
        text.map { $0 == "." ? .decimalPoint : .digit(Int(String($0))!) }
    }

    func testOrderOfOperations() {
        let calculator = run(digits("2") + [.add] + digits("3") + [.multiply] + digits("4") + [.equals])
        XCTAssertEqual(calculator.display, "14")
    }

    func testParentheses() {
        let calculator = run([.openParen] + digits("2") + [.add] + digits("3") + [.closeParen, .multiply] + digits("4") + [.equals])
        XCTAssertEqual(calculator.display, "20")
    }

    func testDivisionAndDecimals() {
        XCTAssertEqual(run(digits("1") + [.divide] + digits("3") + [.equals]).display, "0.3333333")
        XCTAssertEqual(run(digits("0.5") + [.multiply] + digits("4") + [.equals]).display, "2")
        XCTAssertEqual(run(digits("7") + [.divide] + digits("0") + [.equals]).display, "Error")
    }

    func testSquareRootAndNegate() {
        XCTAssertEqual(run(digits("144") + [.squareRoot]).display, "12")
        XCTAssertEqual(run(digits("5") + [.negate]).display, "-5")
        XCTAssertEqual(run(digits("4") + [.negate, .squareRoot]).display, "Error")
        // Typing after √ starts a new number.
        XCTAssertEqual(run(digits("9") + [.squareRoot] + digits("2")).display, "2")
    }

    func testChainingFromResult() {
        XCTAssertEqual(run(digits("6") + [.multiply] + digits("7") + [.equals, .subtract] + digits("2") + [.equals]).display, "40")
    }

    func testMemory() {
        var calculator = run(digits("12") + [.memoryAdd, .clear] + digits("3") + [.add, .memoryRecall, .equals])
        XCTAssertEqual(calculator.display, "15")
        XCTAssertTrue(calculator.hasMemory)
        calculator.press(.memoryClear)
        XCTAssertFalse(calculator.hasMemory)
    }

    func testDigitLimitAndOverflow() {
        XCTAssertEqual(run(digits("1234567890")).display, "12345678")
        XCTAssertEqual(run(digits("99999999") + [.multiply] + digits("10") + [.equals]).display, "Error")
        XCTAssertEqual(run(digits("99999999") + [.multiply] + digits("10") + [.equals, .clear]).display, "0")
    }

    func testShowsRunningValue() {
        let calculator = run(digits("2") + [.add] + digits("3") + [.add])
        XCTAssertEqual(calculator.display, "5")
        XCTAssertEqual(calculator.pendingExpression, "2 + 3 +")
    }

    func testTransferValue() {
        XCTAssertEqual(run(digits("3") + [.divide] + digits("4") + [.equals]).displayValue, 0.75)
    }
}
