import Foundation

/// A test taker's answer to one question. Which fields are used depends on the
/// question's `AnswerFormat`.
public struct Response: Codable, Hashable, Sendable {
    /// `single`, `multiple` and `sentence`: selected option or sentence indices.
    public var selected: Set<Int>
    /// `blanks`: chosen option index per blank (nil = blank not filled yet).
    public var blankChoices: [Int?]
    /// `numeric`: the entry box. `fraction`: the numerator box.
    public var numberText: String
    /// `fraction`: the denominator box.
    public var denominatorText: String

    public init(
        selected: Set<Int> = [], blankChoices: [Int?] = [],
        numberText: String = "", denominatorText: String = ""
    ) {
        self.selected = selected
        self.blankChoices = blankChoices
        self.numberText = numberText
        self.denominatorText = denominatorText
    }
}

public enum AnswerState: String, Codable, Hashable, Sendable {
    case unanswered
    /// Partly answered (e.g. one of two Sentence Equivalence choices picked).
    case incomplete
    case answered

    public var title: String {
        switch self {
        case .unanswered: return "Not Answered"
        case .incomplete: return "Incomplete"
        case .answered: return "Answered"
        }
    }
}

public extension Question {
    func state(of response: Response?) -> AnswerState {
        guard let response else { return .unanswered }
        switch format {
        case .single, .sentence:
            return response.selected.count == 1 ? .answered : (response.selected.isEmpty ? .unanswered : .incomplete)
        case .multiple:
            if response.selected.isEmpty { return .unanswered }
            if let count = selectCount, response.selected.count != count { return .incomplete }
            return .answered
        case .blanks:
            let needed = blanks?.count ?? 0
            let filled = response.blankChoices.prefix(needed).compactMap { $0 }.count
            if filled == 0 { return .unanswered }
            return filled == needed ? .answered : .incomplete
        case .numeric:
            let text = AnswerChecker.normalized(response.numberText)
            if text.isEmpty { return .unanswered }
            return AnswerChecker.parse(text) == nil ? .incomplete : .answered
        case .fraction:
            let top = AnswerChecker.normalized(response.numberText)
            let bottom = AnswerChecker.normalized(response.denominatorText)
            if top.isEmpty && bottom.isEmpty { return .unanswered }
            guard AnswerChecker.parse(top) != nil, let denominator = AnswerChecker.parse(bottom), denominator != 0 else {
                return .incomplete
            }
            return .answered
        }
    }

    func isCorrect(_ response: Response?) -> Bool {
        guard let response, state(of: response) == .answered else { return false }
        switch format {
        case .single, .multiple, .sentence:
            return response.selected == Set(correct ?? [])
        case .blanks:
            guard let correct else { return false }
            return Array(response.blankChoices.prefix(correct.count)) == correct.map { Optional($0) }
        case .numeric:
            guard let expected = answerValue, let value = AnswerChecker.parse(AnswerChecker.normalized(response.numberText)) else {
                return false
            }
            return AnswerChecker.matches(value, expected, tolerance: 1e-9)
        case .fraction:
            guard let expected = answerValue,
                  let top = AnswerChecker.parse(AnswerChecker.normalized(response.numberText)),
                  let bottom = AnswerChecker.parse(AnswerChecker.normalized(response.denominatorText)),
                  bottom != 0
            else { return false }
            // Content stores fractions as decimals (7/12 → 0.58333…), so allow rounding error.
            return AnswerChecker.matches(top / bottom, expected, tolerance: 1e-6)
        }
    }

    /// The user's answer rendered as text for review screens.
    func responseText(_ response: Response?) -> String {
        guard let response, state(of: response) != .unanswered else { return "No answer" }
        switch format {
        case .numeric:
            return [entryPrefix, response.numberText, entrySuffix].compactMap { $0 }.joined()
        case .fraction:
            return "\(response.numberText)/\(response.denominatorText)"
        case .sentence:
            return response.selected.sorted().map { "Sentence \($0 + 1)" }.joined(separator: ", ")
        case .blanks:
            guard let blanks else { return "—" }
            return blanks.indices.map { index -> String in
                let label = blanks.count > 1 ? "\(Question.romanNumeral(index + 1)). " : ""
                guard response.blankChoices.indices.contains(index),
                      let choice = response.blankChoices[index],
                      blanks[index].indices.contains(choice)
                else { return label + "—" }
                return label + blanks[index][choice]
            }.joined(separator: "; ")
        case .single, .multiple:
            let options = displayOptions
            return response.selected.sorted().map { index in
                options.indices.contains(index) ? "\(Question.letter(index)). \(options[index])" : Question.letter(index)
            }.joined(separator: "; ")
        }
    }
}

public enum AnswerChecker {
    /// Strips spaces, thousands separators and the Unicode minus sign.
    public static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\u{2212}", with: "-")
    }

    /// Parses an entry-box value. Accepts integers and decimals such as "-3", "0.25", ".5".
    public static func parse(_ text: String) -> Double? {
        guard !text.isEmpty else { return nil }
        let allowed = Set("0123456789.-")
        guard text.allSatisfy({ allowed.contains($0) }),
              text.filter({ $0 == "." }).count <= 1,
              text.dropFirst().contains("-") == false
        else { return nil }
        if text == "-" || text == "." || text == "-." { return nil }
        return Double(text)
    }

    public static func matches(_ value: Double, _ expected: Double, tolerance: Double) -> Bool {
        abs(value - expected) <= tolerance * max(1, abs(expected))
    }
}
