import Foundation

public extension DrillSet {
    /// The record of one sitting of this set, as it is saved in `progress.json`.
    ///
    /// - Parameters:
    ///   - responses: the learner's answers by question id.
    ///   - timeSpent: seconds spent looking at each question.
    ///   - questionIds: the questions to record, or nil for every question. An untimed drill records
    ///     the questions that were checked or skipped; a timed set records all of them, like a test section.
    ///   - timed: whether the set ran against the clock.
    ///   - secondsUsed: seconds on the clock when a timed set ended.
    func makeAttempt(responses: [String: Response], timeSpent: [String: Double],
                     including questionIds: Set<String>? = nil, timed: Bool,
                     secondsUsed: Double? = nil, date: Date = Date()) -> DrillAttempt {
        let results = questions.filter { questionIds?.contains($0.id) ?? true }.map { question -> QuestionResult in
            let response = responses[question.id]
            let state = question.state(of: response)
            return QuestionResult(
                questionId: question.id, category: question.category, topic: question.topic,
                difficulty: question.difficulty,
                answered: state == .answered,
                correct: question.isCorrect(response),
                seconds: timeSpent[question.id] ?? 0,
                // Keep a half-finished answer too: it shows where the learner got stuck.
                response: state == .unanswered ? nil : response
            )
        }
        return DrillAttempt(setId: id, date: date, results: results, timed: timed,
                            timeLimitMinutes: timed ? timeLimitMinutes : nil,
                            secondsUsed: timed ? secondsUsed : nil)
    }
}
