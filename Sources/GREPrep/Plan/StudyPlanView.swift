import SwiftUI
import GRECore

struct StudyPlanView: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var showPast = false

    var body: some View {
        // Re-render every minute so "today" moves on at midnight.
        TimelineView(.everyMinute) { context in
            if let plan = model.studyPlan {
                planBody(plan, now: context.date)
            } else {
                setup
            }
        }
        .navigationTitle("Study Plan")
        .sheet(isPresented: $editing) {
            PlanEditSheet()
        }
        .confirmationDialog("Delete your study plan?", isPresented: $confirmDelete) {
            Button("Delete Plan", role: .destructive) { model.deleteStudyPlan() }
        } message: {
            Text("Your lessons, drills, tests and vocabulary progress are kept.")
        }
    }

    // MARK: No plan yet

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Study Plan").font(.largeTitle.weight(.semibold))
                    Text("Tell the app when you're taking the GRE and how much time you have each day. It lays out every day until then: a diagnostic mock test, every lesson with its drill, daily vocabulary, practice on your weak spots, a dress rehearsal a week out and a light day before the test.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CoachWarning(problems: model.coachPlanProblems)
                PlanSettingsForm(settings: nil, buttonTitle: "Create Plan")
                    .frame(maxWidth: 560)
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Plan

    private func planBody(_ plan: StudyPlan, now: Date) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let daysLeft = calendar.dateComponents([.day], from: today, to: plan.examDate).day ?? 0
        let todayPlan = plan.day(for: now)
        let pastDays = plan.days.filter { $0.date < today }
        let overdue = pastDays.flatMap { day in
            day.tasks.filter { $0.carriesOver && !model.isDone($0, on: day) }.map { (day, $0) }
        }
        let dueSoFar = plan.days.filter { $0.date <= today }.flatMap { day in
            day.tasks.filter { $0.kind != .rest && $0.kind != .examDay }.map { (day, $0) }
        }
        let doneSoFar = dueSoFar.filter { model.isDone($0.1, on: $0.0) }.count
        let shownDays = showPast ? plan.days : plan.days.filter { $0.date >= today }

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Study Plan").font(.largeTitle.weight(.semibold))
                        Text(summary(daysLeft: daysLeft, examDate: plan.examDate))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !plan.isCoachPlan {
                        Button("Edit Plan…") { editing = true }
                        Button("Delete…", role: .destructive) { confirmDelete = true }
                    }
                }

                if let coach = plan.coach {
                    coachBanner(coach)
                }
                CoachWarning(problems: model.coachPlanProblems)

                if let needed = plan.minutesNeeded {
                    Label("All the lessons and drills need about \(needed) minutes a day to fit before your test. Days are fuller than you asked for; allow more time a day or pick a later date if you can.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if daysLeft < 0 {
                    if plan.isCoachPlan {
                        ContentUnavailableView {
                            Label("Your test date has passed", systemImage: "flag.checkered")
                        } description: {
                            Text("This plan came from your coach. Ask them for a new one if you're taking the test again.")
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Your test date has passed", systemImage: "flag.checkered")
                        } description: {
                            Text("If you're taking the test again, set a new date.")
                        } actions: {
                            Button("Set a New Date…") { editing = true }
                        }
                    }
                } else {
                    if let todayPlan {
                        todayCard(todayPlan)
                    } else if plan.isCoachPlan {
                        card("Today", subtitle: "Your coach's plan has nothing for today.") {
                            EmptyView()
                        }
                    }
                    if !dueSoFar.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView(value: Double(doneSoFar), total: Double(dueSoFar.count))
                                .tint(Theme.correct)
                                .frame(maxWidth: 320)
                            Text("\(doneSoFar) of \(dueSoFar.count) tasks done so far")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !overdue.isEmpty {
                        card("Catch up", subtitle: "Earlier tasks that are still worth doing") {
                            ForEach(overdue, id: \.1.id) { day, task in
                                PlanTaskRow(task: task, day: day, showsDate: true)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Schedule").font(.title2.weight(.semibold))
                        Spacer()
                        if !pastDays.isEmpty {
                            Button(showPast ? "Hide Earlier Days" : "Show Earlier Days (\(pastDays.count))") {
                                showPast.toggle()
                            }
                            .buttonStyle(.link)
                        }
                    }
                    ForEach(weeks(shownDays, plan: plan), id: \.number) { week in
                        weekSection(week, today: today, showsPhases: !plan.isCoachPlan)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func summary(daysLeft: Int, examDate: Date) -> String {
        let date = examDate.formatted(date: .complete, time: .omitted)
        switch daysLeft {
        case ..<0: return "Your test was on \(date)."
        case 0: return "Your test is today. Good luck!"
        case 1: return "Your test is tomorrow, \(date)."
        default: return "\(daysLeft) days until your test on \(date)."
        }
    }

    /// Says whose plan this is, when the coach last changed it, and passes on the coach's note.
    private func coachBanner(_ coach: CoachPlanInfo) -> some View {
        var label = "From your coach"
        if let title = coach.title { label += ": \(title)" }
        if let updated = coach.updated {
            label += " · updated \(updated.formatted(date: .abbreviated, time: .omitted))"
        }
        return VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
            if let note = coach.note {
                Text(note).fixedSize(horizontal: false, vertical: true)
            }
            Text("This plan replaces the app's own. Lessons, drills, tests and vocabulary tick themselves off when you do them here; tick the other tasks yourself.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func todayCard(_ day: PlanDay) -> some View {
        let open = day.tasks.filter { !model.isDone($0, on: day) && $0.kind != .rest }
        let subtitle: String
        if day.isRestDay {
            subtitle = day.focus ?? "Rest day"
        } else if open.isEmpty {
            subtitle = "All done for today. Nice work!"
        } else if let focus = day.focus {
            subtitle = day.minutes > 0 ? "\(focus) · about \(day.minutes) min" : focus
        } else {
            subtitle = "\(day.phase.title) · about \(day.minutes) min"
        }
        return card("Today", subtitle: subtitle) {
            ForEach(day.tasks) { task in
                PlanTaskRow(task: task, day: day)
            }
        }
    }

    private struct Week {
        let number: Int
        let days: [PlanDay]
    }

    private func weeks(_ days: [PlanDay], plan: StudyPlan) -> [Week] {
        guard let start = plan.days.first?.date else { return [] }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: days) { day in
            (calendar.dateComponents([.day], from: start, to: day.date).day ?? 0) / 7
        }
        return grouped.keys.sorted().map { Week(number: $0 + 1, days: grouped[$0] ?? []) }
    }

    private func weekSection(_ week: Week, today: Date, showsPhases: Bool) -> some View {
        let phases = !showsPhases ? [] : week.days.map(\.phase).reduce(into: [PlanDay.Phase]()) { if !$0.contains($1) { $0.append($1) } }
        let range = [week.days.first, week.days.last].compactMap { $0?.date.formatted(.dateTime.month(.abbreviated).day()) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Week \(week.number)").font(.headline)
                Text(Set(range).count == 2 ? "\(range[0]) – \(range[1])" : range.first ?? "")
                    .foregroundStyle(.secondary)
                ForEach(phases, id: \.self) { phase in
                    PhaseChip(phase: phase)
                }
            }
            VStack(spacing: 0) {
                ForEach(week.days) { day in
                    dayRow(day, isToday: day.date == today, isPast: day.date < today)
                    if day.id != week.days.last?.id { Divider() }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func dayRow(_ day: PlanDay, isToday: Bool, isPast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isToday ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if day.minutes > 0, !day.isRestDay, day.phase != .examDay {
                    Text("\(day.minutes) min").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
            .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if let focus = day.focus {
                    Text(focus)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(day.tasks) { task in
                    PlanTaskRow(task: task, day: day, compact: true)
                }
            }
        }
        .padding(12)
        .opacity(isPast ? 0.7 : 1)
        .background(isToday ? Color.accentColor.opacity(0.08) : .clear)
    }

    private func card<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct PhaseChip: View {
    let phase: PlanDay.Phase

    var body: some View {
        Text(phase.title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch phase {
        case .foundations: return .indigo
        case .practice: return .teal
        case .finalWeek: return .orange
        case .examDay: return .red
        }
    }
}

struct PlanTaskRow: View {
    @Environment(AppModel.self) private var model
    let task: PlanTask
    let day: PlanDay
    var compact = false
    var showsDate = false

    var body: some View {
        let done = model.isDone(task, on: day)
        let doneInApp = model.isCompletedInApp(task, on: day)
        let checkable = task.kind != .rest
        HStack(alignment: compact ? .center : .top, spacing: 10) {
            if checkable {
                Button {
                    model.togglePlanTask(task)
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(compact ? .body : .title3)
                        .foregroundStyle(done ? Theme.correct : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(doneInApp)
                .help(doneInApp ? "Done in the app" : (done ? "Mark as not done" : "Mark as done"))
                .accessibilityLabel("\(title), \(done ? "done" : "not done")")
            }
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(done ? Color.secondary : tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(done ? .secondary : .primary)
                if !compact {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .help(compact ? detail : "")
            Spacer(minLength: 8)
            if showsDate {
                Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !compact, task.minutes > 0, task.kind != .examDay {
                Text("\(task.minutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if model.canOpen(task), !compact || !done {
                Button(openTitle) { model.open(task) }
                    .controlSize(.small)
            }
        }
    }

    private var title: String {
        if case let .weakSpot(fallback) = task.kind, let drill = model.weakSpotDrill(fallback: fallback) {
            return drill.weakest == nil ? "Practice drill: \(drill.set.title)" : "Weak spot: \(drill.set.title)"
        }
        return task.title
    }

    private var detail: String {
        if case let .weakSpot(fallback) = task.kind, let drill = model.weakSpotDrill(fallback: fallback) {
            if let weakest = drill.weakest {
                return "Your accuracy here is \(Format.percent(weakest.accuracy)), your lowest so far. Redo the drill and read every explanation."
            }
            return "\(drill.set.questions.count) questions. Once you've answered more questions, this switches to the question type you miss most."
        }
        return task.detail
    }

    private var openTitle: String {
        switch task.kind {
        case .lesson, .essayOutline, .lightReview: return "Read"
        case .drill, .weakSpot: return "Practise"
        case .vocabulary: return "Study"
        case .mockTest: return "Go to Test"
        case .reviewMock: return "Review"
        case .note, .rest, .examDay: return "Open"
        }
    }

    private var icon: String {
        switch task.kind {
        case .lesson: return "lightbulb"
        case .drill: return "target"
        case .weakSpot: return "scope"
        case .vocabulary: return "character.book.closed"
        case .mockTest: return "doc.text.magnifyingglass"
        case .reviewMock: return "magnifyingglass"
        case .essayOutline: return "pencil.and.outline"
        case .lightReview: return "leaf"
        case .note: return "person.crop.circle.badge.checkmark"
        case .rest: return "moon.zzz"
        case .examDay: return "flag.checkered"
        }
    }

    private var tint: Color {
        switch task.kind {
        case let .lesson(id):
            return model.content?.lesson(id: id).map { Theme.color(forArea: $0.measure) } ?? .accentColor
        case let .drill(id):
            return model.content?.drillSet(id: id).map { Theme.color(for: $0.measure) } ?? .accentColor
        case .weakSpot: return .pink
        case .vocabulary: return Theme.correct
        case .mockTest, .reviewMock: return .blue
        case .essayOutline: return .purple
        case .note: return .orange
        case .lightReview, .rest: return .gray
        case .examDay: return .red
        }
    }
}

/// Test date, daily study time and rest day. Saving (re)builds the plan from today.
struct PlanSettingsForm: View {
    @Environment(AppModel.self) private var model
    let buttonTitle: String
    var onSave: () -> Void = {}

    @State private var examDate: Date
    @State private var minutesPerDay: Int
    /// 0 means no rest day.
    @State private var restWeekday: Int

    init(settings: StudyPlanSettings?, buttonTitle: String, onSave: @escaping () -> Void = {}) {
        self.buttonTitle = buttonTitle
        self.onSave = onSave
        let defaultDate = Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date()
        _examDate = State(initialValue: max(settings?.examDate ?? defaultDate, Self.earliestDate))
        _minutesPerDay = State(initialValue: settings?.minutesPerDay ?? 60)
        _restWeekday = State(initialValue: settings?.restWeekday ?? 0)
    }

    private static var earliestDate: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
    }

    private var latestDate: Date {
        Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
    }

    private var daysUntil: Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: examDate)).day ?? 0
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Test date", selection: $examDate, in: Self.earliestDate...latestDate, displayedComponents: .date)
                Picker("Study time a day", selection: $minutesPerDay) {
                    ForEach(StudyPlan.minutesOptions, id: \.self) { minutes in
                        Text(Self.duration(minutes)).tag(minutes)
                    }
                }
                Picker("Rest day", selection: $restWeekday) {
                    Text("None").tag(0)
                    ForEach(1...7, id: \.self) { weekday in
                        Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                    }
                }
            } footer: {
                Text(daysUntil == 1 ? "Your test is tomorrow." : "\(daysUntil) days from today. Mock-test days take about 2 hours.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(buttonTitle) {
                    model.setStudyPlan(examDate: examDate, minutesPerDay: minutesPerDay,
                                       restWeekday: restWeekday == 0 ? nil : restWeekday)
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
    }

    static func duration(_ minutes: Int) -> String {
        switch minutes {
        case ..<60: return "\(minutes) minutes"
        case 60: return "1 hour"
        default: return minutes % 60 == 0 ? "\(minutes / 60) hours" : "\(minutes / 60) h \(minutes % 60) min"
        }
    }
}

struct PlanEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit Study Plan").font(.title2.weight(.semibold))
            Text("Saving rebuilds the plan from today. Lessons, drills, tests and vocabulary you've done in the app stay ticked off.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PlanSettingsForm(settings: model.studyPlan?.settings, buttonTitle: "Rebuild Plan") { dismiss() }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}
