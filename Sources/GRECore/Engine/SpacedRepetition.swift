import Foundation

public enum ReviewRating: Int, Codable, CaseIterable, Hashable, Sendable {
    case again
    case hard
    case good
    case easy

    public var title: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

/// A small SM-2–style scheduler (the algorithm family Anki uses).
public enum SpacedRepetition {
    public static let startingEase = 2.5
    public static let minimumEase = 1.3
    public static let masteredIntervalDays = 21
    /// A missed card comes back after this many minutes in the same session.
    public static let relearnMinutes = 10

    public static func review(
        _ state: CardState?, wordId: String, rating: ReviewRating,
        now: Date = Date(), calendar: Calendar = .current
    ) -> CardState {
        var ease = state?.ease ?? startingEase
        var repetitions = state?.repetitions ?? 0
        var lapses = state?.lapses ?? 0
        let previous = max(1, state?.intervalDays ?? 0)
        let interval: Int

        switch rating {
        case .again:
            repetitions = 0
            lapses += state == nil ? 0 : 1
            ease = max(minimumEase, ease - 0.2)
            interval = 0
        case .hard:
            ease = max(minimumEase, ease - 0.15)
            interval = repetitions == 0 ? 1 : max(previous + 1, Int((Double(previous) * 1.2).rounded()))
            repetitions += 1
        case .good:
            switch repetitions {
            case 0: interval = 1
            case 1: interval = 3
            default: interval = max(previous + 1, Int((Double(previous) * ease).rounded()))
            }
            repetitions += 1
        case .easy:
            ease += 0.15
            interval = repetitions == 0 ? 4 : max(previous + 2, Int((Double(previous) * ease * 1.3).rounded()))
            repetitions += 1
        }

        let due: Date
        if interval == 0 {
            due = now.addingTimeInterval(TimeInterval(relearnMinutes * 60))
        } else {
            let today = calendar.startOfDay(for: now)
            due = calendar.date(byAdding: .day, value: interval, to: today) ?? now.addingTimeInterval(Double(interval) * 86_400)
        }

        return CardState(
            wordId: wordId, ease: ease, intervalDays: interval, repetitions: repetitions,
            lapses: lapses, due: due, firstSeen: state?.firstSeen ?? now, lastReviewed: now
        )
    }

    /// Cards to study now: everything due (oldest first), then new words up to today's limit.
    public static func queue(
        words: [VocabWord], cards: [String: CardState], newPerDay: Int,
        now: Date = Date(), calendar: Calendar = .current
    ) -> [VocabWord] {
        let due = words
            .compactMap { word -> (VocabWord, Date)? in
                guard let card = cards[word.id], card.due <= now else { return nil }
                return (word, card.due)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        let newRemaining = max(0, newPerDay - newCardsIntroduced(on: now, cards: cards, calendar: calendar))
        let fresh = words.filter { cards[$0.id] == nil }.prefix(newRemaining)
        return due + fresh
    }

    public static func newCardsIntroduced(on date: Date, cards: [String: CardState], calendar: Calendar = .current) -> Int {
        cards.values.filter { calendar.isDate($0.firstSeen, inSameDayAs: date) }.count
    }

    /// Short text for when a card will be seen again, e.g. "10 min", "3 days".
    public static func intervalText(_ state: CardState, now: Date = Date()) -> String {
        if state.intervalDays == 0 { return "\(relearnMinutes) min" }
        return state.intervalDays == 1 ? "1 day" : "\(state.intervalDays) days"
    }
}
