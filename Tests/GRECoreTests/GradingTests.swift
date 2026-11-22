import XCTest
@testable import GRECore

final class ClaudeCodeOutputTests: XCTestCase {
    let gradeJSON = """
    {"score": 4.3, "summary": "Clear position.", "criteria": [{"name": "Organization & Coherence", "score": 4.8, "comment": "Logical."}], \
    "strengths": ["Clear thesis"], "improvements": ["Add a counterargument"], "nextSteps": "Practice concessions."}
    """

    func testStructuredOutput() throws {
        let stdout = """
        {"type":"result","subtype":"success","is_error":false,"result":"","total_cost_usd":0.04,"structured_output":\(gradeJSON)}
        """
        let parsed = try ClaudeCodeOutput.parse(stdout: Data(stdout.utf8), stderr: Data(), exitCode: 0)
        XCTAssertEqual(parsed.grade.score, 4.5, "scores round to the nearest half point")
        XCTAssertEqual(parsed.grade.criteria.first?.score, 5.0)
        XCTAssertEqual(parsed.costUSD, 0.04)
    }

    func testResultTextWithCodeFence() throws {
        let result = "Here is the grade:\n```json\n\(gradeJSON)\n```"
        let envelope: [String: Any] = ["type": "result", "subtype": "success", "is_error": false, "result": result]
        let stdout = try JSONSerialization.data(withJSONObject: envelope)
        let parsed = try ClaudeCodeOutput.parse(stdout: stdout, stderr: Data(), exitCode: 0)
        XCTAssertEqual(parsed.grade.summary, "Clear position.")
    }

    func testLogLinesBeforeJSON() throws {
        let envelope = try JSONSerialization.data(withJSONObject: ["type": "result", "is_error": false, "result": gradeJSON] as [String: Any])
        let stdout = Data("warning: {weird \"braces\n".utf8) + envelope
        let parsed = try ClaudeCodeOutput.parse(stdout: stdout, stderr: Data(), exitCode: 0)
        XCTAssertEqual(parsed.grade.strengths, ["Clear thesis"])
    }

    func testNotLoggedIn() {
        let stdout = #"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}"#
        XCTAssertThrowsError(try ClaudeCodeOutput.parse(stdout: Data(stdout.utf8), stderr: Data(), exitCode: 1)) { error in
            guard case EssayGradingError.notLoggedIn = error else { return XCTFail("got \(error)") }
        }
    }

    func testCrashWithoutJSON() {
        XCTAssertThrowsError(try ClaudeCodeOutput.parse(stdout: Data(), stderr: Data("boom".utf8), exitCode: 2)) { error in
            XCTAssertEqual(error as? EssayGradingError, .failed("boom"))
        }
    }

    func testUnparseableResult() {
        let stdout = #"{"type":"result","is_error":false,"result":"I cannot grade this."}"#
        XCTAssertThrowsError(try ClaudeCodeOutput.parse(stdout: Data(stdout.utf8), stderr: Data(), exitCode: 0)) { error in
            guard case EssayGradingError.invalidOutput = error else { return XCTFail("got \(error)") }
        }
    }

    func testSchemaIsValidJSON() throws {
        let object = try JSONSerialization.jsonObject(with: Data(EssayGradingPrompt.jsonSchema.utf8)) as? [String: Any]
        XCTAssertEqual(object?["type"] as? String, "object")
        XCTAssertEqual((object?["required"] as? [String])?.count, 6)
    }

    func testPromptContainsEssayAndInstructions() {
        let task = EssayTask(id: "e", statement: "Cities should ban cars.", instructions: "Discuss.", minutes: 30)
        let input = EssayGradingPrompt.input(task: task, essay: "I agree because...", minutesUsed: 28)
        XCTAssertTrue(input.contains("Cities should ban cars."))
        XCTAssertTrue(input.contains("I agree because..."))
        XCTAssertTrue(input.contains("3 words, written in 28 of 30 minutes"))
        XCTAssertTrue(EssayGradingPrompt.systemPrompt.contains("6 — Outstanding"))
    }

    func testArguments() {
        let grader = ClaudeCodeGrader(executable: URL(fileURLWithPath: "/bin/true"), model: .opus, environment: [:])
        let full = grader.arguments(minimal: false)
        XCTAssertEqual(Array(full.prefix(2)), ["-p", EssayGradingPrompt.instruction])
        XCTAssertTrue(full.contains("--json-schema"))
        XCTAssertTrue(full.contains("--safe-mode"))
        XCTAssertEqual(full[full.firstIndex(of: "--model")! + 1], "opus")
        XCTAssertEqual(full[full.firstIndex(of: "--tools")! + 1], "")
        XCTAssertFalse(grader.arguments(minimal: true).contains("--json-schema"))
        let defaultModel = ClaudeCodeGrader(executable: URL(fileURLWithPath: "/bin/true"), model: .default, environment: [:])
        XCTAssertFalse(defaultModel.arguments(minimal: false).contains("--model"))
    }
}

/// Runs the grader end to end against a fake `claude` script.
final class ClaudeCodeGraderProcessTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fake-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func makeScript(_ body: String) throws -> URL {
        let url = folder.appendingPathComponent("claude")
        try ("#!/bin/sh\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    let task = EssayTask(id: "e", statement: "S", instructions: "I", minutes: 30)

    func testGradesThroughFakeCLI() async throws {
        // Echo the stdin word count into the summary to prove the essay was piped in.
        let script = try makeScript("""
        words=$(cat | grep -c 'unique-essay-marker')
        printf '{"type":"result","is_error":false,"result":"","total_cost_usd":0.1,"structured_output":{"score":5,"summary":"marker=%s","criteria":[],"strengths":[],"improvements":[],"nextSteps":"x"}}' "$words"
        """)
        let grader = ClaudeCodeGrader(executable: script, model: .sonnet, environment: ["PATH": "/usr/bin:/bin"])
        let grade = try await grader.grade(task: task, essay: "My unique-essay-marker essay.", minutesUsed: 20)
        XCTAssertEqual(grade.score, 5)
        XCTAssertEqual(grade.summary, "marker=1")
        XCTAssertEqual(grade.model, "Claude Sonnet")
        XCTAssertNotNil(grade.gradedAt)
    }

    func testRetriesWithoutNewFlagsOnOldCLI() async throws {
        let grade = #"{"score":3,"summary":"ok","criteria":[],"strengths":[],"improvements":[],"nextSteps":"n"}"#
        let envelope = try JSONSerialization.data(withJSONObject: ["type": "result", "is_error": false, "result": grade] as [String: Any])
        try envelope.write(to: folder.appendingPathComponent("response.json"))
        let script = try makeScript("""
        cat > /dev/null
        for arg in "$@"; do
          if [ "$arg" = "--safe-mode" ]; then echo "error: unknown option '--safe-mode'" >&2; exit 1; fi
        done
        cat "\(folder.path)/response.json"
        """)
        let grader = ClaudeCodeGrader(executable: script, environment: ["PATH": "/usr/bin:/bin"])
        let result = try await grader.grade(task: task, essay: "Essay", minutesUsed: nil)
        XCTAssertEqual(result.score, 3)
    }

    func testTimeout() async throws {
        let script = try makeScript("sleep 5\n")
        let grader = ClaudeCodeGrader(executable: script, environment: ["PATH": "/usr/bin:/bin"], timeout: 0.5)
        do {
            _ = try await grader.grade(task: task, essay: "Essay", minutesUsed: nil)
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? EssayGradingError, .timedOut)
        }
    }

    func testMissingExecutable() async {
        let grader = ClaudeCodeGrader(executable: folder.appendingPathComponent("nope"), environment: [:])
        do {
            _ = try await grader.grade(task: task, essay: "Essay", minutesUsed: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? EssayGradingError, .claudeNotFound)
        }
    }

    func testParsesLoginShellOutput() {
        let output = "Welcome to zsh!\n__GRE_PATH__=/opt/homebrew/bin:/usr/bin\n__GRE_CLAUDE__=/opt/homebrew/bin/claude\n__GRE_ENV__\n"
            + "HTTPS_PROXY=http://proxy:8080\u{0}PWD=/tmp\u{0}MULTI=line one\nline two\u{0}CLAUDE_CONFIG_DIR=/Users/me/.claude\u{0}"
        let parsed = ClaudeCodeLocator.parseShellOutput(Data(output.utf8), isExecutable: { $0 == "/opt/homebrew/bin/claude" })
        XCTAssertEqual(parsed.path, "/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(parsed.claude, "/opt/homebrew/bin/claude")
        XCTAssertEqual(parsed.environment["HTTPS_PROXY"], "http://proxy:8080")
        XCTAssertEqual(parsed.environment["CLAUDE_CONFIG_DIR"], "/Users/me/.claude")
        XCTAssertEqual(parsed.environment["MULTI"], "line one\nline two")
        XCTAssertNil(parsed.environment["PWD"], "shell-only variables are dropped")

        let missing = ClaudeCodeLocator.parseShellOutput(Data("__GRE_PATH__=/usr/bin\n__GRE_CLAUDE__=\n".utf8), isExecutable: { _ in true })
        XCTAssertNil(missing.claude)
        XCTAssertTrue(missing.environment.isEmpty)
    }

    func testNumericAnswerTextIncludesUnits() {
        let question = Question(id: "n", category: .numericEntry, topic: "Arithmetic", difficulty: 2, format: .numeric,
                                prompt: "p", answerValue: 12.5, answerDisplay: "12.50", entryPrefix: "$",
                                explanation: "explanation text here")
        XCTAssertEqual(question.correctAnswerText, "$12.50")
        XCTAssertEqual(question.responseText(Response(numberText: "12")), "$12")
        let length = Question(id: "l", category: .numericEntry, topic: "Geometry", difficulty: 2, format: .numeric,
                              prompt: "p", answerValue: 7, answerDisplay: "7", entrySuffix: "cm",
                              explanation: "explanation text here")
        XCTAssertEqual(length.correctAnswerText, "7 cm")
    }

    func testLocatorHonoursCustomPath() throws {
        let script = try makeScript("exit 0\n")
        let location = ClaudeCodeLocator.locate(customPath: script.path, processEnvironment: ["HOME": folder.path, "SHELL": "/nonexistent"])
        XCTAssertEqual(location?.executable.path, script.path)
        XCTAssertTrue(location?.environment["PATH"]?.hasPrefix(folder.path) ?? false)
        XCTAssertNil(ClaudeCodeLocator.locate(customPath: folder.appendingPathComponent("missing").path,
                                              processEnvironment: ["HOME": folder.path]))
    }
}
