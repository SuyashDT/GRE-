import Foundation
import Observation
import GRECore

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case studyPlan
    case mockTests
    case drills
    case vocabulary
    case lessons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .studyPlan: return "Study Plan"
        case .mockTests: return "Mock Tests"
        case .drills: return "Practice Drills"
        case .vocabulary: return "Vocabulary"
        case .lessons: return "Strategy Lessons"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .studyPlan: return "calendar"
        case .mockTests: return "doc.text.magnifyingglass"
        case .drills: return "target"
        case .vocabulary: return "character.book.closed"
        case .lessons: return "lightbulb"
        }
    }
}

/// App-wide state: content, saved progress, settings and the running exam.
@MainActor
@Observable
final class AppModel {
    /// The bundled content plus any drill sets the coach has put in the Coach folder.
    private(set) var content: ContentLibrary?
    private(set) var loadError: String?
    private(set) var progress = ProgressData()
    /// The plan the app shows: the coach's (`Coach/plan.json`) when there is one, else the generated one.
    private(set) var studyPlan: StudyPlan?
    /// One line per problem with the coach's plan, shown on the Study Plan screen.
    private(set) var coachPlanProblems: [String] = []
    /// One line per coach drills file that was left out, shown on the Practice Drills screen.
    private(set) var coachDrillProblems: [String] = []
    var saveError: String?

    var selection: SidebarItem? = .dashboard
    var mockPath: [UUID] = []
    var drillPath: [String] = []
    var lessonPath: [String] = []

    /// The mock test in progress; while set, the window shows only the exam.
    private(set) var exam: ExamSession?
    /// The timed drill set in progress; while set, the window shows only that set.
    private(set) var timedDrill: TimedDrillSession?

    // MARK: Settings

    var claudeCustomPath: String {
        didSet {
            defaults.set(claudeCustomPath, forKey: Keys.claudePath)
            claudeLocation = nil
            claudeStatus = nil
        }
    }
    var gradingModel: ClaudeCodeGrader.Model {
        didSet { defaults.set(gradingModel.rawValue, forKey: Keys.gradingModel) }
    }
    var autoGradeEssays: Bool {
        didSet { defaults.set(autoGradeEssays, forKey: Keys.autoGrade) }
    }

    private(set) var claudeLocation: ClaudeCodeLocator.Location?
    private(set) var claudeStatus: ClaudeCodeGrader.InstallationStatus?
    private(set) var isCheckingClaude = false
    private(set) var gradingInProgress: Set<UUID> = []
    private(set) var gradingErrors: [UUID: String] = [:]

    @ObservationIgnored private let store = ProgressStore.defaultStore()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var started = false
    @ObservationIgnored private let coachFolder = CoachFolder.standard()
    @ObservationIgnored private var bundledContent: ContentLibrary?
    @ObservationIgnored private var coachContent = CoachContent.empty
    @ObservationIgnored private var coachSignature: String?

    private enum Keys {
        static let claudePath = "claudeCodePath"
        static let gradingModel = "gradingModel"
        static let autoGrade = "autoGradeEssays"
    }

    init() {
        let stored = UserDefaults.standard
        claudeCustomPath = stored.string(forKey: Keys.claudePath) ?? ""
        gradingModel = stored.string(forKey: Keys.gradingModel).flatMap(ClaudeCodeGrader.Model.init(rawValue:)) ?? .opus
        autoGradeEssays = stored.object(forKey: Keys.autoGrade) as? Bool ?? true
    }

    func start() async {
        guard !started else { return }
        started = true
        do {
            let bundled = try ContentLibrary.loadBundled()
            bundledContent = bundled
            content = bundled
        } catch {
            loadError = error.localizedDescription
        }
        do {
            progress = try store.load()
        } catch {
            let backup = store.quarantineCorruptFile()
            saveError = "Your saved progress couldn't be read, so a fresh file was started."
                + (backup.map { " The old file was kept at \($0.path)." } ?? "")
        }
        reloadCoach(force: true)
        UITestOptions.current.apply(to: self)
    }

    // MARK: Coach folder

    /// Reads the Coach folder again if anything in it changed. Called at launch and whenever the app
    /// becomes active, so a plan or set the coach wrote while the app was open shows up without a relaunch.
    /// A running test or timed set is left alone; the folder is read once it ends.
    func reloadCoach(force: Bool = false) {
        guard let bundledContent, exam == nil, timedDrill == nil else { return }
        let signature = coachFolder.signature()
        guard force || signature != coachSignature else { return }
        coachSignature = signature
        coachContent = coachFolder.load(bundled: bundledContent)
        content = bundledContent.adding(coachContent)
        coachDrillProblems = coachContent.drillProblems
        rebuildPlan()
    }

    /// Where the coach's files go, for the Settings screen.
    var coachFolderPath: String { coachFolder.url.path }

    // MARK: Progress

    private func persist() {
        do {
            try store.save(progress)
            saveError = nil
        } catch {
            saveError = "Couldn't save progress: \(error.localizedDescription)"
        }
    }

    private func markStudiedToday() {
        progress.studyDays.insert(StudyCalendar.dayKey(Date()))
    }

    var analytics: Analytics { Analytics(progress: progress) }

    var streak: Int { StudyCalendar.streak(days: progress.studyDays) }

    func attempt(id: UUID) -> MockAttempt? {
        progress.mockAttempts.first { $0.id == id }
    }

    func attempts(forTest testId: String) -> [MockAttempt] {
        progress.mockAttempts.filter { $0.testId == testId }.sorted { $0.finishedAt > $1.finishedAt }
    }

    func deleteAttempt(_ id: UUID) {
        progress.mockAttempts.removeAll { $0.id == id }
        mockPath.removeAll { $0 == id }
        persist()
    }

    func recordDrill(_ attempt: DrillAttempt) {
        guard !attempt.results.isEmpty else { return }
        progress.drillAttempts.append(attempt)
        markStudiedToday()
        persist()
    }

    func drillAttempts(setId: String) -> [DrillAttempt] {
        progress.drillAttempts.filter { $0.setId == setId }
    }

    /// The questions of one measure whose latest answer was wrong, as a set to redo. Nil when there are none.
    func missedSet(for measure: Measure) -> DrillSet? {
        content.flatMap { MissedQuestions.set(for: measure, progress: progress, content: $0) }
    }

    func markLessonRead(_ id: String) {
        guard !progress.lessonsRead.contains(id) else { return }
        progress.lessonsRead.insert(id)
        markStudiedToday()
        persist()
    }

    // MARK: Vocabulary

    var newCardsPerDay: Int {
        get { progress.newCardsPerDay }
        set {
            progress.newCardsPerDay = max(1, min(100, newValue))
            rebuildPlan()
            persist()
        }
    }

    func studyQueue(now: Date = Date()) -> [VocabWord] {
        SpacedRepetition.queue(words: content?.vocabulary ?? [], cards: progress.cards,
                               newPerDay: progress.newCardsPerDay, now: now)
    }

    func review(_ word: VocabWord, rating: ReviewRating) {
        progress.cards[word.id] = SpacedRepetition.review(progress.cards[word.id], wordId: word.id, rating: rating)
        markStudiedToday()
        persist()
    }

    func cardState(_ word: VocabWord) -> CardState? {
        progress.cards[word.id]
    }

    func resetProgress() {
        progress = ProgressData()
        mockPath = []
        rebuildPlan()
        persist()
    }

    // MARK: Study plan

    /// Builds (or rebuilds) the plan starting today.
    func setStudyPlan(examDate: Date, minutesPerDay: Int, restWeekday: Int?) {
        progress.studyPlan = StudyPlanSettings(
            examDate: examDate, startDate: Date(), minutesPerDay: minutesPerDay, restWeekday: restWeekday
        )
        rebuildPlan()
        persist()
    }

    /// Deletes the generated plan and its ticks. Ticks on a coach's plan are kept.
    func deleteStudyPlan() {
        if let generated = generatedPlan() {
            progress.planChecked.subtract(generated.days.flatMap(\.tasks).map(\.id))
        }
        progress.studyPlan = nil
        rebuildPlan()
        persist()
    }

    /// The app's own plan. It is built from the bundled content only, so that a coach
    /// adding or removing a drill set never reshuffles it.
    private func generatedPlan() -> StudyPlan? {
        guard let settings = progress.studyPlan, let bundledContent else { return nil }
        return StudyPlan.make(settings: settings, content: bundledContent, newCardsPerDay: progress.newCardsPerDay)
    }

    private func rebuildPlan() {
        var problems = coachContent.planProblems
        defer { coachPlanProblems = problems }
        if let file = coachContent.planFile, let content {
            let resolved = CoachPlan.resolve(file, content: content, newCardsPerDay: progress.newCardsPerDay)
            problems += resolved.problems
            if let plan = resolved.plan {
                studyPlan = plan
                return
            }
        }
        studyPlan = generatedPlan()
    }

    /// The later day a coach's plan saves this mock test for, if starting it now would be early.
    func plannedLaterDay(forMockTest id: String, now: Date = Date()) -> Date? {
        CoachPlan.upcomingDay(forMockTest: id, in: studyPlan, now: now)
    }

    func isDone(_ task: PlanTask, on day: PlanDay) -> Bool {
        StudyPlan.isDone(task, on: day.date, progress: progress)
    }

    func isCompletedInApp(_ task: PlanTask, on day: PlanDay) -> Bool {
        StudyPlan.isCompletedInApp(task, on: day.date, progress: progress)
    }

    func togglePlanTask(_ task: PlanTask) {
        if progress.planChecked.contains(task.id) {
            progress.planChecked.remove(task.id)
        } else {
            progress.planChecked.insert(task.id)
            markStudiedToday()
        }
        persist()
    }

    /// Tasks still open today, for the sidebar badge.
    func openPlanTaskCount(now: Date = Date()) -> Int {
        guard let day = studyPlan?.day(for: now) else { return 0 }
        return day.tasks.filter { $0.kind != .rest && $0.kind != .examDay && !isDone($0, on: day) }.count
    }

    /// The drill to practise for a weak-spot task: the weakest question type so far (with its stats),
    /// or the plan's pick until enough questions have been answered.
    func weakSpotDrill(fallback: String) -> (set: DrillSet, weakest: CategoryStat?)? {
        if let weakest = analytics.weakestCategories(limit: 1).first,
           let set = content?.bundledDrillSets.first(where: { $0.category == weakest.category }) {
            return (set, weakest)
        }
        return content?.drillSet(id: fallback).map { ($0, nil) }
    }

    /// Whether a task has a place in the app to go to.
    func canOpen(_ task: PlanTask) -> Bool {
        switch task.kind {
        case .note, .rest, .examDay: return false
        case .reviewMock: return !progress.mockAttempts.isEmpty
        default: return true
        }
    }

    func open(_ task: PlanTask) {
        switch task.kind {
        case let .lesson(id):
            selection = .lessons
            lessonPath = [id]
        case let .drill(id):
            selection = .drills
            drillPath = [id]
        case let .weakSpot(fallback):
            selection = .drills
            drillPath = weakSpotDrill(fallback: fallback).map { [$0.set.id] } ?? []
        case .vocabulary:
            selection = .vocabulary
        case .mockTest:
            selection = .mockTests
            mockPath = []
        case .reviewMock:
            selection = .mockTests
            mockPath = progress.mockAttempts.max { $0.finishedAt < $1.finishedAt }.map { [$0.id] } ?? []
        case .essayOutline:
            selection = .lessons
            lessonPath = ["awa-issue"]
        case .lightReview:
            selection = .lessons
            lessonPath = ["pacing"]
        case .note, .rest, .examDay:
            break
        }
    }

    // MARK: Mock tests

    func startExam(_ test: MockTest) {
        let session = ExamSession(test: test)
        session.onFinish = { [weak self] attempt in
            self?.finishExam(attempt)
        }
        exam = session
    }

    func quitExam() {
        exam?.stop()
        exam = nil
        reloadCoach()
    }

    private func finishExam(_ attempt: MockAttempt) {
        progress.mockAttempts.append(attempt)
        markStudiedToday()
        persist()
        exam = nil
        selection = .mockTests
        mockPath = [attempt.id]
        reloadCoach()
        if autoGradeEssays, let essay = attempt.essay, !essay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task { await gradeEssay(attemptId: attempt.id) }
        }
    }

    // MARK: Timed drill sets

    /// Starts a timed set. The clock starts at once and the window shows only the set until it ends.
    func startTimedDrill(_ drill: DrillSet) {
        guard drill.isTimed, exam == nil, timedDrill == nil else { return }
        let session = TimedDrillSession(drill: drill, stimuli: content?.drills.stimuli ?? [])
        session.onFinish = { [weak self] attempt in
            self?.finishTimedDrill(attempt)
        }
        timedDrill = session
        session.begin()
    }

    /// Stops the set without recording anything.
    func quitTimedDrill() {
        timedDrill?.stop()
        timedDrill = nil
        reloadCoach()
    }

    private func finishTimedDrill(_ attempt: DrillAttempt) {
        recordDrill(attempt)
        timedDrill = nil
        selection = .drills
        drillPath = [attempt.setId]
        reloadCoach()
    }

    func setSelfScore(_ score: Double?, attemptId: UUID) {
        guard let index = progress.mockAttempts.firstIndex(where: { $0.id == attemptId }) else { return }
        progress.mockAttempts[index].essay?.selfScore = score
        persist()
    }

    // MARK: Claude Code

    /// Finds `claude` (off the main thread: it may ask the login shell).
    func locateClaude() async -> ClaudeCodeLocator.Location? {
        if let claudeLocation { return claudeLocation }
        let custom = claudeCustomPath
        let found = await Task.detached(priority: .userInitiated) {
            ClaudeCodeLocator.locate(customPath: custom.isEmpty ? nil : custom)
        }.value
        claudeLocation = found
        return found
    }

    func checkClaude() async {
        isCheckingClaude = true
        defer { isCheckingClaude = false }
        claudeLocation = nil
        guard let location = await locateClaude() else {
            claudeStatus = ClaudeCodeGrader.InstallationStatus(version: nil, loggedIn: nil, detail: "Claude Code wasn't found.")
            return
        }
        claudeStatus = await ClaudeCodeGrader.checkInstallation(executable: location.executable, environment: location.environment)
    }

    func gradeEssay(attemptId: UUID) async {
        guard !gradingInProgress.contains(attemptId),
              let attempt = attempt(id: attemptId), let essay = attempt.essay,
              let test = content?.mockTest(id: attempt.testId)
        else { return }
        gradingInProgress.insert(attemptId)
        gradingErrors[attemptId] = nil
        defer { gradingInProgress.remove(attemptId) }

        guard let location = await locateClaude() else {
            gradingErrors[attemptId] = EssayGradingError.claudeNotFound.localizedDescription
            return
        }
        let grader = ClaudeCodeGrader(executable: location.executable, model: gradingModel, environment: location.environment)
        do {
            let grade = try await grader.grade(task: test.essay, essay: essay.text, minutesUsed: essay.secondsUsed / 60)
            if let index = progress.mockAttempts.firstIndex(where: { $0.id == attemptId }) {
                progress.mockAttempts[index].essay?.grade = grade
                persist()
            }
        } catch is CancellationError {
            return
        } catch {
            gradingErrors[attemptId] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
