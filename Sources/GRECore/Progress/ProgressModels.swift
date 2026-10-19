import Foundation

public struct QuestionResult: Codable, Hashable, Sendable {
    public let questionId: String
    public let category: QuestionCategory
    public let topic: String
    public let difficulty: Int
    public let answered: Bool
    public let correct: Bool
    public let seconds: Double

    public init(questionId: String, category: QuestionCategory, topic: String, difficulty: Int,
                answered: Bool, correct: Bool, seconds: Double) {
        self.questionId = questionId
        self.category = category
        self.topic = topic
        self.difficulty = difficulty
        self.answered = answered
        self.correct = correct
        self.seconds = seconds
    }
}

public struct SectionResult: Codable, Hashable, Sendable, Identifiable {
    public let sectionId: String
    public let measure: Measure
    public let stage: Int
    public let tier: TestSection.Tier
    public let minutesAllowed: Int
    public let secondsUsed: Double
    public let questions: [QuestionResult]

    public var id: String { sectionId }
    public var correctCount: Int { questions.filter(\.correct).count }
    public var questionCount: Int { questions.count }
}

public struct EssayResult: Codable, Hashable, Sendable {
    public var text: String
    public var wordCount: Int
    public var secondsUsed: Double
    public var grade: EssayGrade?
    /// Score the test taker gave themselves when AI grading wasn't used.
    public var selfScore: Double?

    public var score: Double? { grade?.score ?? selfScore }
}

public struct MockAttempt: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let testId: String
    public let startedAt: Date
    public let finishedAt: Date
    public let completed: Bool
    public let sections: [SectionResult]
    public var essay: EssayResult?
    public let verbal: ScoreEstimate?
    public let quant: ScoreEstimate?
    public let responses: [String: Response]

    public var allQuestionResults: [QuestionResult] { sections.flatMap(\.questions) }

    public func section(_ measure: Measure, stage: Int) -> SectionResult? {
        sections.first { $0.measure == measure && $0.stage == stage }
    }
}

public struct DrillAttempt: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let setId: String
    public let date: Date
    public let results: [QuestionResult]

    public init(id: UUID = UUID(), setId: String, date: Date = Date(), results: [QuestionResult]) {
        self.id = id
        self.setId = setId
        self.date = date
        self.results = results
    }

    public var correctCount: Int { results.filter(\.correct).count }
}

/// Spaced-repetition state of one vocabulary card.
public struct CardState: Codable, Hashable, Sendable {
    public var wordId: String
    public var ease: Double
    public var intervalDays: Int
    public var repetitions: Int
    public var lapses: Int
    public var due: Date
    public var firstSeen: Date
    public var lastReviewed: Date

    public var isMastered: Bool { intervalDays >= SpacedRepetition.masteredIntervalDays }
}

public struct ProgressData: Codable, Hashable, Sendable {
    public var version: Int = 1
    public var mockAttempts: [MockAttempt] = []
    public var drillAttempts: [DrillAttempt] = []
    public var cards: [String: CardState] = [:]
    /// Days (yyyy-MM-dd, local time) with any study activity.
    public var studyDays: Set<String> = []
    public var lessonsRead: Set<String> = []
    public var newCardsPerDay: Int = 20

    public init() {}

    enum CodingKeys: String, CodingKey {
        case version, mockAttempts, drillAttempts, cards, studyDays, lessonsRead, newCardsPerDay
    }

    // Decode leniently so files written by older versions of the app keep loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        mockAttempts = try container.decodeIfPresent([MockAttempt].self, forKey: .mockAttempts) ?? []
        drillAttempts = try container.decodeIfPresent([DrillAttempt].self, forKey: .drillAttempts) ?? []
        cards = try container.decodeIfPresent([String: CardState].self, forKey: .cards) ?? [:]
        studyDays = try container.decodeIfPresent(Set<String>.self, forKey: .studyDays) ?? []
        lessonsRead = try container.decodeIfPresent(Set<String>.self, forKey: .lessonsRead) ?? []
        newCardsPerDay = try container.decodeIfPresent(Int.self, forKey: .newCardsPerDay) ?? 20
    }
}
