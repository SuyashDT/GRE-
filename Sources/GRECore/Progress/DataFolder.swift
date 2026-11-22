import Foundation

/// Where the app keeps its files: `progress.json` and the coach's `Coach` folder.
public enum DataFolder {
    /// Set this environment variable to keep a development or test run away from the real data.
    public static let environmentKey = "GREPREP_DATA_DIR"

    /// `~/Library/Application Support/GRE Prep` on macOS, unless `GREPREP_DATA_DIR` names another folder.
    public static func url(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment[environmentKey]?.trimmingCharacters(in: .whitespaces), !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("GRE Prep", isDirectory: true)
    }

    /// True when `GREPREP_DATA_DIR` is in use.
    public static func isOverridden(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        !(environment[environmentKey]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }
}
