import SwiftUI
import GRECore

/// Full-window interface for a timed drill set, laid out like a mock-test section:
/// the dark command bar, a status line with the question number and the clock, and the question below.
struct TimedDrillView: View {
    @Environment(AppModel.self) private var model
    let session: TimedDrillSession

    @State private var confirmQuit = false
    @State private var confirmFinish = false

    var body: some View {
        VStack(spacing: 0) {
            commandBar
            statusBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    if session.isCalculatorVisible && session.isQuant && session.phase == .question {
                        CalculatorPanel(session: session)
                            .padding(16)
                    }
                }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert("Quit this set?", isPresented: $confirmQuit) {
            Button("Quit Set", role: .destructive) { model.quitTimedDrill() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Your answers will be discarded and nothing will be recorded.")
        }
        .alert("Finish the set?", isPresented: $confirmFinish) {
            Button("Finish") { session.finish() }
            Button("Return", role: .cancel) {}
        } message: {
            Text(finishMessage)
        }
    }

    private var finishMessage: String {
        let open = session.unansweredCount
        let left = "You still have \(Format.clock(session.remainingSeconds)) left."
        let next = "You'll see the answers and explanations next."
        return open > 0
            ? "You have \(open) unanswered or incomplete question\(open == 1 ? "" : "s"). \(left) \(next)"
            : "\(left) \(next)"
    }

    // MARK: Bars

    private var commandBar: some View {
        HStack(spacing: 4) {
            Text(session.drill.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.leading, 6)
            Spacer()
            switch session.phase {
            case .question:
                ExamBarButton("Quit", systemImage: "xmark.circle") { confirmQuit = true }
                ExamBarButton("Finish", systemImage: "flag.checkered") { confirmFinish = true }
                ExamBarButton("Review", systemImage: "list.bullet.rectangle") { session.showReview() }
                ExamBarButton(isMarked ? "Unmark" : "Mark", systemImage: isMarked ? "checkmark.square.fill" : "checkmark.square") {
                    session.toggleMark()
                }
                .keyboardShortcut("m", modifiers: .command)
                if session.isQuant {
                    ExamBarButton("Calculator", systemImage: "plusminus") { session.isCalculatorVisible.toggle() }
                }
                ExamBarButton("Back", systemImage: "chevron.left") { session.back() }
                    .disabled(!session.canGoBack)
                    .keyboardShortcut("[", modifiers: .command)
                ExamBarButton("Next", systemImage: "chevron.right") { session.next() }
                    .keyboardShortcut("]", modifiers: .command)
            case .review:
                ExamBarButton("Quit", systemImage: "xmark.circle") { confirmQuit = true }
                ExamBarButton("Finish", systemImage: "flag.checkered") { confirmFinish = true }
                ExamBarButton("Return", systemImage: "arrow.uturn.backward") { session.back() }
            case .finished:
                EmptyView()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.examBar)
    }

    private var isMarked: Bool {
        session.currentQuestion.map { session.isMarked($0) } ?? false
    }

    private var statusBar: some View {
        HStack {
            Text("Timed set — \(session.drill.measure.title)")
                .font(.subheadline.weight(.semibold))
            if session.phase == .question {
                Text("Question \(session.questionIndex + 1) of \(session.questions.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }
            Spacer()
            if session.phase != .finished {
                if !session.isTimeHidden {
                    Text(Format.clock(session.remainingSeconds))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(session.remainingSeconds <= 60 ? Theme.incorrect : .primary)
                        .accessibilityLabel("Time remaining \(Format.clock(session.remainingSeconds))")
                }
                Button(session.isTimeHidden ? "Show Time" : "Hide Time") { session.isTimeHidden.toggle() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.examSubBar)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .question:
            if let question = session.currentQuestion {
                QuestionScreen(
                    question: question,
                    stimulus: session.stimulus,
                    response: Binding(
                        get: { session.response(for: question) },
                        set: { session.setResponse($0, for: question) }
                    ),
                    mode: .test
                )
                .id(question.id)
            }
        case .review:
            ReviewScreen(session: session)
        case .finished:
            ProgressView("Checking your answers…")
        }
    }
}

/// The page of a timed set in Practice Drills: what it is, the Start button,
/// and the results of earlier attempts with every explanation.
struct TimedSetView: View {
    @Environment(AppModel.self) private var model
    let drill: DrillSet

    @State private var shownAttempt: UUID?
    @State private var reviewing: ReviewTarget?

    struct ReviewTarget: Identifiable, Hashable {
        let attemptId: UUID
        let index: Int
        var id: String { "\(attemptId)-\(index)" }
    }

    /// Timed attempts of this set, newest first.
    private var attempts: [DrillAttempt] {
        model.drillAttempts(setId: drill.id).filter(\.isTimed).sorted { $0.date > $1.date }
    }

    var body: some View {
        let attempts = attempts
        let attempt = attempts.first { $0.id == shownAttempt } ?? attempts.first
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(hasAttempts: !attempts.isEmpty)
                if let attempt {
                    results(attempt, all: attempts)
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(drill.title)
        .sheet(item: $reviewing) { target in
            if let attempt = attempts.first(where: { $0.id == target.attemptId }) {
                DrillReviewSheet(drill: drill, attempt: attempt, startIndex: target.index)
            }
        }
    }

    private func header(hasAttempts: Bool) -> some View {
        let minutes = drill.timeLimitMinutes ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            Text(drill.title).font(.largeTitle.weight(.semibold))
            HStack(spacing: 6) {
                Pill(text: drill.measure.shortTitle, color: Theme.color(for: drill.measure))
                Pill(text: drill.categoryTitle)
                Pill(text: "\(drill.questions.count) question\(drill.questions.count == 1 ? "" : "s")")
                Pill(text: "\(minutes) min", color: .orange)
            }
            if !drill.summary.isEmpty {
                Text(drill.summary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = drill.note, !note.isEmpty {
                CoachNote(text: note)
            }
            Text("It runs like a section of the real test. The clock starts as soon as you click the button, you can move between questions and mark them, and the answers and explanations appear when you finish or the time runs out.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.startTimedDrill(drill)
            } label: {
                Label(hasAttempts ? "Start Again (\(minutes) min)" : "Start (\(minutes) min)", systemImage: "play.fill")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func results(_ attempt: DrillAttempt, all: [DrillAttempt]) -> some View {
        let limit = (attempt.timeLimitMinutes ?? drill.timeLimitMinutes ?? 0) * 60
        let used = min(attempt.secondsUsed ?? 0, Double(limit))
        return VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text(attempt.id == all.first?.id ? "Your last attempt" : "Earlier attempt")
                    .font(.title2.weight(.semibold))
                Spacer()
                if all.count > 1 {
                    Picker("Attempt", selection: Binding(
                        get: { attempt.id },
                        set: { shownAttempt = $0 }
                    )) {
                        ForEach(all) { item in
                            Text("\(Format.date.string(from: item.date)) · \(item.correctCount)/\(item.results.count)").tag(item.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
            }
            HStack(spacing: 14) {
                StatTile(title: "Correct", value: "\(attempt.correctCount) of \(attempt.results.count)",
                         detail: Format.date.string(from: attempt.date), systemImage: "checkmark.circle",
                         tint: Theme.color(for: drill.measure))
                StatTile(title: "Time used", value: Format.minutesSeconds(used),
                         detail: used >= Double(limit) ? "Time ran out (\(limit / 60) min)" : "of \(limit / 60) min",
                         systemImage: "clock", tint: used >= Double(limit) ? .orange : .accentColor)
                StatTile(title: "Pace", value: Format.minutesSeconds(used / Double(max(1, attempt.results.count))),
                         detail: "a question; the real test allows \(Format.minutesSeconds(Pacing.target(for: drill.measure)))",
                         systemImage: "speedometer")
            }
            Text("Select a question to see your answer, the correct answer and the explanation.")
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(attempt.results.enumerated()), id: \.offset) { index, result in
                    Button {
                        reviewing = ReviewTarget(attemptId: attempt.id, index: index)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: result.correct ? "checkmark.circle.fill" : (result.answered ? "xmark.circle.fill" : "minus.circle"))
                                .foregroundStyle(result.correct ? Theme.correct : (result.answered ? Theme.incorrect : .secondary))
                            Text("Q\(index + 1)").monospacedDigit().frame(width: 36, alignment: .leading)
                            Text(result.category.title).frame(width: 200, alignment: .leading)
                            Text(result.topic).foregroundStyle(.secondary)
                            Spacer()
                            Text("Difficulty \(result.difficulty)").font(.caption).foregroundStyle(.secondary)
                            Text(Format.minutesSeconds(result.seconds))
                                .monospacedDigit()
                                .foregroundStyle(result.seconds > Pacing.target(for: drill.measure) * 1.5 ? Color.orange : Color.secondary)
                                .frame(width: 50, alignment: .trailing)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < attempt.results.count - 1 { Divider() }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// A line from the coach, set apart from the app's own text.
struct CoachNote: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "person.crop.circle.badge.checkmark")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Steps through the questions of a finished timed set: the learner's answer, the key and the explanation.
struct DrillReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let drill: DrillSet
    let attempt: DrillAttempt
    @State private var index: Int

    init(drill: DrillSet, attempt: DrillAttempt, startIndex: Int) {
        self.drill = drill
        self.attempt = attempt
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        let result = attempt.results[safe: index]
        let question = result.flatMap { item in drill.questions.first { $0.id == item.questionId } }
        VStack(spacing: 0) {
            HStack {
                Text("Question \(index + 1) of \(attempt.results.count)").font(.headline)
                Spacer()
                Button("Previous") { index -= 1 }
                    .disabled(index <= 0)
                    .keyboardShortcut("[", modifiers: .command)
                Button("Next") { index += 1 }
                    .disabled(index >= attempt.results.count - 1)
                    .keyboardShortcut("]", modifiers: .command)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            if let question, let result {
                QuestionScreen(
                    question: question,
                    stimulus: model.content?.stimulus(for: question),
                    response: .constant(result.response ?? Response()),
                    mode: .review,
                    timeSpent: result.seconds
                )
                .id(question.id)
            } else {
                ContentUnavailableView("This question is no longer in the set", systemImage: "questionmark.folder",
                                       description: Text("The coach's file has changed since this attempt."))
            }
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 620, idealHeight: 760)
    }
}
