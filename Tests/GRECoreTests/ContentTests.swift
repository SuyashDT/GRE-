import XCTest
@testable import GRECore

/// Decodes the shipped JSON content and checks the invariants the app relies on.
final class ContentTests: XCTestCase {
    func loadLibrary() throws -> ContentLibrary {
        guard ContentLibrary.bundledContentFolder() != nil else {
            throw XCTSkip("Content folder not built yet")
        }
        return try ContentLibrary.loadBundled()
    }

    func testMockTestMatchesCurrentGREFormat() throws {
        let library = try loadLibrary()
        let test = try XCTUnwrap(library.mockTests.first)
        XCTAssertEqual(test.essay.minutes, 30)
        XCTAssertEqual(test.steps.first, .essay)
        XCTAssertEqual(test.steps.count, 5)

        let expected: [(Measure, Int, Int)] = [(.verbal, 12, 18), (.verbal, 15, 23), (.quant, 12, 21), (.quant, 15, 26)]
        for (measure, count, minutes) in expected {
            let stage = count == 12 ? 1 : 2
            let tiers: [TestSection.Tier] = stage == 1 ? [.standard] : [.easier, .harder]
            for tier in tiers {
                let section = try XCTUnwrap(test.section(measure, stage: stage, tier: tier), "\(measure) \(stage) \(tier)")
                XCTAssertEqual(section.questions.count, count, section.id)
                XCTAssertEqual(section.minutes, minutes, section.id)
                XCTAssertTrue(section.questions.allSatisfy { $0.category.measure == measure }, section.id)
            }
        }
        // One path through the test is 30 + 18 + 23 + 21 + 26 = 118 minutes (1 h 58 min).
        XCTAssertEqual(test.totalMinutes, 118)
    }

    func testEveryQuestionIsAnswerable() throws {
        let library = try loadLibrary()
        var stimuli: [String: Stimulus] = [:]
        for test in library.mockTests { for stimulus in test.stimuli { stimuli[stimulus.id] = stimulus } }
        for stimulus in library.drills.stimuli { stimuli[stimulus.id] = stimulus }

        let questions = library.mockTests.flatMap(\.allQuestions) + library.drills.sets.flatMap(\.questions)
        XCTAssertGreaterThan(questions.count, 100)
        XCTAssertEqual(Set(questions.map(\.id)).count, questions.count, "question ids must be unique")

        for question in questions {
            // Build the correct response and make sure the checker accepts it.
            var response = Response()
            switch question.format {
            case .single, .multiple, .sentence:
                response.selected = Set(question.correct ?? [])
            case .blanks:
                response.blankChoices = (question.correct ?? []).map { Optional($0) }
            case .numeric:
                response.numberText = NumberFormatting.plain(try XCTUnwrap(question.answerValue, question.id), maxFractionDigits: 10)
            case .fraction:
                let value = try XCTUnwrap(question.answerValue, question.id)
                let parts = (question.answerDisplay ?? "").split(separator: "/")
                if parts.count == 2 {
                    response.numberText = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    response.denominatorText = String(parts[1]).trimmingCharacters(in: .whitespaces)
                } else {
                    response.numberText = NumberFormatting.plain(value * 1000, maxFractionDigits: 10)
                    response.denominatorText = "1000"
                }
            }
            XCTAssertEqual(question.state(of: response), .answered, question.id)
            XCTAssertTrue(question.isCorrect(response), "\(question.id) rejects its own key")
            XCTAssertFalse(question.isCorrect(Response()), question.id)

            if let id = question.stimulusId {
                let stimulus = try XCTUnwrap(stimuli[id], "\(question.id) → \(id)")
                if question.format == .sentence {
                    XCTAssertTrue(stimulus.sentences.indices.contains(question.correct?.first ?? -1), question.id)
                }
            }
        }
    }

    func testDrillsCoverEveryCategory() throws {
        let library = try loadLibrary()
        let categories = Set(library.drills.sets.map(\.category))
        XCTAssertEqual(categories, Set(QuestionCategory.allCases))
        for set in library.drills.sets {
            XCTAssertTrue(set.questions.allSatisfy { $0.category == set.category }, set.id)
        }
    }

    func testVocabularyAndLessons() throws {
        let library = try loadLibrary()
        XCTAssertGreaterThanOrEqual(library.vocabulary.count, 250)
        XCTAssertEqual(Set(library.vocabulary.map(\.id)).count, library.vocabulary.count)
        XCTAssertGreaterThanOrEqual(library.lessons.count, 10)
        for lesson in library.lessons {
            if let drillId = lesson.drillId {
                XCTAssertNotNil(library.drillSet(id: drillId), "\(lesson.id) links to missing drill \(drillId)")
            }
        }
    }
}
