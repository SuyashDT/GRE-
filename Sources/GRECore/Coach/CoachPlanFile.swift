import Foundation

/// `Coach/plan.json` as the coach wrote it. See docs/COACH.md for the format.
///
/// Decoding is forgiving: a day or task that can't be decoded is left out and noted in
/// `skipped`, so one typo doesn't take the whole plan away.
public struct CoachPlanFile: Decodable, Hashable, Sendable {
    public struct Task: Decodable, Hashable, Sendable {
        public var id: String
        /// `lesson`, `drill`, `mockTest`, `vocabulary`, `note`, `rest` or `exam`.
        public var kind: String
        /// The lesson, drill set or mock test the task points to.
        public var ref: String?
        public var title: String?
        public var detail: String?
        public var minutes: Int?
        /// For a note: keep it in the catch-up list until it is ticked.
        public var carryOver: Bool?

        public init(id: String, kind: String, ref: String? = nil, title: String? = nil, detail: String? = nil,
                    minutes: Int? = nil, carryOver: Bool? = nil) {
            self.id = id
            self.kind = kind
            self.ref = ref
            self.title = title
            self.detail = detail
            self.minutes = minutes
            self.carryOver = carryOver
        }
    }

    public struct Day: Decodable, Hashable, Sendable {
        /// A local calendar day, `yyyy-MM-dd`.
        public var date: String
        public var focus: String?
        public var tasks: [Task]
        var skipped: [String]

        public init(date: String, focus: String? = nil, tasks: [Task]) {
            self.date = date
            self.focus = focus
            self.tasks = tasks
            self.skipped = []
        }

        enum CodingKeys: String, CodingKey { case date, focus, tasks }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let day = try container.decode(String.self, forKey: .date)
            date = day
            focus = try? container.decodeIfPresent(String.self, forKey: .focus)
            let lossy = try container.decodeIfPresent(LossyArray<Task>.self, forKey: .tasks)
            tasks = lossy?.elements ?? []
            skipped = (lossy?.failures ?? []).map { "\(day), task \($0.index + 1): \($0.reason)" }
        }
    }

    public var version: Int?
    public var title: String?
    /// The test date, `yyyy-MM-dd`.
    public var examDate: String?
    /// When the coach last changed the plan, `yyyy-MM-dd`.
    public var updated: String?
    /// One line from the coach, shown at the top of the plan.
    public var note: String?
    public var days: [Day]
    /// Days and tasks that couldn't be decoded and were left out, one line each.
    public var skipped: [String]

    public init(version: Int? = 1, title: String? = nil, examDate: String? = nil, updated: String? = nil,
                note: String? = nil, days: [Day]) {
        self.version = version
        self.title = title
        self.examDate = examDate
        self.updated = updated
        self.note = note
        self.days = days
        self.skipped = []
    }

    enum CodingKeys: String, CodingKey { case version, title, examDate, updated, note, days }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try? container.decodeIfPresent(Int.self, forKey: .version)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        examDate = try? container.decodeIfPresent(String.self, forKey: .examDate)
        updated = try? container.decodeIfPresent(String.self, forKey: .updated)
        note = try? container.decodeIfPresent(String.self, forKey: .note)
        let lossy = try container.decode(LossyArray<Day>.self, forKey: .days)
        days = lossy.elements
        skipped = lossy.failures.map { "day \($0.index + 1): \($0.reason)" } + lossy.elements.flatMap(\.skipped)
    }
}

/// Decodes an array one element at a time, keeping the good elements and noting why the others failed.
struct LossyArray<Element: Decodable>: Decodable {
    struct Failure {
        let index: Int
        let reason: String
    }

    var elements: [Element] = []
    var failures: [Failure] = []

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var index = 0
        while !container.isAtEnd {
            let position = container.currentIndex
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                failures.append(Failure(index: index, reason: CoachFolder.describe(error, droppingPath: container.codingPath.count + 1)))
                // A failed decode doesn't move the container on; step over the bad element.
                _ = try? container.decode(AnyJSONValue.self)
            }
            if container.currentIndex == position {
                // It can't be stepped over either: stop here rather than loop forever.
                failures.append(Failure(index: index, reason: "the rest of the list couldn't be read"))
                break
            }
            index += 1
        }
    }
}

/// Accepts any JSON value, to step over one that couldn't be decoded.
private struct AnyJSONValue: Decodable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: Key.self) {
            for key in keyed.allKeys { _ = try? keyed.decode(AnyJSONValue.self, forKey: key) }
        } else if var unkeyed = try? decoder.unkeyedContainer() {
            while !unkeyed.isAtEnd {
                guard (try? unkeyed.decode(AnyJSONValue.self)) != nil else { break }
            }
        } else {
            _ = try decoder.singleValueContainer()
        }
    }
}
