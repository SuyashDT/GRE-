import Foundation

public struct CategoryStat: Hashable, Sendable, Identifiable {
    public let category: QuestionCategory
    public let attempted: Int
    public let correct: Int
    public let averageSeconds: Double

    public var id: String { category.rawValue }
    public var accuracy: Double { attempted == 0 ? 0 : Double(correct) / Double(attempted) }
}

public struct TopicStat: Hashable, Sendable, Identifiable {
    public let measure: Measure
    public let topic: String
    public let attempted: Int
    public let correct: Int

    public var id: String { "\(measure.rawValue)-\(topic)" }
    public var accuracy: Double { attempted == 0 ? 0 : Double(correct) / Double(attempted) }
}

public struct ScorePoint: Hashable, Sendable, Identifiable {
    public let attemptId: UUID
    public let date: Date
    public let verbal: Int?
    public let quant: Int?
    public let essay: Double?

    public var id: UUID { attemptId }
    public var total: Int? {
        guard let verbal, let quant else { return nil }
        return verbal + quant
    }
}

/// Aggregates mock-test and drill results for the dashboard.
public struct Analytics: Sendable {
    public let progress: ProgressData

    public init(progress: ProgressData) {
        self.progress = progress
    }

    /// Every answered-or-seen question result from mock tests and drills.
    public var allResults: [QuestionResult] {
        progress.mockAttempts.flatMap(\.allQuestionResults) + progress.drillAttempts.flatMap(\.results)
    }

    public var categoryStats: [CategoryStat] {
        let grouped = Dictionary(grouping: allResults, by: \.category)
        return QuestionCategory.allCases.compactMap { category in
            guard let results = grouped[category], !results.isEmpty else { return nil }
            let timed = results.filter { $0.seconds > 0 }
            let average = timed.isEmpty ? 0 : timed.map(\.seconds).reduce(0, +) / Double(timed.count)
            return CategoryStat(
                category: category, attempted: results.count,
                correct: results.filter(\.correct).count, averageSeconds: average
            )
        }
    }

    public var topicStats: [TopicStat] {
        let grouped = Dictionary(grouping: allResults) { "\($0.category.measure.rawValue)|\($0.topic)" }
        return grouped.compactMap { _, results in
            guard let first = results.first else { return nil }
            return TopicStat(
                measure: first.category.measure, topic: first.topic,
                attempted: results.count, correct: results.filter(\.correct).count
            )
        }
        .sorted { ($0.measure.rawValue, $0.topic) < ($1.measure.rawValue, $1.topic) }
    }

    /// Categories with the lowest accuracy (at least `minimumAttempts` questions seen).
    public func weakestCategories(limit: Int = 3, minimumAttempts: Int = 3) -> [CategoryStat] {
        Array(categoryStats.filter { $0.attempted >= minimumAttempts }
            .sorted { $0.accuracy < $1.accuracy }
            .prefix(limit))
    }

    public var scoreHistory: [ScorePoint] {
        progress.mockAttempts
            .filter(\.completed)
            .sorted { $0.finishedAt < $1.finishedAt }
            .map { attempt in
                ScorePoint(
                    attemptId: attempt.id, date: attempt.finishedAt,
                    verbal: attempt.verbal?.scaled, quant: attempt.quant?.scaled,
                    essay: attempt.essay?.score
                )
            }
    }

    public var latestScore: ScorePoint? { scoreHistory.last }

    public var overallAccuracy: Double? {
        let results = allResults
        guard !results.isEmpty else { return nil }
        return Double(results.filter(\.correct).count) / Double(results.count)
    }

    public var questionsPracticed: Int { allResults.count }

    public func vocabularyCounts(totalWords: Int) -> (new: Int, learning: Int, mastered: Int) {
        let mastered = progress.cards.values.filter(\.isMastered).count
        let learning = progress.cards.count - mastered
        return (max(0, totalWords - progress.cards.count), learning, mastered)
    }

    public func dueCardCount(now: Date = Date()) -> Int {
        progress.cards.values.filter { $0.due <= now }.count
    }
}
