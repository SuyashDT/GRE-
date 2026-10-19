import Foundation

public enum Measure: String, Codable, CaseIterable, Hashable, Sendable {
    case verbal
    case quant

    public var title: String {
        switch self {
        case .verbal: return "Verbal Reasoning"
        case .quant: return "Quantitative Reasoning"
        }
    }

    public var shortTitle: String {
        switch self {
        case .verbal: return "Verbal"
        case .quant: return "Quant"
        }
    }
}

public enum QuestionCategory: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case textCompletion
    case sentenceEquivalence
    case readingComprehension
    case quantitativeComparison
    case problemSolving
    case multipleAnswer
    case numericEntry
    case dataInterpretation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .textCompletion: return "Text Completion"
        case .sentenceEquivalence: return "Sentence Equivalence"
        case .readingComprehension: return "Reading Comprehension"
        case .quantitativeComparison: return "Quantitative Comparison"
        case .problemSolving: return "Problem Solving"
        case .multipleAnswer: return "Multiple Answer"
        case .numericEntry: return "Numeric Entry"
        case .dataInterpretation: return "Data Interpretation"
        }
    }

    public var measure: Measure {
        switch self {
        case .textCompletion, .sentenceEquivalence, .readingComprehension: return .verbal
        default: return .quant
        }
    }
}

public enum AnswerFormat: String, Codable, Hashable, Sendable {
    /// Pick exactly one option.
    case single
    /// Pick several options (exactly `selectCount` when set, otherwise all that apply).
    case multiple
    /// Text completion: one choice per blank.
    case blanks
    /// Integer or decimal entry box.
    case numeric
    /// Numerator / denominator entry boxes.
    case fraction
    /// Select-in-passage: pick one sentence of the passage.
    case sentence
}

public struct Question: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let category: QuestionCategory
    public let topic: String
    public let difficulty: Int
    public let format: AnswerFormat
    public let stimulusId: String?
    public let prompt: String
    public let options: [String]?
    public let blanks: [[String]]?
    public let selectCount: Int?
    public let correct: [Int]?
    public let quantityA: String?
    public let quantityB: String?
    public let answerValue: Double?
    public let answerDisplay: String?
    public let entryPrefix: String?
    public let entrySuffix: String?
    public let explanation: String

    public init(
        id: String, category: QuestionCategory, topic: String, difficulty: Int,
        format: AnswerFormat, stimulusId: String? = nil, prompt: String,
        options: [String]? = nil, blanks: [[String]]? = nil, selectCount: Int? = nil,
        correct: [Int]? = nil, quantityA: String? = nil, quantityB: String? = nil,
        answerValue: Double? = nil, answerDisplay: String? = nil,
        entryPrefix: String? = nil, entrySuffix: String? = nil, explanation: String
    ) {
        self.id = id
        self.category = category
        self.topic = topic
        self.difficulty = difficulty
        self.format = format
        self.stimulusId = stimulusId
        self.prompt = prompt
        self.options = options
        self.blanks = blanks
        self.selectCount = selectCount
        self.correct = correct
        self.quantityA = quantityA
        self.quantityB = quantityB
        self.answerValue = answerValue
        self.answerDisplay = answerDisplay
        self.entryPrefix = entryPrefix
        self.entrySuffix = entrySuffix
        self.explanation = explanation
    }

    /// The four fixed answer choices of every Quantitative Comparison question.
    public static let comparisonChoices = [
        "Quantity A is greater.",
        "Quantity B is greater.",
        "The two quantities are equal.",
        "The relationship cannot be determined from the information given.",
    ]

    public var isComparison: Bool { category == .quantitativeComparison }

    /// Options as shown to the test taker (QC questions get the standard four).
    public var displayOptions: [String] {
        if isComparison { return Self.comparisonChoices }
        return options ?? []
    }

    /// Instruction line shown above the answer area, matching the real test's wording.
    public var directions: String {
        switch format {
        case .single:
            return isComparison
                ? "Compare Quantity A and Quantity B, using additional information centered above the two quantities if such information is given."
                : "Select one answer choice."
        case .multiple:
            if category == .sentenceEquivalence {
                return "Select the two answer choices that, when used to complete the sentence, fit the meaning of the sentence as a whole and produce completed sentences that are alike in meaning."
            }
            if let count = selectCount {
                return "Select exactly \(count) answer choices."
            }
            return "Select all the answer choices that apply."
        case .blanks:
            return (blanks?.count ?? 1) > 1
                ? "For each blank, select one entry from the corresponding column of choices. Fill all blanks in the way that best completes the text."
                : "Select one entry for the blank. Fill the blank in the way that best completes the text."
        case .numeric:
            return "Enter your answer as an integer or a decimal."
        case .fraction:
            return "Enter your answer as a fraction. Fractions do not need to be reduced."
        case .sentence:
            return "Click the sentence in the passage that answers the question."
        }
    }

    /// Human-readable correct answer for review screens.
    public var correctAnswerText: String {
        switch format {
        case .numeric, .fraction:
            return answerDisplay ?? answerValue.map { NumberFormatting.plain($0) } ?? "—"
        case .blanks:
            guard let blanks, let correct else { return "—" }
            return zip(blanks, correct).enumerated().map { index, pair in
                let label = blanks.count > 1 ? "\(Self.romanNumeral(index + 1)). " : ""
                return label + (pair.0.indices.contains(pair.1) ? pair.0[pair.1] : "?")
            }.joined(separator: "; ")
        case .sentence:
            guard let index = correct?.first else { return "—" }
            return "Sentence \(index + 1)"
        case .single, .multiple:
            let options = displayOptions
            return (correct ?? []).map { index in
                let letter = Self.letter(index)
                return options.indices.contains(index) ? "\(letter). \(options[index])" : letter
            }.joined(separator: "; ")
        }
    }

    public static func letter(_ index: Int) -> String {
        let scalars = Array("ABCDEFGHIJ")
        return scalars.indices.contains(index) ? String(scalars[index]) : "\(index + 1)"
    }

    public static func romanNumeral(_ number: Int) -> String {
        switch number {
        case 1: return "i"
        case 2: return "ii"
        case 3: return "iii"
        default: return "\(number)"
        }
    }
}

public enum NumberFormatting {
    /// Formats a value without trailing zeros, e.g. 12.0 → "12", 0.25 → "0.25".
    public static func plain(_ value: Double, maxFractionDigits: Int = 6) -> String {
        if value.isNaN || value.isInfinite { return "—" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text = String(format: "%.\(maxFractionDigits)f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
