import Foundation
import Observation
import GRECore

/// What the review table needs from a running section: used by mock-test sections and timed drill sets.
@MainActor
protocol SectionReviewing: AnyObject, Observable {
    var questions: [Question] { get }
    var unansweredCount: Int { get }
    func state(of question: Question) -> AnswerState
    func isMarked(_ question: Question) -> Bool
    func goToQuestion(_ index: Int)
}

/// What the on-screen calculator needs from whatever is showing it.
@MainActor
protocol CalculatorHosting: AnyObject, Observable {
    var calculator: CalculatorEngine { get set }
    var isCalculatorVisible: Bool { get set }
    var canTransferDisplay: Bool { get }
    func transferDisplay()
}

extension ExamSession: SectionReviewing, CalculatorHosting {}

/// Drives one sitting of a timed drill set. It behaves like one section of a mock test:
/// a countdown, free movement between questions, Mark and Review, the calculator for Quant,
/// and no answers or explanations until the set is finished or time runs out.
@MainActor
@Observable
final class TimedDrillSession: SectionReviewing, CalculatorHosting {
    enum Phase: Equatable {
        case question
        case review
        case finished
    }

    let drill: DrillSet
    private(set) var phase: Phase = .question
    private(set) var questionIndex = 0
    private(set) var remainingSeconds: Int
    private(set) var responses: [String: Response] = [:]
    private(set) var marked: Set<String> = []
    var isTimeHidden = false
    var isCalculatorVisible = false
    var calculator = CalculatorEngine()

    @ObservationIgnored var onFinish: ((DrillAttempt) -> Void)?
    @ObservationIgnored private let stimuli: [String: Stimulus]
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var deadline = Date()
    @ObservationIgnored private var lastTick = Date()
    /// Seconds spent looking at each question.
    @ObservationIgnored private var timeSpent: [String: Double] = [:]
    @ObservationIgnored private var secondsUsed: Double = 0

    init(drill: DrillSet, stimuli: [Stimulus]) {
        self.drill = drill
        let needed = Set(drill.questions.compactMap(\.stimulusId))
        self.stimuli = Dictionary(stimuli.filter { needed.contains($0.id) }.map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })
        remainingSeconds = Self.limitSeconds(of: drill)
    }

    static func limitSeconds(of drill: DrillSet) -> Int { max(1, drill.timeLimitMinutes ?? 0) * 60 }

    var questions: [Question] { drill.questions }
    var currentQuestion: Question? { questions[safe: questionIndex] }
    var isQuant: Bool { drill.measure == .quant }
    var stimulus: Stimulus? { currentQuestion?.stimulusId.flatMap { stimuli[$0] } }

    // MARK: Flow

    /// Starts the clock.
    func begin() {
        guard timerTask == nil, phase != .finished else { return }
        let seconds = Self.limitSeconds(of: drill)
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

    /// Ends the set and hands over the results. Does nothing the second time,
    /// so a confirmation left open when time runs out can't record the set twice.
    func finish() {
        guard phase != .finished else { return }
        stopTimer()
        isCalculatorVisible = false
        phase = .finished
        onFinish?(makeAttempt())
    }

    /// Stops the clock without recording anything (Quit).
    func stop() {
        stopTimer()
    }

    func makeAttempt(date: Date = Date()) -> DrillAttempt {
        drill.makeAttempt(responses: responses, timeSpent: timeSpent, timed: true, secondsUsed: secondsUsed, date: date)
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
        } else if phase == .question, questionIndex > 0 {
            questionIndex -= 1
        }
    }

    func showReview() {
        guard phase == .question else { return }
        phase = .review
    }

    func goToQuestion(_ index: Int) {
        guard phase != .finished, questions.indices.contains(index) else { return }
        questionIndex = index
        phase = .question
    }

    // MARK: Answers

    func response(for question: Question) -> Response {
        responses[question.id] ?? Response(blankChoices: Array(repeating: nil, count: question.blanks?.count ?? 0))
    }

    func setResponse(_ response: Response, for question: Question) {
        guard phase != .finished else { return }
        responses[question.id] = response
    }

    func isMarked(_ question: Question) -> Bool {
        marked.contains(question.id)
    }

    func toggleMark() {
        guard let question = currentQuestion else { return }
        if marked.contains(question.id) {
            marked.remove(question.id)
        } else {
            marked.insert(question.id)
        }
    }

    func state(of question: Question) -> AnswerState {
        question.state(of: responses[question.id])
    }

    var unansweredCount: Int {
        questions.filter { state(of: $0) != .answered }.count
    }

    /// "Transfer Display": copies the calculator display into a numeric entry box.
    var canTransferDisplay: Bool {
        phase == .question && currentQuestion?.format == .numeric && calculator.displayValue != nil
    }

    func transferDisplay() {
        guard canTransferDisplay, let question = currentQuestion else { return }
        var response = response(for: question)
        response.numberText = calculator.display
        setResponse(response, for: question)
    }

    // MARK: Timer

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func tick() {
        guard phase != .finished else { return }
        let now = Date()
        // Cap at the deadline so sleep or App Nap can't inflate recorded time.
        let elapsed = max(0, min(now, deadline).timeIntervalSince(lastTick))
        lastTick = now
        secondsUsed += elapsed
        if phase == .question, let question = currentQuestion {
            timeSpent[question.id, default: 0] += elapsed
        }
        remainingSeconds = max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
        if remainingSeconds == 0 { finish() }
    }
}
