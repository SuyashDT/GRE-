import Foundation

// MARK: - Stimuli (passages and data sets)

public struct Stimulus: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case passage
        case data
    }

    public let id: String
    public let kind: Kind
    public let title: String?
    /// Passage text: paragraphs, each a list of sentences.
    public let paragraphs: [[String]]?
    public let intro: String?
    public let tables: [DataTable]?
    public let charts: [ChartSpec]?

    /// All sentences of a passage in reading order; select-in-passage answers index into this.
    public var sentences: [String] { paragraphs?.flatMap { $0 } ?? [] }

    /// Index of the first sentence of each paragraph within `sentences`.
    public var paragraphStartIndices: [Int] {
        var starts: [Int] = []
        var running = 0
        for paragraph in paragraphs ?? [] {
            starts.append(running)
            running += paragraph.count
        }
        return starts
    }

    public var wordCount: Int {
        sentences.reduce(0) { $0 + $1.split(whereSeparator: { $0.isWhitespace }).count }
    }
}

public struct DataTable: Codable, Hashable, Sendable {
    public let title: String?
    public let columns: [String]
    public let rows: [[String]]
}

public struct ChartSpec: Codable, Hashable, Sendable {
    public enum ChartType: String, Codable, Hashable, Sendable {
        case bar
        case line
        case pie
    }

    public let title: String?
    public let type: ChartType
    public let xLabel: String?
    public let yLabel: String?
    public let categories: [String]
    public let series: [ChartSeries]
}

public struct ChartSeries: Codable, Hashable, Sendable {
    public let name: String
    public let values: [Double]
}

// MARK: - Mock test

public struct EssayTask: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let statement: String
    public let instructions: String
    public let minutes: Int
}

public struct TestSection: Codable, Identifiable, Hashable, Sendable {
    public enum Tier: String, Codable, Hashable, Sendable {
        case standard
        case easier
        case harder

        public var title: String {
            switch self {
            case .standard: return "Standard"
            case .easier: return "Easier"
            case .harder: return "Harder"
            }
        }
    }

    public let id: String
    public let measure: Measure
    public let stage: Int
    public let tier: Tier
    public let minutes: Int
    public let questions: [Question]

    public var title: String { "\(measure.title) — Section \(stage)" }
}

/// One step of the test, in the order the test taker sees it.
public enum ExamStep: Hashable, Sendable {
    case essay
    case section(Measure, stage: Int)

    /// Parses order entries like `"verbal-1"` or `"quant-2"`.
    public init?(slot: String) {
        if slot == "essay" {
            self = .essay
            return
        }
        let parts = slot.split(separator: "-")
        guard parts.count == 2,
              let measure = Measure(rawValue: String(parts[0])),
              let stage = Int(parts[1]), stage == 1 || stage == 2
        else { return nil }
        self = .section(measure, stage: stage)
    }
}

public struct MockTest: Codable, Identifiable, Hashable, Sendable {
    public struct Routing: Codable, Hashable, Sendable {
        /// Stage-1 correct answers needed to be routed to the harder stage-2 section.
        public let verbal: Int
        public let quant: Int

        public func threshold(for measure: Measure) -> Int {
            measure == .verbal ? verbal : quant
        }
    }

    public let id: String
    public let title: String
    public let description: String
    public let formatVersion: String
    public let essay: EssayTask
    public let order: [String]
    public let routing: Routing
    public let stimuli: [Stimulus]
    public let sections: [TestSection]

    /// Essay first, then the measure sections in the order the file specifies.
    public var steps: [ExamStep] {
        [.essay] + order.compactMap(ExamStep.init(slot:)).filter { $0 != .essay }
    }

    public func stimulus(_ id: String?) -> Stimulus? {
        guard let id else { return nil }
        return stimuli.first { $0.id == id }
    }

    public func section(_ measure: Measure, stage: Int, tier: TestSection.Tier) -> TestSection? {
        sections.first { $0.measure == measure && $0.stage == stage && $0.tier == tier }
    }

    public func section(id: String) -> TestSection? {
        sections.first { $0.id == id }
    }

    public var allQuestions: [Question] { sections.flatMap(\.questions) }

    /// Total timed minutes for one path through the test.
    public var totalMinutes: Int {
        var total = essay.minutes
        for step in steps {
            if case let .section(measure, stage) = step {
                let tier: TestSection.Tier = stage == 1 ? .standard : .harder
                total += section(measure, stage: stage, tier: tier)?.minutes ?? 0
            }
        }
        return total
    }
}

// MARK: - Drills

public struct DrillSet: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let measure: Measure
    public let category: QuestionCategory
    public let summary: String
    public let questions: [Question]
}

public struct DrillLibrary: Codable, Hashable, Sendable {
    public let stimuli: [Stimulus]
    public let sets: [DrillSet]

    public init(stimuli: [Stimulus], sets: [DrillSet]) {
        self.stimuli = stimuli
        self.sets = sets
    }
}

// MARK: - Vocabulary

public struct VocabWord: Codable, Identifiable, Hashable, Sendable {
    public let word: String
    public let partOfSpeech: String
    public let definition: String
    public let example: String
    public let synonyms: [String]
    public let tier: Int

    public var id: String { word.lowercased() }
}

public struct VocabularyList: Codable, Hashable, Sendable {
    public let words: [VocabWord]
}

// MARK: - Lessons

public struct Lesson: Codable, Identifiable, Hashable, Sendable {
    public enum Area: String, Codable, Hashable, Sendable, CaseIterable {
        case general
        case writing
        case verbal
        case quant

        public var title: String {
            switch self {
            case .general: return "Test Strategy"
            case .writing: return "Analytical Writing"
            case .verbal: return "Verbal Reasoning"
            case .quant: return "Quantitative Reasoning"
            }
        }
    }

    public struct Block: Codable, Hashable, Sendable {
        public let heading: String
        public let body: String
    }

    public struct Example: Codable, Hashable, Sendable {
        public let question: String
        public let walkthrough: String
    }

    public let id: String
    public let title: String
    public let measure: Area
    public let category: QuestionCategory?
    public let minutes: Int
    public let summary: String
    public let blocks: [Block]
    public let keyTips: [String]
    public let commonTraps: [String]
    public let example: Example?
    public let drillId: String?
}

public struct LessonList: Codable, Hashable, Sendable {
    public let lessons: [Lesson]
}
