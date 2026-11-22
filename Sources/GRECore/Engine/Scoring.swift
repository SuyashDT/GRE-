import Foundation

/// Estimated scaled score for one measure (Verbal or Quant, 130–170).
public struct ScoreEstimate: Codable, Hashable, Sendable {
    public let measure: Measure
    public let rawCorrect: Int
    public let questionCount: Int
    public let stage2Tier: TestSection.Tier
    public let scaled: Int
    public let low: Int
    public let high: Int

    public var rangeText: String { "\(low)–\(high)" }
}

/// ETS does not publish its raw-to-scaled conversion. This estimator mimics how a
/// section-adaptive test behaves: the harder second section unlocks the upper part
/// of the 130–170 scale, while the easier one caps the score in the mid-150s.
public enum ScoreEstimator {
    public static let minScore = 130
    public static let maxScore = 170
    /// Highest score reachable through the easier second section.
    public static let easierPathCeiling = 155
    /// Score for meeting the routing threshold exactly and missing all of stage 2 on the harder path.
    public static let harderPathFloor = 145

    public static func estimate(
        measure: Measure,
        stage1Correct: Int, stage1Count: Int,
        stage2Correct: Int, stage2Count: Int,
        tier: TestSection.Tier, threshold: Int
    ) -> ScoreEstimate {
        let raw = stage1Correct + stage2Correct
        let total = stage1Count + stage2Count
        let value: Double
        if tier == .harder {
            let span = Double(max(1, total - threshold))
            let above = Double(max(0, raw - threshold))
            value = Double(harderPathFloor) + Double(maxScore - harderPathFloor) * above / span
        } else {
            let possible = Double(max(1, (threshold - 1) + stage2Count))
            value = Double(minScore) + Double(easierPathCeiling - minScore) * Double(raw) / possible
        }
        let scaled = clamp(Int(value.rounded()))
        return ScoreEstimate(
            measure: measure, rawCorrect: raw, questionCount: total, stage2Tier: tier,
            scaled: scaled, low: clamp(scaled - 3), high: clamp(scaled + 3)
        )
    }

    /// Which stage-2 section a test taker is routed to.
    public static func route(stage1Correct: Int, threshold: Int) -> TestSection.Tier {
        stage1Correct >= threshold ? .harder : .easier
    }

    private static func clamp(_ score: Int) -> Int {
        min(maxScore, max(minScore, score))
    }
}

/// Recommended seconds per question for a section, from the official timing.
public enum Pacing {
    public static func secondsPerQuestion(minutes: Int, questions: Int) -> Double {
        guard questions > 0 else { return 0 }
        return Double(minutes * 60) / Double(questions)
    }

    /// Typical per-question target by measure (Verbal ≈ 1.5 min, Quant ≈ 1.75 min).
    public static func target(for measure: Measure) -> Double {
        measure == .verbal ? 90 : 105
    }
}
