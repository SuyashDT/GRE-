import Foundation

/// The questions a learner last got wrong, offered again as practice sets, one per measure.
///
/// A question is "missed" while its latest answer, in a drill, a coach's set or a mock test,
/// was wrong or left blank. Answering it correctly anywhere takes it off the list, so the
/// sets empty themselves as the learner fixes their mistakes.
public enum MissedQuestions {
    /// `missed-verbal` and `missed-quant`. A coach's plan can point a drill task at these ids.
    public static func setId(for measure: Measure) -> String { "missed-\(measure.rawValue)" }

    public static func measure(forSetId id: String) -> Measure? {
        Measure.allCases.first { setId(for: $0) == id }
    }

    /// Set ids a coach's own files may not use.
    public static var reservedSetIds: Set<String> { Set(Measure.allCases.map(setId(for:))) }

    /// Ids of the questions whose latest answer was wrong or blank, the longest-standing miss first.
    public static func questionIds(in progress: ProgressData) -> [String] {
        var answers: [(date: Date, result: QuestionResult)] = []
        for attempt in progress.mockAttempts {
            answers += attempt.allQuestionResults.map { (attempt.finishedAt, $0) }
        }
        for attempt in progress.drillAttempts {
            answers += attempt.results.map { (attempt.date, $0) }
        }
        // Stable sort: answers saved at the same moment keep the order they were saved in.
        let ordered = answers.enumerated().sorted {
            $0.element.date != $1.element.date ? $0.element.date < $1.element.date : $0.offset < $1.offset
        }
        var latest: [String: (order: Int, correct: Bool)] = [:]
        for (order, answer) in ordered.enumerated() {
            latest[answer.element.result.questionId] = (order, answer.element.result.correct)
        }
        return latest.filter { !$0.value.correct }.sorted { $0.value.order < $1.value.order }.map(\.key)
    }

    /// The missed questions of one measure as a set, or nil when there are none.
    /// Questions that are no longer in the content (a coach's file was removed) are left out.
    public static func set(for measure: Measure, progress: ProgressData, content: ContentLibrary) -> DrillSet? {
        let questions = questionIds(in: progress).compactMap { content.question(id: $0) }
            .filter { $0.category.measure == measure }
        guard !questions.isEmpty else { return nil }
        return DrillSet(
            id: setId(for: measure),
            title: "Missed \(measure.shortTitle) questions",
            measure: measure,
            summary: summary(for: measure),
            questions: questions
        )
    }

    public static func summary(for measure: Measure) -> String {
        "Every \(measure.shortTitle) question whose latest answer was wrong, from the drills, your coach's sets and the mock tests. Answer one correctly and it leaves this list."
    }
}
