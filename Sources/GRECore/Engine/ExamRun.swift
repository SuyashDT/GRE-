import Foundation

/// The state of one sitting of a mock test: which step the test taker is on,
/// which adaptive sections they were routed to, and every answer so far.
/// Timing is driven by the UI; this type only records it.
public struct ExamRun: Sendable {
    public let test: MockTest
    public let startedAt: Date
    public let steps: [ExamStep]
    public private(set) var stepIndex: Int = 0
    /// Step index → id of the section served for that step.
    public private(set) var servedSections: [Int: String] = [:]

    public var essayText: String = ""
    public var essaySeconds: Double = 0
    public var responses: [String: Response] = [:]
    public var marked: Set<String> = []
    /// Seconds spent looking at each question.
    public var timeSpent: [String: Double] = [:]
    /// Seconds used in each section (by section id).
    public var sectionSeconds: [String: Double] = [:]

    public init(test: MockTest, startedAt: Date = Date()) {
        self.test = test
        self.startedAt = startedAt
        self.steps = test.steps
    }

    public var isFinished: Bool { stepIndex >= steps.count }

    public var currentStep: ExamStep? {
        steps.indices.contains(stepIndex) ? steps[stepIndex] : nil
    }

    /// The section for the current step, choosing the adaptive tier when a
    /// stage-2 section is reached for the first time.
    public mutating func currentSection() -> TestSection? {
        section(forStep: stepIndex)
    }

    public mutating func section(forStep index: Int) -> TestSection? {
        guard steps.indices.contains(index), case let .section(measure, stage) = steps[index] else { return nil }
        if let id = servedSections[index] { return test.section(id: id) }
        let tier: TestSection.Tier
        if stage == 1 {
            tier = .standard
        } else {
            tier = ScoreEstimator.route(
                stage1Correct: correctCount(measure: measure, stage: 1),
                threshold: test.routing.threshold(for: measure)
            )
        }
        guard let section = test.section(measure, stage: stage, tier: tier) else { return nil }
        servedSections[index] = section.id
        return section
    }

    public mutating func advance() {
        if stepIndex < steps.count { stepIndex += 1 }
    }

    /// Sections served so far, in order.
    public var servedSectionList: [TestSection] {
        servedSections.keys.sorted().compactMap { servedSections[$0] }.compactMap { test.section(id: $0) }
    }

    public func servedSection(measure: Measure, stage: Int) -> TestSection? {
        servedSectionList.first { $0.measure == measure && $0.stage == stage }
    }

    public func correctCount(measure: Measure, stage: Int) -> Int {
        guard let section = servedSection(measure: measure, stage: stage) else { return 0 }
        return correctCount(in: section)
    }

    public func correctCount(in section: TestSection) -> Int {
        section.questions.filter { $0.isCorrect(responses[$0.id]) }.count
    }

    public func state(of question: Question) -> AnswerState {
        question.state(of: responses[question.id])
    }

    public var essayWordCount: Int {
        essayText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Scaled estimate for a measure, available once both of its sections were served.
    public func estimate(for measure: Measure) -> ScoreEstimate? {
        guard let first = servedSection(measure: measure, stage: 1),
              let second = servedSection(measure: measure, stage: 2)
        else { return nil }
        return ScoreEstimator.estimate(
            measure: measure,
            stage1Correct: correctCount(in: first), stage1Count: first.questions.count,
            stage2Correct: correctCount(in: second), stage2Count: second.questions.count,
            tier: second.tier, threshold: test.routing.threshold(for: measure)
        )
    }

    public func makeAttempt(finishedAt: Date = Date(), essayGrade: EssayGrade? = nil, selfScore: Double? = nil) -> MockAttempt {
        let sections = servedSectionList.map { section in
            SectionResult(
                sectionId: section.id,
                measure: section.measure,
                stage: section.stage,
                tier: section.tier,
                minutesAllowed: section.minutes,
                secondsUsed: sectionSeconds[section.id] ?? 0,
                questions: section.questions.map { question in
                    QuestionResult(
                        questionId: question.id,
                        category: question.category,
                        topic: question.topic,
                        difficulty: question.difficulty,
                        answered: question.state(of: responses[question.id]) == .answered,
                        correct: question.isCorrect(responses[question.id]),
                        seconds: timeSpent[question.id] ?? 0
                    )
                }
            )
        }
        let essay = EssayResult(
            text: essayText, wordCount: essayWordCount, secondsUsed: essaySeconds,
            grade: essayGrade, selfScore: selfScore
        )
        let servedCount = servedSections.count
        let sectionSteps = steps.filter { if case .section = $0 { return true } else { return false } }.count
        return MockAttempt(
            id: UUID(),
            testId: test.id,
            startedAt: startedAt,
            finishedAt: finishedAt,
            completed: isFinished && servedCount == sectionSteps,
            sections: sections,
            essay: essay,
            verbal: estimate(for: .verbal),
            quant: estimate(for: .quant),
            responses: responses
        )
    }
}
