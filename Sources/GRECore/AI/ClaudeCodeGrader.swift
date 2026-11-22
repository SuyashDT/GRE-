import Foundation
#if canImport(Glibc)
import Glibc
#endif

/// Grades essays by running the locally installed Claude Code CLI (`claude -p`),
/// which uses the person's own Claude Code login. No API key is stored by the app.
public struct ClaudeCodeGrader: Sendable {
    public enum Model: String, CaseIterable, Codable, Sendable, Identifiable {
        /// Claude Code's alias for the latest Opus model.
        case opus
        /// Claude Code's alias for the latest Sonnet model (faster, uses less of your plan).
        case sonnet
        /// Whatever model Claude Code is configured to use.
        case `default`

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .opus: return "Opus (most thorough)"
            case .sonnet: return "Sonnet (faster)"
            case .default: return "Claude Code default"
            }
        }
    }

    public let executable: URL
    public let model: Model
    public let environment: [String: String]
    public let timeout: TimeInterval

    public init(executable: URL, model: Model = .opus, environment: [String: String], timeout: TimeInterval = 300) {
        self.executable = executable
        self.model = model
        self.environment = environment
        self.timeout = timeout
    }

    public func grade(task: EssayTask, essay: String, minutesUsed: Double?) async throws -> EssayGrade {
        let input = Data(EssayGradingPrompt.input(task: task, essay: essay, minutesUsed: minutesUsed).utf8)
        // Run in an empty folder so no project CLAUDE.md, hooks or MCP config get picked up.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gre-prep-grading-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        var result = try await ProcessRunner.run(
            executable: executable, arguments: arguments(minimal: false), stdin: input,
            workingDirectory: workDir, environment: environment, timeout: timeout
        )
        // Older Claude Code versions may not know the newer isolation flags; retry with the basics.
        let stderrText = String(decoding: result.stderr, as: UTF8.self).lowercased()
        if result.exitCode != 0, stderrText.contains("unknown option") || stderrText.contains("unknown argument") {
            result = try await ProcessRunner.run(
                executable: executable, arguments: arguments(minimal: true), stdin: input,
                workingDirectory: workDir, environment: environment, timeout: timeout
            )
        }
        if result.timedOut { throw EssayGradingError.timedOut }

        let parsed = try ClaudeCodeOutput.parse(stdout: result.stdout, stderr: result.stderr, exitCode: result.exitCode)
        var grade = parsed.grade
        grade.model = model == .default ? "Claude (Claude Code default)" : "Claude \(model.rawValue.capitalized)"
        grade.gradedAt = Date()
        grade.costUSD = parsed.costUSD
        return grade
    }

    func arguments(minimal: Bool) -> [String] {
        var arguments = ["-p", EssayGradingPrompt.instruction, "--output-format", "json"]
        if model != .default { arguments += ["--model", model.rawValue] }
        arguments += ["--system-prompt", EssayGradingPrompt.systemPrompt]
        if !minimal {
            arguments += [
                "--json-schema", EssayGradingPrompt.jsonSchema,
                "--tools", "",
                "--safe-mode",
                "--no-session-persistence",
            ]
        }
        return arguments
    }

    /// Runs `claude --version` and `claude auth status` for the Settings screen.
    public static func checkInstallation(executable: URL, environment: [String: String]) async -> InstallationStatus {
        let workDir = FileManager.default.temporaryDirectory
        guard let version = try? await ProcessRunner.run(
            executable: executable, arguments: ["--version"], stdin: Data(),
            workingDirectory: workDir, environment: environment, timeout: 20
        ), version.exitCode == 0 else {
            return InstallationStatus(version: nil, loggedIn: nil, detail: "Couldn't run \(executable.path).")
        }
        let versionText = String(decoding: version.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let auth = try? await ProcessRunner.run(
            executable: executable, arguments: ["auth", "status", "--text"], stdin: Data(),
            workingDirectory: workDir, environment: environment, timeout: 20
        )
        let authText = auth.map { String(decoding: $0.stdout + $0.stderr, as: UTF8.self) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return InstallationStatus(
            version: versionText,
            loggedIn: auth.map { $0.exitCode == 0 },
            detail: authText
        )
    }

    public struct InstallationStatus: Sendable, Equatable {
        public let version: String?
        /// nil when the status couldn't be determined.
        public let loggedIn: Bool?
        public let detail: String

        public init(version: String?, loggedIn: Bool?, detail: String) {
            self.version = version
            self.loggedIn = loggedIn
            self.detail = detail
        }
    }
}

/// Finds the `claude` binary. Apps launched from Finder don't inherit the shell's PATH,
/// so this checks the usual install locations and then asks the login shell.
public enum ClaudeCodeLocator {
    public struct Location: Sendable, Equatable {
        public let executable: URL
        /// Environment to launch it with (PATH extended so npm installs can find `node`).
        public let environment: [String: String]
    }

    public static func candidatePaths(home: String) -> [String] {
        [
            "\(home)/.local/bin/claude",          // native installer
            "/opt/homebrew/bin/claude",           // Homebrew (Apple silicon) / npm with Homebrew node
            "/usr/local/bin/claude",              // Homebrew (Intel) / npm default prefix
            "\(home)/.claude/local/claude",       // legacy local install
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.volta/bin/claude",
        ]
    }

    public static func locate(customPath: String? = nil, processEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> Location? {
        let fileManager = FileManager.default
        let home = processEnvironment["HOME"] ?? NSHomeDirectory()

        var found: String?
        if let customPath, !customPath.isEmpty {
            let expanded = (customPath as NSString).expandingTildeInPath
            guard fileManager.isExecutableFile(atPath: expanded) else { return nil }
            found = expanded
        }
        if found == nil {
            found = candidatePaths(home: home).first { fileManager.isExecutableFile(atPath: $0) }
        }
        // Always ask the login shell: npm installs of `claude` need the shell's PATH to find `node`.
        let lookup = loginShellLookup(environment: processEnvironment)
        if found == nil { found = lookup.claude }
        guard let found else { return nil }

        var pathEntries: [String] = [(found as NSString).deletingLastPathComponent]
        pathEntries += (lookup.path ?? "").split(separator: ":").map(String.init)
        pathEntries += (processEnvironment["PATH"] ?? "").split(separator: ":").map(String.init)
        pathEntries += ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        let path = pathEntries.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")

        var environment = processEnvironment
        environment.merge(lookup.environment) { _, fromShell in fromShell }
        environment["PATH"] = path
        environment["HOME"] = home
        return Location(executable: URL(fileURLWithPath: found), environment: environment)
    }

    /// Variables from the login shell that describe the shell itself rather than the user's setup.
    static let shellOnlyVariables: Set<String> = ["PWD", "OLDPWD", "SHLVL", "_", "PS1", "PS2", "PROMPT", "RPROMPT"]

    /// Asks the user's login shell for its PATH, the location of `claude` and its environment
    /// (proxy, certificate and Claude Code settings that a Finder-launched app wouldn't otherwise see).
    static func loginShellLookup(environment: [String: String]) -> (path: String?, claude: String?, environment: [String: String]) {
        let fileManager = FileManager.default
        let shell = environment["SHELL"].flatMap { fileManager.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        guard fileManager.isExecutableFile(atPath: shell) else { return (nil, nil, [:]) }

        // Write to a file rather than a pipe: a background process started by the user's
        // shell config could hold a pipe open and block reading forever.
        let outputURL = fileManager.temporaryDirectory.appendingPathComponent("gre-prep-shell-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL)
        else { return (nil, nil, [:]) }
        defer {
            try? output.close()
            try? fileManager.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "echo __GRE_PATH__=$PATH; echo __GRE_CLAUDE__=$(command -v claude); echo __GRE_ENV__; /usr/bin/env -0"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return (nil, nil, [:]) }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            // Interactive shells ignore SIGTERM.
            kill(process.processIdentifier, SIGKILL)
            return (nil, nil, [:])
        }
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return parseShellOutput(data, isExecutable: { fileManager.isExecutableFile(atPath: $0) })
    }

    static func parseShellOutput(_ data: Data, isExecutable: (String) -> Bool) -> (path: String?, claude: String?, environment: [String: String]) {
        let text = String(decoding: data, as: UTF8.self)
        var head = Substring(text)
        var variables: [String: String] = [:]
        if let marker = text.range(of: "__GRE_ENV__\n") {
            head = text[..<marker.lowerBound]
            for entry in text[marker.upperBound...].split(separator: "\0") {
                guard let equals = entry.firstIndex(of: "=") else { continue }
                let key = String(entry[..<equals])
                guard !key.isEmpty, !key.contains(where: { $0.isWhitespace }), !shellOnlyVariables.contains(key) else { continue }
                variables[key] = String(entry[entry.index(after: equals)...])
            }
        }
        var path: String?
        var claude: String?
        for line in head.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("__GRE_PATH__=") { path = String(line.dropFirst("__GRE_PATH__=".count)) }
            if line.hasPrefix("__GRE_CLAUDE__=") {
                let value = String(line.dropFirst("__GRE_CLAUDE__=".count)).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("/"), isExecutable(value) { claude = value }
            }
        }
        return (path, claude, variables)
    }
}

/// Runs a subprocess with stdin, captured output, a timeout and task cancellation.
public enum ProcessRunner {
    public struct Result: Sendable {
        public let exitCode: Int32
        public let stdout: Data
        public let stderr: Data
        public let timedOut: Bool
    }

    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var stdout = Data()
        var stderr = Data()
        var continuation: CheckedContinuation<Result, Error>?

        /// Resumes the waiting task exactly once.
        func finish(_ outcome: Swift.Result<Result, Error>) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: outcome)
        }
    }

    public static func run(
        executable: URL, arguments: [String], stdin: Data,
        workingDirectory: URL, environment: [String: String], timeout: TimeInterval
    ) async throws -> Result {
        // Writing to a child that already exited must not kill the app.
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        let box = Box()
        let group = DispatchGroup()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
                box.continuation = continuation
                process.terminationHandler = { finished in
                    // Wait for both readers to drain their pipes before reporting.
                    group.notify(queue: .global()) {
                        box.lock.lock()
                        let result = Result(exitCode: finished.terminationStatus, stdout: box.stdout,
                                            stderr: box.stderr, timedOut: false)
                        box.lock.unlock()
                        box.finish(.success(result))
                    }
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    box.finish(.failure(EssayGradingError.claudeNotFound))
                    return
                }

                group.enter()
                DispatchQueue.global().async {
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    box.lock.lock(); box.stdout = data; box.lock.unlock()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    box.lock.lock(); box.stderr = data; box.lock.unlock()
                    group.leave()
                }
                DispatchQueue.global().async {
                    let handle = inPipe.fileHandleForWriting
                    try? handle.write(contentsOf: stdin)
                    try? handle.close()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard process.isRunning else { return }
                    process.terminate()
                    // Don't wait for the pipes: a grandchild process may still hold them open.
                    box.finish(.success(Result(exitCode: -1, stdout: Data(), stderr: Data(), timedOut: true)))
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
            box.finish(.failure(CancellationError()))
        }
    }
}
