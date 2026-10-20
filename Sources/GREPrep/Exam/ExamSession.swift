import Foundation
import Observation
import GRECore

/// Drives one sitting of a mock test: phases, the section timer, navigation,
/// Mark/Review and the calculator. Answers and routing live in `ExamRun`.
@MainActor
@Observable
final class ExamSession {
    enum Phase: Equatable {
        case welcome
        case essay
        case sectionIntro
        case question
        case review
        case finished
    }

    private(set) var run: ExamRun
    private(set) var phase: Phase = .welcome
    private(set) var section: TestSection?
    private(set) var questionIndex = 0
    private(set) var remainingSeconds = 0
    var isTimeHidden = false
    var isCalculatorVisible = false
    var calculator = CalculatorEngine()
    /// Shown once when a section ends because time ran out.
    var timeExpiredNotice: String?

    @ObservationIgnored var onFinish: ((MockAttempt) -> Void)?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var deadline = Date()
    @ObservationIgnored private var lastTick = Date()

    init(test: MockTest) {
        run = ExamRun(test: test)
    }

    var test: MockTest { run.test }
    var stepNumber: Int { min(run.stepIndex + 1, run.steps.count) }
    var stepCount: Int { run.steps.count }
    var questions: [Question] { section?.questions ?? [] }
    var currentQuestion: Question? { questions[safe: questionIndex] }
    var isQuant: Bool { section?.measure == .quant }

    var stimulus: Stimulus? { test.stimulus(currentQuestion?.stimulusId) }

    var essayText: String {
        get { run.essayText }
        set { run.essayText = newValue }
    }

    var essayWordCount: Int { run.essayWordCount }

    // MARK: Flow

    func begin() {
        phase = .essay
        startTimer(seconds: test.essay.minutes * 60)
    }

    func finishEssay() {
        // A confirmation alert left open when time runs out must not advance a second time.
        guard phase == .essay else { return }
        stopTimer()
        run.advance()
        prepareNextStep()
    }

    func startSection() {
        guard let section else { return }
        questionIndex = 0
        phase = .question
        startTimer(seconds: section.minutes * 60)
    }

    func exitSection() {
        guard phase == .question || phase == .review else { return }
        stopTimer()
        isCalculatorVisible = false
        run.advance()
        prepareNextStep()
    }

    private func prepareNextStep() {
        while !run.isFinished {
            if run.currentStep == .essay {
                run.advance()
                continue
            }
            if let next = run.currentSection() {
                section = next
                questionIndex = 0
                calculator = CalculatorEngine()
                remainingSeconds = next.minutes * 60
                phase = .sectionIntro
                return
            }
            run.advance() // content missing for this step: skip it
        }
        finish()
    }

    private func finish() {
        stopTimer()
        phase = .finished
        section = nil
        onFinish?(run.makeAttempt())
    }

    /// Stops the clock without recording anything (Quit Test).
    func stop() {
        stopTimer()
    }

    // MARK: Navigation

    var canGoBack: Bool {
        phase == .review || (phase == .question && questionIndex > 0)
    }

    func next() {
        guard phase == .question else { return }
        if questionIndex < questions.count - 1 {
            questionIndex += 1
        } else {
            phase = .review
        }
    }

    func back() {
        if phase == .review {
            phase = .question
        } else if questionIndex > 0 {
            questionIndex -= 1
        }
    }

    func showReview() {
        guard phase == .question else { return }
        phase = .review
    }

    func goToQuestion(_ index: Int) {
        guard questions.indices.contains(index) else { return }
        questionIndex = index
        phase = .question
    }

    // MARK: Answers

    func response(for question: Question) -> Response {
        run.responses[question.id] ?? Response(blankChoices: Array(repeating: nil, count: question.blanks?.count ?? 0))
    }

    func setResponse(_ response: Response, for question: Question) {
        run.responses[question.id] = response
    }

    func isMarked(_ question: Question) -> Bool {
        run.marked.contains(question.id)
    }

    func toggleMark() {
        guard let question = currentQuestion else { return }
        if run.marked.contains(question.id) {
            run.marked.remove(question.id)
        } else {
            run.marked.insert(question.id)
        }
    }

    func state(of question: Question) -> AnswerState {
        run.state(of: question)
    }

    var unansweredCount: Int {
        questions.filter { state(of: $0) != .answered }.count
    }

    /// "Transfer Display": copies the calculator display into a numeric entry box.
    var canTransferDisplay: Bool {
        currentQuestion?.format == .numeric && calculator.displayValue != nil
    }

    func transferDisplay() {
        guard let question = currentQuestion, question.format == .numeric, calculator.displayValue != nil else { return }
        var response = response(for: question)
        response.numberText = calculator.display
        setResponse(response, for: question)
    }

    // MARK: Timer

    private func startTimer(seconds: Int) {
        stopTimer()
        remainingSeconds = seconds
        deadline = Date().addingTimeInterval(TimeInterval(seconds))
        lastTick = Date()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func tick() {
        let now = Date()
        // Cap at the deadline so sleep or App Nap can't inflate recorded time.
        let elapsed = max(0, min(now, deadline).timeIntervalSince(lastTick))
        lastTick = now
        switch phase {
        case .essay:
            run.essaySeconds += elapsed
        case .question, .review:
            if let section { run.sectionSeconds[section.id, default: 0] += elapsed }
            if phase == .question, let question = currentQuestion {
                run.timeSpent[question.id, default: 0] += elapsed
            }
        default:
            break
        }
        remainingSeconds = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        if remainingSeconds == 0 { timeExpired() }
    }

    private func timeExpired() {
        if phase == .essay {
            timeExpiredNotice = "Time is up for the Analytical Writing section. Your response has been saved."
            finishEssay()
        } else if phase == .question || phase == .review {
            timeExpiredNotice = "Time is up for \(section?.title ?? "this section"). Your answers have been saved."
            exitSection()
        }
    }
}
