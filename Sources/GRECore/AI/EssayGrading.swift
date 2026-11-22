import Foundation

/// Feedback on an Analyze an Issue essay, produced by Claude via Claude Code.
public struct EssayGrade: Codable, Hashable, Sendable {
    public struct Criterion: Codable, Hashable, Sendable {
        public let name: String
        public let score: Double
        public let comment: String
    }

    /// Holistic score, 0–6 in half-point steps (like the official AW score).
    public var score: Double
    public var summary: String
    public var criteria: [Criterion]
    public var strengths: [String]
    public var improvements: [String]
    public var nextSteps: String
    /// Filled in by the app after grading.
    public var model: String?
    public var gradedAt: Date?
    public var costUSD: Double?

    /// Clamps every score to 0–6 and rounds to the nearest half point.
    public func normalized() -> EssayGrade {
        var copy = self
        copy.score = EssayRubric.roundToHalf(score)
        copy.criteria = criteria.map {
            Criterion(name: $0.name, score: EssayRubric.roundToHalf($0.score), comment: $0.comment)
        }
        return copy
    }
}

public enum EssayRubric {
    public struct Level: Hashable, Sendable, Identifiable {
        public let score: Int
        public let title: String
        public let description: String
        public var id: Int { score }
    }

    /// The six-point Issue scale, paraphrased from the published GRE scoring guide.
    public static let levels: [Level] = [
        Level(score: 6, title: "Outstanding",
              description: "A clear, insightful position developed with compelling reasons and well-chosen examples. Logically organized with smooth transitions; varied, precise language with only minor errors."),
        Level(score: 5, title: "Strong",
              description: "A clear, thoughtful position with logically sound reasons and well-chosen examples. Generally focused and well organized; clear language with some variety and minor errors."),
        Level(score: 4, title: "Adequate",
              description: "A clear position supported by relevant reasons and examples. Adequately organized; language is generally clear, though some errors may appear."),
        Level(score: 3, title: "Limited",
              description: "Some competence, but the position is vague or limited, development is weak or uneven, organization is poor, or there are frequent errors that sometimes obscure meaning."),
        Level(score: 2, title: "Seriously flawed",
              description: "Unclear or seriously limited position, few relevant reasons or examples, poor focus or organization, or language errors that frequently obscure meaning."),
        Level(score: 1, title: "Fundamentally deficient",
              description: "Little evidence of an organized response; little or no development; severe and pervasive language errors."),
        Level(score: 0, title: "Unscorable",
              description: "Off topic, copies the prompt, written in a foreign language, consists only of keystroke characters, or is blank."),
    ]

    public static let criteria = [
        "Position & Insight",
        "Development & Support",
        "Organization & Coherence",
        "Language & Mechanics",
    ]

    public static func roundToHalf(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(6, max(0, (value * 2).rounded() / 2))
    }
}

/// Builds the prompt sent to Claude Code and parses what comes back.
public enum EssayGradingPrompt {
    public static let systemPrompt = """
    You are an experienced GRE Analytical Writing rater scoring a practice response to the \
    "Analyze an Issue" task of the current GRE General Test (30 minutes, one essay).

    Score the response holistically on the official 0–6 scale. Official scores are the average \
    of two ratings, so report a whole or half point (for example 3.5 or 5.0). Use this scale:
    \(EssayRubric.levels.map { "\($0.score) — \($0.title): \($0.description)" }.joined(separator: "\n"))

    Rating guidance:
    - Judge it as a first draft written under a 30-minute limit, with no spell-checker. Minor \
    typos should not lower a score unless they interfere with meaning.
    - The response must address the specific instructions given with the prompt (for example, \
    addressing the strongest counterarguments, or the circumstances in which the recommendation \
    would or would not be advantageous). Ignoring them caps the score.
    - Length is not a goal in itself, but very short responses rarely develop ideas enough for \
    a score above 3.
    - Score a blank, off-topic, or copied-prompt response 0.

    Also score each of these four aspects on the same 0–6 scale, with one or two sentences of \
    comment: \(EssayRubric.criteria.joined(separator: ", ")).

    Write all feedback to the test taker in the second person ("you"). Be specific: briefly quote \
    or point to passages. Give two to four strengths, three to five concrete improvements, and a \
    short nextSteps paragraph saying what to practice before the next essay.

    Return the grade as a JSON object with the keys score, summary, criteria (array of {name, \
    score, comment}), strengths, improvements, nextSteps. If a StructuredOutput tool is available, \
    return it by calling that tool exactly once; otherwise reply with only the JSON object. Do not \
    use any other tools.
    """

    /// The short instruction passed as the `-p` argument; the essay itself goes on stdin.
    public static let instruction = "Grade the GRE Analyze an Issue practice essay provided in the input, following your instructions."

    public static func input(task: EssayTask, essay: String, minutesUsed: Double?) -> String {
        let words = essay.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        var lines = [
            "ISSUE STATEMENT:",
            task.statement,
            "",
            "INSTRUCTIONS GIVEN TO THE TEST TAKER:",
            task.instructions,
            "",
            "RESPONSE (\(words) words\(minutesUsed.map { String(format: ", written in %.0f of %d minutes", $0, task.minutes) } ?? "")):",
            "<<<BEGIN RESPONSE>>>",
            essay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(blank)" : essay,
            "<<<END RESPONSE>>>",
        ]
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// JSON Schema for `claude -p --json-schema`.
    public static let jsonSchema: String = {
        let criterion: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "score": ["type": "number"],
                "comment": ["type": "string"],
            ],
            "required": ["name", "score", "comment"],
            "additionalProperties": false,
        ]
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "score": ["type": "number", "description": "Holistic score from 0 to 6 in half-point steps"],
                "summary": ["type": "string", "description": "Two or three sentences explaining the score"],
                "criteria": ["type": "array", "items": criterion],
                "strengths": ["type": "array", "items": ["type": "string"]],
                "improvements": ["type": "array", "items": ["type": "string"]],
                "nextSteps": ["type": "string"],
            ],
            "required": ["score", "summary", "criteria", "strengths", "improvements", "nextSteps"],
            "additionalProperties": false,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }()
}

public enum EssayGradingError: Error, LocalizedError, Equatable, Sendable {
    case claudeNotFound
    case notLoggedIn(String)
    case failed(String)
    case timedOut
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Claude Code wasn't found. Install it from https://claude.com/claude-code, or set its location in Settings."
        case let .notLoggedIn(detail):
            return "Claude Code isn't logged in. Open Terminal, run `claude`, and sign in with /login. (\(detail))"
        case let .failed(detail):
            return "Claude Code couldn't grade the essay: \(detail)"
        case .timedOut:
            return "Grading took too long and was stopped. Try again."
        case let .invalidOutput(detail):
            return "Claude Code returned a response the app couldn't read: \(detail)"
        }
    }
}

/// Parses the `--output-format json` result printed by `claude -p`.
public enum ClaudeCodeOutput {
    public struct Parsed: Sendable {
        public let grade: EssayGrade
        public let costUSD: Double?
    }

    public static func parse(stdout: Data, stderr: Data, exitCode: Int32) throws -> Parsed {
        let errorText = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let outText = String(decoding: stdout, as: UTF8.self)

        guard let object = lastJSONObject(in: outText) else {
            let detail = errorText.isEmpty ? outText.trimmingCharacters(in: .whitespacesAndNewlines) : errorText
            if looksLikeAuthProblem(detail) { throw EssayGradingError.notLoggedIn(shorten(detail)) }
            if exitCode != 0 {
                throw EssayGradingError.failed(shorten(detail.isEmpty ? "exit code \(exitCode)" : detail))
            }
            throw EssayGradingError.invalidOutput(shorten(detail.isEmpty ? "empty output" : detail))
        }

        let resultText = object["result"] as? String ?? ""
        let isError = object["is_error"] as? Bool ?? false
        let subtype = object["subtype"] as? String ?? ""
        if isError || (subtype.hasPrefix("error") && object["structured_output"] == nil) {
            let detail = [resultText, (object["errors"] as? [String])?.joined(separator: "; ") ?? "", subtype]
                .first { !$0.isEmpty } ?? "unknown error"
            if looksLikeAuthProblem(detail) || looksLikeAuthProblem(errorText) {
                throw EssayGradingError.notLoggedIn(shorten(detail))
            }
            throw EssayGradingError.failed(shorten(detail))
        }

        let cost = object["total_cost_usd"] as? Double
        if let structured = object["structured_output"], !(structured is NSNull),
           let data = try? JSONSerialization.data(withJSONObject: structured),
           let grade = try? JSONDecoder().decode(EssayGrade.self, from: data) {
            return Parsed(grade: grade.normalized(), costUSD: cost)
        }
        if let inner = lastJSONObject(in: resultText),
           let data = try? JSONSerialization.data(withJSONObject: inner),
           let grade = try? JSONDecoder().decode(EssayGrade.self, from: data) {
            return Parsed(grade: grade.normalized(), costUSD: cost)
        }
        throw EssayGradingError.invalidOutput(shorten(resultText.isEmpty ? outText : resultText))
    }

    /// Finds the last top-level `{…}` in text that parses as a JSON object.
    /// Handles code fences and any log lines printed before the result.
    static func lastJSONObject(in text: String) -> [String: Any]? {
        let characters = Array(text)
        var found: [String: Any]?
        var index = 0
        while index < characters.count {
            guard characters[index] == "{", let close = matchingBrace(characters, from: index) else {
                index += 1
                continue
            }
            let candidate = String(characters[index...close])
            if let data = candidate.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                found = object
                index = close + 1
            } else {
                index += 1
            }
        }
        return found
    }

    /// Index of the `}` closing the `{` at `start`, honouring JSON strings and escapes.
    private static func matchingBrace(_ characters: [Character], from start: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < characters.count {
            let character = characters[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    static func looksLikeAuthProblem(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["not logged in", "/login", "authentication_failed", "failed to authenticate",
                "invalid api key", "oauth"].contains { lowered.contains($0) }
    }

    static func shorten(_ text: String, limit: Int = 400) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }
}
