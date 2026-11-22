import Foundation

/// What a coach has put in the `Coach` folder, after checking it against the bundled content.
public struct CoachContent: Hashable, Sendable {
    /// The decoded `plan.json`: nil when there is none, or when it can't be read at all.
    public var planFile: CoachPlanFile?
    /// One line per problem found while reading `plan.json`.
    public var planProblems: [String]
    /// Passages and data sets of the accepted `drills-*.json` files.
    public var stimuli: [Stimulus]
    /// Drill sets of the accepted files, newest file name first.
    public var sets: [DrillSet]
    /// One line per `drills-*.json` file that was left out.
    public var drillProblems: [String]

    public init(planFile: CoachPlanFile? = nil, planProblems: [String] = [], stimuli: [Stimulus] = [],
                sets: [DrillSet] = [], drillProblems: [String] = []) {
        self.planFile = planFile
        self.planProblems = planProblems
        self.stimuli = stimuli
        self.sets = sets
        self.drillProblems = drillProblems
    }

    public static let empty = CoachContent()
}

/// The folder a coach writes into: `Coach` inside the data folder.
///
/// It can hold a study plan (`plan.json`) and extra drill sets (`drills-*.json`). The app
/// only ever reads it. A file that can't be used is left out and reported in one line;
/// nothing in this folder can stop the bundled content from loading.
public struct CoachFolder: Sendable {
    public static let planFileName = "plan.json"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Coach` in the data folder (see `DataFolder`).
    public static func standard() -> CoachFolder {
        CoachFolder(url: DataFolder.url().appendingPathComponent("Coach", isDirectory: true))
    }

    /// Names of the drill files, oldest name first.
    private func drillFileNames() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { $0.hasPrefix("drills-") && $0.hasSuffix(".json") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Changes whenever a file the app reads is added, removed or rewritten.
    public func signature() -> String {
        let fileManager = FileManager.default
        var names = drillFileNames()
        if fileManager.fileExists(atPath: url.appendingPathComponent(Self.planFileName).path) {
            names.insert(Self.planFileName, at: 0)
        }
        return names.map { name -> String in
            let attributes = try? fileManager.attributesOfItem(atPath: url.appendingPathComponent(name).path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(name)|\(size)|\(modified)"
        }.joined(separator: "\n")
    }

    /// Reads the folder. `bundled` is the app's own content, used to reject ids that are already taken.
    public func load(bundled: ContentLibrary) -> CoachContent {
        var content = CoachContent()
        loadPlan(into: &content)
        loadDrills(into: &content, bundled: bundled)
        return content
    }

    // MARK: Plan

    private func loadPlan(into content: inout CoachContent) {
        let file = url.appendingPathComponent(Self.planFileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let plan = try JSONDecoder().decode(CoachPlanFile.self, from: Data(contentsOf: file))
            content.planFile = plan
            content.planProblems = plan.skipped.map { "\(Self.planFileName): \($0)" }
        } catch {
            content.planProblems = ["\(Self.planFileName) couldn't be read: \(Self.describe(error))"]
        }
    }

    // MARK: Drill sets

    /// A drills file as a coach writes it: like a bundled one, but `stimuli` may be left out.
    private struct DrillFile: Decodable {
        let stimuli: [Stimulus]?
        let sets: [DrillSet]
    }

    private func loadDrills(into content: inout CoachContent, bundled: ContentLibrary) {
        var takenSets = Set(bundled.bundledDrillSets.map(\.id))
        var takenQuestions = Set(bundled.mockTests.flatMap(\.allQuestions).map(\.id))
        takenQuestions.formUnion(bundled.bundledDrillSets.flatMap(\.questions).map(\.id))
        var takenStimuli = Set(bundled.mockTests.flatMap(\.stimuli).map(\.id))
        takenStimuli.formUnion(bundled.drills.stimuli.map(\.id).filter { !bundled.coachStimulusIds.contains($0) })

        // Oldest file first, so that when two coach files clash the one that was there first wins.
        var accepted: [(stimuli: [Stimulus], sets: [DrillSet])] = []
        for name in drillFileNames() {
            let file: DrillFile
            do {
                file = try JSONDecoder().decode(DrillFile.self, from: Data(contentsOf: url.appendingPathComponent(name)))
            } catch {
                content.drillProblems.append("\(name) was left out: \(Self.describe(error))")
                continue
            }
            let stimuli = file.stimuli ?? []
            let problems = Self.problems(sets: file.sets, stimuli: stimuli, takenSets: takenSets,
                                         takenQuestions: takenQuestions, takenStimuli: takenStimuli)
            if let first = problems.first {
                let more = problems.count > 1 ? " (and \(problems.count - 1) more)" : ""
                content.drillProblems.append("\(name) was left out: \(first)\(more)")
                continue
            }
            takenSets.formUnion(file.sets.map(\.id))
            takenQuestions.formUnion(file.sets.flatMap(\.questions).map(\.id))
            takenStimuli.formUnion(stimuli.map(\.id))
            accepted.append((stimuli, file.sets))
        }
        // Newest file first for display.
        for file in accepted.reversed() {
            content.stimuli += file.stimuli
            content.sets += file.sets
        }
    }

    /// Why a drills file can't be used, or an empty list when it can.
    static func problems(sets: [DrillSet], stimuli: [Stimulus], takenSets: Set<String>,
                         takenQuestions: Set<String>, takenStimuli: Set<String>) -> [String] {
        var problems: [String] = []
        if sets.isEmpty { problems.append("it has no sets") }

        var stimulusIds = Set<String>()
        for stimulus in stimuli {
            if takenStimuli.contains(stimulus.id) {
                problems.append("stimulus id \"\(stimulus.id)\" is already used")
            } else if !stimulusIds.insert(stimulus.id).inserted {
                problems.append("stimulus id \"\(stimulus.id)\" appears twice")
            }
        }

        var setIds = Set<String>()
        var questionIds = Set<String>()
        for set in sets {
            if set.id.isEmpty {
                problems.append("a set has no id")
            } else if takenSets.contains(set.id) {
                problems.append("set id \"\(set.id)\" is already used")
            } else if !setIds.insert(set.id).inserted {
                problems.append("set id \"\(set.id)\" appears twice")
            }
            if set.questions.isEmpty { problems.append("set \"\(set.id)\" has no questions") }
            if let limit = set.timeLimitMinutes, limit <= 0 {
                problems.append("set \"\(set.id)\" has a time limit of \(limit) minutes")
            }
            for question in set.questions {
                if takenQuestions.contains(question.id) {
                    problems.append("question id \"\(question.id)\" is already used")
                } else if !questionIds.insert(question.id).inserted {
                    problems.append("question id \"\(question.id)\" appears twice")
                }
                if question.category.measure != set.measure {
                    problems.append("question \"\(question.id)\" is not a \(set.measure.shortTitle) question")
                }
                if let category = set.category, question.category != category {
                    problems.append("question \"\(question.id)\" is not \(category.title), the set's question type")
                }
                if let id = question.stimulusId, !stimulusIds.contains(id) {
                    problems.append("question \"\(question.id)\" needs stimulus \"\(id)\", which isn't in the file")
                }
            }
        }
        return problems
    }

    // MARK: Errors

    /// A short reason for a decoding or file error, e.g. `missing "id" at sets[0].questions[2]`.
    /// `droppingPath` leaves out that many leading path steps, for errors inside a list item.
    static func describe(_ error: Error, droppingPath: Int = 0) -> String {
        guard let decoding = error as? DecodingError else {
            return (error as NSError).localizedDescription
        }
        func place(_ context: DecodingError.Context) -> String {
            var text = ""
            for step in context.codingPath.dropFirst(droppingPath) {
                if let index = step.intValue {
                    text += "[\(index)]"
                } else {
                    text += (text.isEmpty ? "" : ".") + step.stringValue
                }
            }
            return text
        }
        switch decoding {
        case let .keyNotFound(key, context):
            let location = place(context)
            return "missing \"\(key.stringValue)\"" + (location.isEmpty ? "" : " at \(location)")
        case let .typeMismatch(_, context), let .valueNotFound(_, context):
            let location = place(context)
            return "wrong kind of value" + (location.isEmpty ? "" : " at \(location)")
        case let .dataCorrupted(context):
            let location = place(context)
            return location.isEmpty ? "it isn't valid JSON" : "bad value at \(location)"
        @unknown default:
            return "it couldn't be decoded"
        }
    }
}
