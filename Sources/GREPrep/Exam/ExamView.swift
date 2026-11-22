import SwiftUI
import GRECore

/// Full-window test interface modelled on the real GRE: a dark command bar with
/// Quit / Exit Section / Review / Mark / Back / Next, a status line with the
/// question number and clock, and the question below.
struct ExamView: View {
    @Environment(AppModel.self) private var model
    let session: ExamSession

    @State private var confirmQuit = false
    @State private var confirmExitSection = false
    @State private var confirmFinishEssay = false

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
        .onChange(of: session.phase) { _, _ in
            // Close confirmations that no longer apply (e.g. time ran out while one was open).
            confirmExitSection = false
            confirmFinishEssay = false
        }
        .alert("Quit the test?", isPresented: $confirmQuit) {
            Button("Quit Test", role: .destructive) { model.quitExam() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Your answers will be discarded and no score will be recorded.")
        }
        .alert("Exit this section?", isPresented: $confirmExitSection) {
            Button("Exit Section") { session.exitSection() }
            Button("Return", role: .cancel) {}
        } message: {
            Text(exitSectionMessage)
        }
        .alert("Finish the essay?", isPresented: $confirmFinishEssay) {
            Button("Finish Essay") { session.finishEssay() }
            Button("Keep Writing", role: .cancel) {}
        } message: {
            Text("You still have \(Format.clock(session.remainingSeconds)) left. You can't return to the essay once you continue.")
        }
        .alert("Time's up", isPresented: Binding(
            get: { session.timeExpiredNotice != nil },
            set: { if !$0 { session.timeExpiredNotice = nil } }
        )) {
            Button("Continue", role: .cancel) {}
        } message: {
            Text(session.timeExpiredNotice ?? "")
        }
    }

    private var exitSectionMessage: String {
        let open = session.unansweredCount
        let base = "You won't be able to return to this section."
        return open > 0 ? "You have \(open) unanswered or incomplete question\(open == 1 ? "" : "s"). \(base)" : base
    }

    // MARK: Bars

    private var commandBar: some View {
        HStack(spacing: 4) {
            Text(session.test.title)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.leading, 6)
            Spacer()
            switch session.phase {
            case .welcome:
                ExamBarButton("Quit", systemImage: "xmark.circle") { model.quitExam() }
                ExamBarButton("Begin", systemImage: "play.fill") { session.begin() }
                    .keyboardShortcut(.defaultAction)
            case .essay:
                ExamBarButton("Quit Test", systemImage: "xmark.circle") { confirmQuit = true }
                ExamBarButton("Next", systemImage: "chevron.right") { confirmFinishEssay = true }
            case .sectionIntro:
                ExamBarButton("Quit Test", systemImage: "xmark.circle") { confirmQuit = true }
                ExamBarButton("Continue", systemImage: "chevron.right") { session.startSection() }
                    .keyboardShortcut(.defaultAction)
            case .question:
                ExamBarButton("Quit Test", systemImage: "xmark.circle") { confirmQuit = true }
                ExamBarButton("Exit Section", systemImage: "rectangle.portrait.and.arrow.right") { confirmExitSection = true }
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
                ExamBarButton("Quit Test", systemImage: "xmark.circle") { confirmQuit = true }
                ExamBarButton("Exit Section", systemImage: "rectangle.portrait.and.arrow.right") { confirmExitSection = true }
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
            Text(statusTitle)
                .font(.subheadline.weight(.semibold))
            if session.phase == .question {
                Text("Question \(session.questionIndex + 1) of \(session.questions.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }
            Spacer()
            if [ExamSession.Phase.essay, .question, .review].contains(session.phase) {
                if !session.isTimeHidden {
                    Text(Format.clock(session.remainingSeconds))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(session.remainingSeconds <= 300 ? Theme.incorrect : .primary)
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

    private var statusTitle: String {
        switch session.phase {
        case .welcome: return "Welcome"
        case .essay: return "Section \(session.stepNumber) of \(session.stepCount) — Analytical Writing"
        case .sectionIntro, .question, .review:
            return "Section \(session.stepNumber) of \(session.stepCount) — \(session.section?.measure.title ?? "")"
        case .finished: return "Test complete"
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .welcome:
            ExamWelcomeView(test: session.test)
        case .essay:
            EssayTaskView(session: session)
        case .sectionIntro:
            SectionIntroView(session: session)
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
            ProgressView("Scoring your test…")
        }
    }
}

struct ExamBarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .frame(minWidth: 64, minHeight: 38)
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.35))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 2)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Intro screens

struct ExamWelcomeView: View {
    let test: MockTest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(test.title)
                    .font(.largeTitle.weight(.semibold))
                Text(test.description)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox("What to expect") {
                    VStack(alignment: .leading, spacing: 8) {
                        row("1", "Analytical Writing — Analyze an Issue", "\(test.essay.minutes) minutes")
                        ForEach(Array(sectionRows.enumerated()), id: \.offset) { index, item in
                            row("\(index + 2)", item.0, item.1)
                        }
                    }
                    .padding(6)
                }

                GroupBox("How it works") {
                    VStack(alignment: .leading, spacing: 6) {
                        bullet("Total testing time is about \(test.totalMinutes / 60) hour \(test.totalMinutes % 60) minutes, with no scheduled break.")
                        bullet("The second Verbal and Quant sections adapt to how many questions you answered correctly in the first section of that measure.")
                        bullet("Within a section you can move back and forth, mark questions, and use Review to jump to any question.")
                        bullet("There is no penalty for wrong answers — answer every question.")
                        bullet("Quant sections include an on-screen calculator. The essay editor has no spell-check, as on the real test.")
                        bullet("When you finish, you'll get estimated Verbal and Quant scores, and Claude Code will grade your essay.")
                    }
                    .padding(6)
                }

                Text("Click **Begin** when you're ready. The clock starts immediately.")
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var sectionRows: [(String, String)] {
        test.steps.compactMap { step in
            guard case let .section(measure, stage) = step else { return nil }
            let section = test.section(measure, stage: stage, tier: stage == 1 ? .standard : .harder)
            let detail = "\(section?.questions.count ?? 0) questions · \(section?.minutes ?? 0) minutes"
            return ("\(measure.title) — Section \(stage)", detail)
        }
    }

    private func row(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack {
            Text(number)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.examBar))
                .foregroundStyle(.white)
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(LocalizedStringKey(text)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SectionIntroView: View {
    let session: ExamSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let section = session.section {
                Text(section.measure.title)
                    .font(.largeTitle.weight(.semibold))
                Text("Section \(section.stage) of 2 for this measure · \(section.questions.count) questions · \(section.minutes) minutes")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(directions(for: section.measure))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                if section.measure == .quant {
                    Label("An on-screen calculator is available from the command bar.", systemImage: "plusminus")
                        .foregroundStyle(.secondary)
                }
                Text("Click **Continue** to start the section. The clock starts immediately.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }

    private func directions(for measure: Measure) -> String {
        switch measure {
        case .verbal:
            return "For each question, follow the directions shown. Text Completion and Sentence Equivalence questions give no credit for partially correct answers. Reading Comprehension questions may ask you to select one answer, all answers that apply, or a sentence in the passage."
        case .quant:
            return "All numbers used are real numbers. Figures are described in words; assume lines described as straight are straight. For numeric entry, enter an integer, a decimal, or a fraction as directed; equivalent fractions such as 2/4 and 1/2 are both correct."
        }
    }
}

// MARK: - Review screen

struct ReviewScreen: View {
    let session: ExamSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review")
                .font(.title2.weight(.semibold))
            Text("Select a question to go to it. You can still change any answer until you exit the section.")
                .foregroundStyle(.secondary)
            Table(rows) {
                TableColumn("Question") { row in
                    Text("Question \(row.index + 1)")
                }
                .width(120)
                TableColumn("Status") { row in
                    Text(row.state.title)
                        .foregroundStyle(row.state == .answered ? Color.primary : Theme.incorrect)
                }
                .width(140)
                TableColumn("Marked") { row in
                    if row.marked {
                        Image(systemName: "checkmark.square.fill").foregroundStyle(Theme.marked)
                    }
                }
                .width(70)
                TableColumn("") { row in
                    Button("Go to Question") { session.goToQuestion(row.index) }
                        .controlSize(.small)
                }
                .width(140)
            }
            HStack {
                Text("\(session.questions.count - session.unansweredCount) of \(session.questions.count) answered")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(24)
    }

    struct Row: Identifiable {
        let index: Int
        let state: AnswerState
        let marked: Bool
        var id: Int { index }
    }

    private var rows: [Row] {
        session.questions.enumerated().map { index, question in
            Row(index: index, state: session.state(of: question), marked: session.isMarked(question))
        }
    }
}
