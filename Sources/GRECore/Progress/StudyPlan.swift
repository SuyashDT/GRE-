import Foundation

/// What the learner told the app about their test date and study time.
public struct StudyPlanSettings: Codable, Hashable, Sendable {
    public var examDate: Date
    /// The first day of the plan. Editing the plan rebuilds it from that day.
    public var startDate: Date
    public var minutesPerDay: Int
    /// `Calendar` weekday kept free of study (1 = Sunday … 7 = Saturday), or nil for none.
    public var restWeekday: Int?

    public init(examDate: Date, startDate: Date, minutesPerDay: Int, restWeekday: Int? = nil) {
        self.examDate = examDate
        self.startDate = startDate
        self.minutesPerDay = minutesPerDay
        self.restWeekday = restWeekday
    }
}

public struct PlanTask: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case lesson(String)
        case drill(String)
        /// Practise the weakest question type so far; `fallback` is the drill used until there's enough data.
        case weakSpot(fallback: String)
        case vocabulary
        case mockTest(String)
        case reviewMock
        case essayOutline
        case lightReview
        /// Something outside the app (a class, an official practice test), from a coach's plan. Ticked by hand.
        case note
        case rest
        case examDay
    }

    /// Unique across the plan: `yyyy-MM-dd/<task>` in a generated plan, the coach's own id in a coach plan.
    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String
    public let minutes: Int
    /// Work done in the app at or after this moment completes the task.
    public let countsFrom: Date
    /// A coach's note that should stay in the catch-up list until it is ticked.
    public let staysUntilDone: Bool

    public init(id: String, kind: Kind, title: String, detail: String, minutes: Int, countsFrom: Date,
                staysUntilDone: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.minutes = minutes
        self.countsFrom = countsFrom
        self.staysUntilDone = staysUntilDone
    }

    /// Whether the app ticks the task off by itself when the work is done in the app.
    public var isTrackedInApp: Bool {
        switch kind {
        case .lesson, .drill, .weakSpot, .vocabulary, .mockTest: return true
        case .reviewMock, .essayOutline, .lightReview, .note, .rest, .examDay: return false
        }
    }

    /// Tasks that stay worth doing after their day has passed.
    public var carriesOver: Bool {
        switch kind {
        case .lesson, .drill, .mockTest, .reviewMock: return true
        case .note: return staysUntilDone
        default: return false
        }
    }
}

public struct PlanDay: Hashable, Sendable, Identifiable {
    public enum Phase: String, Hashable, Sendable {
        case foundations
        case practice
        case finalWeek
        case examDay

        public var title: String {
            switch self {
            case .foundations: return "Foundations"
            case .practice: return "Practice"
            case .finalWeek: return "Final week"
            case .examDay: return "Test day"
            }
        }
    }

    public let id: String
    public let date: Date
    public let phase: Phase
    public let tasks: [PlanTask]
    /// The coach's headline for the day, e.g. "Baseline". Generated plans have none.
    public let focus: String?

    public init(id: String, date: Date, phase: Phase, tasks: [PlanTask], focus: String? = nil) {
        self.id = id
        self.date = date
        self.phase = phase
        self.tasks = tasks
        self.focus = focus
    }

    public var minutes: Int { tasks.map(\.minutes).reduce(0, +) }
    public var isRestDay: Bool { tasks.count == 1 && tasks[0].kind == .rest }
}

/// A day-by-day schedule from the start date to the test, built from the app's own content.
///
/// The plan is a pure function of its settings and the content, so task ids stay stable
/// across launches. Weeks one onward follow three phases: foundations (every lesson with its
/// drill, after a diagnostic mock test), practice (weak spots, redone drills, essay outlines)
/// and a final week that ends with a light day before the test.
public struct StudyPlan: Hashable, Sendable {
    public let settings: StudyPlanSettings
    public let days: [PlanDay]
    /// Set when the lessons and drills don't fit in `settings.minutesPerDay`: about how many minutes a day they need.
    public let minutesNeeded: Int?
    /// Set when the plan was written by a coach (`Coach/plan.json`) rather than generated. See `CoachPlan`.
    public let coach: CoachPlanInfo?

    init(settings: StudyPlanSettings, days: [PlanDay], minutesNeeded: Int?, coach: CoachPlanInfo? = nil) {
        self.settings = settings
        self.days = days
        self.minutesNeeded = minutesNeeded
        self.coach = coach
    }

    public var isCoachPlan: Bool { coach != nil }

    public static let minutesOptions = [30, 45, 60, 90, 120, 180]
    static let vocabularyMinutes = 15
    static let reviewMockMinutes = 30
    static let essayOutlineMinutes = 15
    /// Lessons in teaching order; any others follow in content order.
    static let lessonOrder = [
        "gre-overview", "vocab-strategy", "quant-review", "tc", "qc", "calculator", "se", "ps",
        "awa-issue", "rc", "ma", "ne", "rc-arguments", "di", "pacing",
    ]
    static let overviewLessonId = "gre-overview"

    /// A generated plan ends on the test day. A coach's plan says when the test is.
    public var examDate: Date { isCoachPlan ? settings.examDate : (days.last?.date ?? settings.examDate) }

    public func day(for date: Date, calendar: Calendar = .current) -> PlanDay? {
        let key = StudyCalendar.dayKey(date, calendar: calendar)
        return days.first { $0.id == key }
    }

    // MARK: Building

    private struct Item {
        let kind: PlanTask.Kind
        let title: String
        let detail: String
        let minutes: Int
    }

    public static func make(settings: StudyPlanSettings, content: ContentLibrary, newCardsPerDay: Int,
                            calendar: Calendar = .current) -> StudyPlan {
        let start = calendar.startOfDay(for: settings.startDate)
        let exam = calendar.startOfDay(for: settings.examDate)
        let budget = max(15, settings.minutesPerDay)

        var dates: [Date] = []
        var cursor = start
        while cursor < exam, dates.count < 730 {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        // The day before the test is always a (light) study day, never a rest day.
        let isRest: (Date) -> Bool = { date in
            guard let rest = settings.restWeekday, date != dates.last else { return false }
            return calendar.component(.weekday, from: date) == rest
        }
        let studyDates = dates.filter { !isRest($0) }
        let count = studyDates.count
        var items: [[Item]] = Array(repeating: [], count: count)

        let vocabulary = Item(
            kind: .vocabulary, title: "Vocabulary",
            detail: "Review the cards that are due, then learn \(newCardsPerDay) new words.",
            minutes: vocabularyMinutes
        )
        let lightDay = count >= 2 ? count - 1 : nil

        // Mock tests: a diagnostic first, a dress rehearsal about a week out, any others in between.
        var mockDays: [Int: Item] = [:]
        let mocks = content.mockTests
        if count >= 5, let first = mocks.first {
            mockDays[0] = Item(
                kind: .mockTest(first.id), title: "Diagnostic: \(first.title)",
                detail: "Take the whole test in one sitting (1 h 58 min) to find your starting point. Don't study for it first.",
                minutes: first.totalMinutes
            )
            if count >= 14 {
                let day = count - 7
                let fresh = mocks.count > 1
                let test = fresh ? mocks[mocks.count - 1] : first
                mockDays[day] = Item(
                    kind: .mockTest(test.id), title: "Dress rehearsal: \(test.title)",
                    detail: fresh
                        ? "Take it in one sitting at the time of day of your real test."
                        : "Retake it in one sitting at the time of day of your real test. You'll recognise some questions, so judge your pacing and stamina rather than the score.",
                    minutes: test.totalMinutes
                )
            }
        }
        let reviewDays = Set(mockDays.keys.map { $0 + 1 })

        // Foundations: every lesson, each followed by its drill the first time that drill comes up.
        let lessonsById = Dictionary(content.lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let orderedLessons = lessonOrder.compactMap { lessonsById[$0] }
            + content.lessons.filter { !lessonOrder.contains($0.id) }
        var units: [[Item]] = []
        var usedDrills = Set<String>()
        for lesson in orderedLessons {
            let read = Item(kind: .lesson(lesson.id), title: "Lesson: \(lesson.title)", detail: lesson.summary, minutes: lesson.minutes)
            if lesson.id == overviewLessonId, mockDays[0] != nil {
                // Read the overview right before the diagnostic test.
                items[0].append(read)
                continue
            }
            var unit = [read]
            if let drillId = lesson.drillId, !usedDrills.contains(drillId), let set = content.drillSet(id: drillId) {
                unit.append(drillItem(set, repeat: false))
                usedDrills.insert(drillId)
            }
            units.append(unit)
        }
        for set in content.drills.sets where !usedDrills.contains(set.id) {
            units.append([drillItem(set, repeat: false)])
        }

        var reserved = Set(mockDays.keys)
        if let lightDay { reserved.insert(lightDay) }
        let open = (0..<count).filter { !reserved.contains($0) }
        let dayBudget: (Int) -> Int = { index in
            budget - vocabularyMinutes - (reviewDays.contains(index) ? reviewMockMinutes : 0)
        }

        // Pack units greedily into the open days to see how many days they need.
        var greedy: [Int] = [] // open-day position of each unit
        var position = 0
        var used = 0
        for unit in units {
            let minutes = unit.map(\.minutes).reduce(0, +)
            if used > 0, position < open.count, used + minutes > dayBudget(open[position]) {
                position += 1
                used = 0
            }
            greedy.append(position)
            used += minutes
        }
        var minutesNeeded: Int?
        var placement: [Int] // open-day position of each unit
        if open.isEmpty {
            placement = []
        } else if let last = greedy.last, last >= open.count {
            // Doesn't fit: spread everything over the open days and say how much time that takes.
            placement = units.indices.map { $0 * open.count / units.count }
            let total = units.flatMap { $0 }.map(\.minutes).reduce(0, +)
            minutesNeeded = Int((Double(total) / Double(open.count)).rounded(.up)) + vocabularyMinutes
        } else {
            // Fits: on a long plan, spread the foundations over about 40% of the days rather than cramming them.
            let needed = (greedy.last ?? -1) + 1
            let span = min(units.count, open.count, max(needed, Int((Double(open.count) * 0.4).rounded(.up))))
            placement = span <= needed ? greedy : units.indices.map { $0 * span / units.count }
        }
        let foundationDays = Set(placement.compactMap { $0 < open.count ? open[$0] : nil })
        for (unit, position) in zip(units, placement) where position < open.count {
            items[open[position]] += unit
        }

        // Practice: weak spots every day, plus redone drills and essay outlines as time allows.
        let sets = content.drills.sets
        var practiceCount = 0
        for index in open where !foundationDays.contains(index) {
            guard !sets.isEmpty else { break }
            let weak = sets[practiceCount % sets.count]
            let weakItem = Item(
                kind: .weakSpot(fallback: weak.id), title: "Practise your weakest question type",
                detail: "Redo the drill for the question type you're getting wrong most often.",
                minutes: drillMinutes(weak)
            )
            items[index].append(weakItem)
            var left = dayBudget(index) - weakItem.minutes
            let redo = drillItem(sets[(practiceCount + sets.count / 2) % sets.count], repeat: true)
            let essay = Item(
                kind: .essayOutline, title: "Issue essay outline",
                detail: "Pick a debatable claim, take a position, and outline two reasons and one counterargument in 15 minutes.",
                minutes: essayOutlineMinutes
            )
            let extras = practiceCount % 2 == 0 ? [redo, essay] : [essay, redo]
            for extra in extras where extra.minutes <= left {
                items[index].append(extra)
                left -= extra.minutes
            }
            practiceCount += 1
        }

        // Every study day starts with vocabulary, except full-test days.
        for index in 0..<count where mockDays[index] == nil {
            items[index].insert(vocabulary, at: 0)
        }
        for (index, mock) in mockDays {
            items[index].append(mock)
        }
        for index in reviewDays where index < count {
            items[index].insert(Item(
                kind: .reviewMock, title: "Review your mock test",
                detail: "Go through every question you missed or guessed, read the explanations, and note which question types to work on.",
                minutes: reviewMockMinutes
            ), at: min(1, items[index].count))
        }
        if let lightDay {
            items[lightDay] = [
                Item(kind: .vocabulary, title: "Vocabulary",
                     detail: "Review only the cards that are due. No new words today.", minutes: 10),
                Item(kind: .lightReview, title: "Light review",
                     detail: "Skim the key tips in the pacing and essay lessons. No new material, and get a good night's sleep.",
                     minutes: 20),
            ]
        }

        // Turn items into dated tasks. A repeated drill or test only counts if done after its previous slot.
        let finalWeekStart = calendar.date(byAdding: .day, value: -7, to: exam) ?? exam
        let lastFoundationDate = foundationDays.max().map { studyDates[$0] } ?? start
        var lastSeen: [String: Date] = [:]
        var studyIndex = 0
        var days: [PlanDay] = []
        for date in dates {
            let key = StudyCalendar.dayKey(date, calendar: calendar)
            let phase: PlanDay.Phase = date >= finalWeekStart ? .finalWeek
                : (date <= lastFoundationDate ? .foundations : .practice)
            let dayItems: [Item]
            if isRest(date) {
                dayItems = [Item(kind: .rest, title: "Rest day",
                                 detail: "Take the day off. Rest helps what you've learned stick.", minutes: 0)]
            } else {
                dayItems = items[studyIndex]
                studyIndex += 1
            }
            var seenToday: [String: Int] = [:]
            let tasks = dayItems.map { item -> PlanTask in
                let slug = Self.slug(item.kind)
                seenToday[slug, default: 0] += 1
                let id = "\(key)/\(slug)" + (seenToday[slug]! > 1 ? "-\(seenToday[slug]!)" : "")
                var countsFrom = date
                if let target = Self.repeatKey(item.kind) {
                    countsFrom = lastSeen[target].flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? .distantPast
                    lastSeen[target] = date
                }
                return PlanTask(id: id, kind: item.kind, title: item.title, detail: item.detail,
                                minutes: item.minutes, countsFrom: countsFrom)
            }
            days.append(PlanDay(id: key, date: date, phase: phase, tasks: tasks))
        }
        days.append(PlanDay(
            id: StudyCalendar.dayKey(exam, calendar: calendar), date: exam, phase: .examDay,
            tasks: [PlanTask(
                id: "\(StudyCalendar.dayKey(exam, calendar: calendar))/exam", kind: .examDay, title: "Test day",
                detail: "Be ready early with your ID, or set up your room if you're testing at home. Keep to your pacing, and mark and move on rather than getting stuck.",
                minutes: 118, countsFrom: exam
            )]
        ))
        return StudyPlan(settings: settings, days: days, minutesNeeded: minutesNeeded)
    }

    static func drillMinutes(_ set: DrillSet) -> Int {
        max(10, (set.questions.count * 5 + 1) / 2)
    }

    private static func drillItem(_ set: DrillSet, repeat isRepeat: Bool) -> Item {
        Item(
            kind: .drill(set.id),
            title: isRepeat ? "Redo drill: \(set.title)" : "Drill: \(set.title)",
            detail: isRepeat
                ? "\(set.questions.count) questions. This time, explain why each wrong option is wrong."
                : "\(set.questions.count) untimed questions. Read every explanation, including the ones you got right.",
            minutes: drillMinutes(set)
        )
    }

    private static func slug(_ kind: PlanTask.Kind) -> String {
        switch kind {
        case let .lesson(id): return "lesson-\(id)"
        case let .drill(id): return "drill-\(id)"
        case .weakSpot: return "weak-spot"
        case .vocabulary: return "vocabulary"
        case let .mockTest(id): return "mock-\(id)"
        case .reviewMock: return "review-mock"
        case .essayOutline: return "essay-outline"
        case .lightReview: return "light-review"
        case .note: return "note"
        case .rest: return "rest"
        case .examDay: return "exam"
        }
    }

    /// Tasks that can come up more than once and are completed by doing the same thing again.
    private static func repeatKey(_ kind: PlanTask.Kind) -> String? {
        switch kind {
        case let .drill(id): return "drill-\(id)"
        case let .mockTest(id): return "mock-\(id)"
        default: return nil
        }
    }

    // MARK: Progress

    /// Whether the work for a task shows up in the saved progress (lessons read, drills and tests taken, cards reviewed).
    public static func isCompletedInApp(_ task: PlanTask, on date: Date, progress: ProgressData,
                                        calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let onDay: (Date) -> Bool = { $0 >= dayStart && $0 < dayEnd }
        switch task.kind {
        case let .lesson(id):
            return progress.lessonsRead.contains(id)
        case let .drill(id):
            return progress.drillAttempts.contains { $0.setId == id && $0.date >= task.countsFrom }
        case .weakSpot:
            return progress.drillAttempts.contains { onDay($0.date) }
        case .vocabulary:
            return progress.cards.values.contains { onDay($0.lastReviewed) }
        case let .mockTest(id):
            return progress.mockAttempts.contains { $0.testId == id && $0.completed && $0.finishedAt >= task.countsFrom }
        case .reviewMock, .essayOutline, .lightReview, .note, .rest, .examDay:
            return false
        }
    }

    public static func isDone(_ task: PlanTask, on date: Date, progress: ProgressData,
                              calendar: Calendar = .current) -> Bool {
        progress.planChecked.contains(task.id) || isCompletedInApp(task, on: date, progress: progress, calendar: calendar)
    }
}
