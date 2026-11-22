import Foundation

/// All study content, decoded from the JSON files in `Resources/Content`,
/// plus any drill sets a coach has put in the `Coach` folder (see `CoachFolder`).
public struct ContentLibrary: Sendable {
    public let mockTests: [MockTest]
    /// Bundled drill sets first, then the coach's.
    public let drills: DrillLibrary
    public let vocabulary: [VocabWord]
    public let lessons: [Lesson]
    /// Ids of the drill sets that came from the coach, newest file first.
    public let coachSetIds: [String]
    let coachStimulusIds: Set<String>

    public init(mockTests: [MockTest], drills: DrillLibrary, vocabulary: [VocabWord], lessons: [Lesson]) {
        self.init(mockTests: mockTests, drills: drills, vocabulary: vocabulary, lessons: lessons,
                  coachSetIds: [], coachStimulusIds: [])
    }

    init(mockTests: [MockTest], drills: DrillLibrary, vocabulary: [VocabWord], lessons: [Lesson],
         coachSetIds: [String], coachStimulusIds: Set<String>) {
        self.mockTests = mockTests
        self.drills = drills
        self.vocabulary = vocabulary
        self.lessons = lessons
        self.coachSetIds = coachSetIds
        self.coachStimulusIds = coachStimulusIds
    }

    public enum LoadError: Error, LocalizedError {
        case contentFolderMissing
        case file(String, Error)

        public var errorDescription: String? {
            switch self {
            case .contentFolderMissing:
                return "The app's study content couldn't be found."
            case let .file(name, error):
                return "Couldn't read \(name): \(error)"
            }
        }
    }

    /// Loads content from the app bundle (or the SwiftPM resource bundle when run from Xcode/`swift run`).
    public static func loadBundled() throws -> ContentLibrary {
        guard let folder = bundledContentFolder() else { throw LoadError.contentFolderMissing }
        return try load(from: folder)
    }

    public static func bundledContentFolder() -> URL? {
        func hasContent(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.appendingPathComponent("mock-test-1.json").path)
        }
        // A packaged .app built by scripts/build-app.sh copies the folder into Contents/Resources.
        // Check it first: touching `Bundle.module` traps when its resource bundle isn't present.
        if let resources = Bundle.main.resourceURL {
            let packaged = resources.appendingPathComponent("Content", isDirectory: true)
            if hasContent(packaged) { return packaged }
        }
        let module = (Bundle.module.resourceURL ?? Bundle.module.bundleURL)
            .appendingPathComponent("Content", isDirectory: true)
        return hasContent(module) ? module : nil
    }

    public static func load(from folder: URL) throws -> ContentLibrary {
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        let decoder = JSONDecoder()

        func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
            do {
                let data = try Data(contentsOf: folder.appendingPathComponent(name))
                return try decoder.decode(type, from: data)
            } catch {
                throw LoadError.file(name, error)
            }
        }

        let mockTests = try files.filter { $0.hasPrefix("mock-test-") && $0.hasSuffix(".json") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { try decode(MockTest.self, $0) }

        var stimuli: [Stimulus] = []
        var sets: [DrillSet] = []
        for name in files.filter({ $0.hasPrefix("drills-") && $0.hasSuffix(".json") }).sorted() {
            let library = try decode(DrillLibrary.self, name)
            stimuli += library.stimuli
            sets += library.sets
        }
        // Verbal drills first, then quant, each in category order.
        let categoryOrder = Dictionary(uniqueKeysWithValues: QuestionCategory.allCases.enumerated().map { ($1, $0) })
        let order: (DrillSet) -> Int = { set in set.category.flatMap { categoryOrder[$0] } ?? Int.max }
        sets.sort { order($0) < order($1) }

        let vocabulary = files.contains("vocabulary.json") ? try decode(VocabularyList.self, "vocabulary.json").words : []
        let lessons = files.contains("lessons.json") ? try decode(LessonList.self, "lessons.json").lessons : []

        return ContentLibrary(
            mockTests: mockTests,
            drills: DrillLibrary(stimuli: stimuli, sets: sets),
            vocabulary: vocabulary,
            lessons: lessons
        )
    }

    public func drillSet(id: String) -> DrillSet? {
        drills.sets.first { $0.id == id }
    }

    public func drillStimulus(_ id: String?) -> Stimulus? {
        guard let id else { return nil }
        return drills.stimuli.first { $0.id == id }
    }

    /// The passage or data set a question uses, looked up where the question lives
    /// (its mock test, or the drill stimuli).
    public func stimulus(for question: Question) -> Stimulus? {
        guard let id = question.stimulusId else { return nil }
        for test in mockTests where test.allQuestions.contains(where: { $0.id == question.id }) {
            return test.stimulus(id)
        }
        return drillStimulus(id)
    }

    // MARK: Coach sets

    /// The same library with the coach's accepted drill sets added after the bundled ones.
    /// Sets from an earlier call are replaced, so it is safe to call again after a reload.
    public func adding(_ coach: CoachContent) -> ContentLibrary {
        ContentLibrary(
            mockTests: mockTests,
            drills: DrillLibrary(
                stimuli: drills.stimuli.filter { !coachStimulusIds.contains($0.id) } + coach.stimuli,
                sets: bundledDrillSets + coach.sets
            ),
            vocabulary: vocabulary,
            lessons: lessons,
            coachSetIds: coach.sets.map(\.id),
            coachStimulusIds: Set(coach.stimuli.map(\.id))
        )
    }

    /// Drill sets that ship with the app.
    public var bundledDrillSets: [DrillSet] {
        coachSetIds.isEmpty ? drills.sets : drills.sets.filter { !coachSetIds.contains($0.id) }
    }

    /// Drill sets from the coach, newest file first.
    public var coachDrillSets: [DrillSet] {
        coachSetIds.compactMap { id in drills.sets.first { $0.id == id } }
    }

    public func isCoachSet(_ id: String) -> Bool { coachSetIds.contains(id) }

    public func mockTest(id: String) -> MockTest? {
        mockTests.first { $0.id == id }
    }

    public func lessons(for category: QuestionCategory) -> [Lesson] {
        lessons.filter { $0.category == category }
    }

    public func lesson(id: String) -> Lesson? {
        lessons.first { $0.id == id }
    }

    /// Looks up a question anywhere in the content (mock tests and drills).
    public func question(id: String) -> Question? {
        for test in mockTests {
            if let question = test.allQuestions.first(where: { $0.id == id }) { return question }
        }
        for set in drills.sets {
            if let question = set.questions.first(where: { $0.id == id }) { return question }
        }
        return nil
    }
}
