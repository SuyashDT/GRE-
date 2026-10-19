import Foundation

/// Reads and writes `ProgressData` as JSON on disk.
public struct ProgressStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/GRE Prep/progress.json` on macOS.
    public static func defaultStore() -> ProgressStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return ProgressStore(fileURL: base.appendingPathComponent("GRE Prep", isDirectory: true)
            .appendingPathComponent("progress.json"))
    }

    public func load() throws -> ProgressData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ProgressData() }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(ProgressData.self, from: data)
    }

    public func save(_ progress: ProgressData) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(progress)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Moves an unreadable file aside so a fresh one can be started without losing it.
    @discardableResult
    public func quarantineCorruptFile() -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return backup
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum StudyCalendar {
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Consecutive study days ending today (or yesterday, so a streak survives until the day ends).
    public static func streak(days: Set<String>, now: Date = Date(), calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: now)
        if !days.contains(dayKey(day, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  days.contains(dayKey(yesterday, calendar: calendar))
            else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(dayKey(day, calendar: calendar)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
