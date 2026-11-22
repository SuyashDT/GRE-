import Foundation

/// What the Study Plan screen says about a coach's plan.
public struct CoachPlanInfo: Hashable, Sendable {
    public let title: String?
    /// When the coach last changed the plan.
    public let updated: Date?
    /// One line from the coach.
    public let note: String?
    /// One line per day or task that had to be left out or shown as a note.
    public let problems: [String]
}

/// Turns the coach's `plan.json` into the plan the app shows, using the app's content
/// for titles, minutes and the Start buttons.
public enum CoachPlan {
    public struct Resolved: Sendable {
        /// Nil when the file has no usable day.
        public let plan: StudyPlan?
        public let problems: [String]
    }

    public static func resolve(_ file: CoachPlanFile, content: ContentLibrary, newCardsPerDay: Int,
                               calendar: Calendar = .current) -> Resolved {
        var problems: [String] = []
        let name = CoachFolder.planFileName

        var seenDays = Set<String>()
        var seenTasks = Set<String>()
        var dated: [(date: Date, day: CoachPlanFile.Day)] = []
        for day in file.days {
            guard let date = StudyCalendar.date(fromDayKey: day.date, calendar: calendar) else {
                problems.append("\(name): \"\(day.date)\" isn't a date (use yyyy-MM-dd), so that day was left out")
                continue
            }
            guard seenDays.insert(StudyCalendar.dayKey(date, calendar: calendar)).inserted else {
                problems.append("\(name): \(day.date) appears twice, so the second one was left out")
                continue
            }
            dated.append((date, day))
        }
        dated.sort { $0.date < $1.date }

        var days: [(date: Date, focus: String?, tasks: [PlanTask])] = []
        for (date, day) in dated {
            var tasks: [PlanTask] = []
            for task in day.tasks {
                guard !task.id.isEmpty, seenTasks.insert(task.id).inserted else {
                    problems.append("\(name): task id \"\(task.id)\" on \(day.date) is empty or used twice, so it was left out")
                    continue
                }
                tasks.append(planTask(task, on: date, content: content, newCardsPerDay: newCardsPerDay, problems: &problems))
            }
            let focus = day.focus?.trimmingCharacters(in: .whitespacesAndNewlines)
            days.append((date, focus?.isEmpty == false ? focus : nil, tasks))
        }
        guard let first = days.first, let last = days.last else {
            return Resolved(plan: nil, problems: problems + ["\(name) has no days that can be shown"])
        }

        var examDate = file.examDate.flatMap { StudyCalendar.date(fromDayKey: $0, calendar: calendar) }
        if examDate == nil, let text = file.examDate, !text.isEmpty {
            problems.append("\(name): examDate \"\(text)\" isn't a date (use yyyy-MM-dd)")
        }
        if examDate == nil {
            examDate = days.first { $0.tasks.contains { $0.kind == .examDay } }?.date ?? last.date
        }
        let exam = examDate ?? last.date
        let finalWeekStart = calendar.date(byAdding: .day, value: -7, to: exam) ?? exam

        let planDays = days.map { day -> PlanDay in
            let phase: PlanDay.Phase
            if day.tasks.contains(where: { $0.kind == .examDay }) || day.date == exam {
                phase = .examDay
            } else {
                phase = day.date >= finalWeekStart ? .finalWeek : .practice
            }
            return PlanDay(id: StudyCalendar.dayKey(day.date, calendar: calendar), date: day.date,
                           phase: phase, tasks: day.tasks, focus: day.focus)
        }

        let trimmed: (String?) -> String? = { text in
            let value = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        let info = CoachPlanInfo(
            title: trimmed(file.title),
            updated: file.updated.flatMap { StudyCalendar.date(fromDayKey: $0, calendar: calendar) },
            note: trimmed(file.note),
            problems: problems
        )
        let plan = StudyPlan(
            settings: StudyPlanSettings(examDate: exam, startDate: first.date, minutesPerDay: 0),
            days: planDays, minutesNeeded: nil, coach: info
        )
        return Resolved(plan: plan, problems: problems)
    }

    private static func planTask(_ task: CoachPlanFile.Task, on date: Date, content: ContentLibrary,
                                 newCardsPerDay: Int, problems: inout [String]) -> PlanTask {
        let name = CoachFolder.planFileName
        let ref = task.ref?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let givenTitle = task.title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }

        func make(_ kind: PlanTask.Kind, title: String, detail: String, minutes: Int) -> PlanTask {
            PlanTask(id: task.id, kind: kind, title: givenTitle ?? title, detail: task.detail ?? detail,
                     minutes: max(0, task.minutes ?? minutes), countsFrom: date,
                     staysUntilDone: kind == .note && task.carryOver == true)
        }
        /// A task the app can't link to anything is still shown, as a note to tick by hand.
        func note(fallbackTitle: String, problem: String?) -> PlanTask {
            if let problem { problems.append("\(name): task \"\(task.id)\" \(problem), so it is shown as a note") }
            return make(.note, title: fallbackTitle, detail: "", minutes: 0)
        }

        switch task.kind.lowercased() {
        case "lesson":
            guard let lesson = content.lesson(id: ref) else {
                return note(fallbackTitle: ref.isEmpty ? "Lesson" : "Lesson: \(ref)",
                            problem: ref.isEmpty ? "has no ref" : "points to a lesson that isn't in the app (\"\(ref)\")")
            }
            return make(.lesson(lesson.id), title: "Lesson: \(lesson.title)", detail: lesson.summary, minutes: lesson.minutes)
        case "drill":
            if let measure = MissedQuestions.measure(forSetId: ref) {
                return make(.drill(ref), title: "Redo your missed \(measure.shortTitle) questions",
                            detail: MissedQuestions.summary(for: measure), minutes: 20)
            }
            guard let set = content.drillSet(id: ref) else {
                return note(fallbackTitle: ref.isEmpty ? "Drill" : "Drill: \(ref)",
                            problem: ref.isEmpty ? "has no ref" : "points to a drill set that isn't in the app (\"\(ref)\")")
            }
            let count = set.questions.count
            if let limit = set.timeLimitMinutes, set.isTimed {
                return make(.drill(set.id), title: "Timed set: \(set.title)",
                            detail: "\(count) questions in \(limit) minutes, like an exam section. The explanations come at the end.",
                            minutes: limit + (count + 1) / 2)
            }
            return make(.drill(set.id), title: "Drill: \(set.title)",
                        detail: "\(count) untimed questions. Read every explanation, including the ones you got right.",
                        minutes: StudyPlan.drillMinutes(set))
        case "mocktest":
            guard let test = content.mockTest(id: ref) else {
                return note(fallbackTitle: ref.isEmpty ? "Mock test" : "Mock test: \(ref)",
                            problem: ref.isEmpty ? "has no ref" : "points to a mock test that isn't in the app (\"\(ref)\")")
            }
            let total = test.totalMinutes
            return make(.mockTest(test.id), title: test.title,
                        detail: "Take the whole test in one sitting (\(total / 60) h \(total % 60) min).",
                        minutes: total)
        case "vocabulary":
            return make(.vocabulary, title: "Vocabulary",
                        detail: "Review the cards that are due, then learn \(newCardsPerDay) new words.",
                        minutes: StudyPlan.vocabularyMinutes)
        case "note":
            return note(fallbackTitle: ref.isEmpty ? "From your coach" : ref, problem: nil)
        case "rest":
            return make(.rest, title: "Rest day", detail: "Take the day off. Rest helps what you've learned stick.", minutes: 0)
        case "exam":
            return make(.examDay, title: "Test day",
                        detail: "Be ready early with your ID, or set up your room if you're testing at home. Keep to your pacing, and mark and move on rather than getting stuck.",
                        minutes: 118)
        default:
            return note(fallbackTitle: ref.isEmpty ? task.kind : ref, problem: "has an unknown kind (\"\(task.kind)\")")
        }
    }

    /// The day a mock test is next planned for in a coach's plan, if that day is after `now`.
    public static func upcomingDay(forMockTest id: String, in plan: StudyPlan?, now: Date = Date(),
                                   calendar: Calendar = .current) -> Date? {
        guard let plan, plan.isCoachPlan else { return nil }
        let today = calendar.startOfDay(for: now)
        let planned = plan.days.filter { $0.tasks.contains { $0.kind == .mockTest(id) } }.map(\.date)
        // Planned for today: go ahead. Otherwise the next later day it is planned for, if any.
        guard !planned.contains(today) else { return nil }
        return planned.first { $0 > today }
    }
}

public extension StudyCalendar {
    /// The start of the local day written as `yyyy-MM-dd`, or nil when the text isn't a real date.
    static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              dayKey(date, calendar: calendar) == "\(parts[0])-\(parts[1])-\(parts[2])"
        else { return nil }
        return calendar.startOfDay(for: date)
    }
}
