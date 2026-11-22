import XCTest
@testable import GRECore

/// Saved progress must survive app updates in both directions that matter:
/// a file written before coach sets existed still loads, and saving it again loses nothing.
final class ProgressCompatibilityTests: XCTestCase {
    /// `progress.json` in the shape the app wrote before timed sets and saved responses were added.
    static let earlierFile = """
    {
      "cards" : {
        "aberrant" : {
          "due" : "2026-11-05T18:30:00Z",
          "ease" : 2.5,
          "firstSeen" : "2026-11-05T12:55:09Z",
          "intervalDays" : 1,
          "lapses" : 0,
          "lastReviewed" : "2026-11-05T12:55:09Z",
          "repetitions" : 1,
          "wordId" : "aberrant"
        }
      },
      "drillAttempts" : [
        {
          "date" : "2026-11-05T13:58:56Z",
          "id" : "52EB0389-944B-4AD6-8F0C-B83E7B6F2C84",
          "results" : [
            {
              "answered" : true,
              "category" : "quantitativeComparison",
              "correct" : true,
              "difficulty" : 2,
              "questionId" : "d-qc-01",
              "seconds" : 35.5,
              "topic" : "Arithmetic"
            }
          ],
          "setId" : "d-qc"
        }
      ],
      "lessonsRead" : [
        "gre-overview"
      ],
      "mockAttempts" : [
        {
          "completed" : true,
          "essay" : {
            "secondsUsed" : 1795.25,
            "selfScore" : 4,
            "text" : "Some essay text.",
            "wordCount" : 3
          },
          "finishedAt" : "2026-11-22T07:10:00Z",
          "id" : "0B8E2F6A-3C55-4C0E-9B57-3E1D2A6F9C11",
          "quant" : {
            "high" : 160,
            "low" : 154,
            "measure" : "quant",
            "questionCount" : 27,
            "rawCorrect" : 17,
            "scaled" : 157,
            "stage2Tier" : "harder"
          },
          "responses" : {
            "m1-q1-01" : {
              "blankChoices" : [],
              "denominatorText" : "",
              "numberText" : "",
              "selected" : [2]
            },
            "m1-q1-05" : {
              "blankChoices" : [],
              "denominatorText" : "4",
              "numberText" : "3",
              "selected" : []
            },
            "m1-v1-01" : {
              "blankChoices" : [1, null],
              "denominatorText" : "",
              "numberText" : "",
              "selected" : []
            }
          },
          "sections" : [
            {
              "measure" : "verbal",
              "minutesAllowed" : 18,
              "questions" : [
                {
                  "answered" : true,
                  "category" : "textCompletion",
                  "correct" : false,
                  "difficulty" : 3,
                  "questionId" : "m1-v1-01",
                  "seconds" : 71.25,
                  "topic" : "Contrast"
                }
              ],
              "secondsUsed" : 1012.5,
              "sectionId" : "V1",
              "stage" : 1,
              "tier" : "standard"
            }
          ],
          "startedAt" : "2026-11-22T05:10:00Z",
          "testId" : "mock-test-1",
          "verbal" : {
            "high" : 153,
            "low" : 147,
            "measure" : "verbal",
            "questionCount" : 27,
            "rawCorrect" : 12,
            "scaled" : 150,
            "stage2Tier" : "easier"
          }
        }
      ],
      "newCardsPerDay" : 20,
      "planChecked" : [
        "2026-11-03/review-mock"
      ],
      "studyDays" : [
        "2026-11-05",
        "2026-11-22"
      ],
      "studyPlan" : {
        "examDate" : "2026-12-10T18:30:00Z",
        "minutesPerDay" : 120,
        "restWeekday" : 1,
        "startDate" : "2026-11-22T04:40:00Z"
      },
      "version" : 1
    }
    """

    func testEarlierFileLoads() throws {
        let progress = try ProgressStore.decoder.decode(ProgressData.self, from: Data(Self.earlierFile.utf8))
        XCTAssertEqual(progress.cards["aberrant"]?.intervalDays, 1)
        XCTAssertEqual(progress.lessonsRead, ["gre-overview"])
        XCTAssertEqual(progress.planChecked, ["2026-11-03/review-mock"])
        XCTAssertEqual(progress.studyDays, ["2026-11-05", "2026-11-22"])
        XCTAssertEqual(progress.studyPlan?.minutesPerDay, 120)
        XCTAssertEqual(progress.newCardsPerDay, 20)

        let drill = try XCTUnwrap(progress.drillAttempts.first)
        XCTAssertEqual(drill.setId, "d-qc")
        XCTAssertNil(drill.timed, "earlier files don't say whether a drill was timed")
        XCTAssertFalse(drill.isTimed)
        XCTAssertNil(drill.timeLimitMinutes)
        XCTAssertNil(drill.secondsUsed)
        XCTAssertEqual(drill.results.first?.seconds, 35.5)
        XCTAssertNil(drill.results.first?.response)

        let mock = try XCTUnwrap(progress.mockAttempts.first)
        XCTAssertTrue(mock.completed)
        XCTAssertEqual(mock.verbal?.scaled, 150)
        XCTAssertEqual(mock.quant?.stage2Tier, .harder)
        XCTAssertEqual(mock.essay?.selfScore, 4)
        XCTAssertEqual(mock.responses["m1-q1-01"]?.selected, [2])
        XCTAssertEqual(mock.responses["m1-v1-01"]?.blankChoices, [1, nil])
        XCTAssertEqual(mock.responses["m1-q1-05"]?.denominatorText, "4")
        XCTAssertEqual(mock.sections.first?.questions.first?.questionId, "m1-v1-01")
    }

    /// Loading the earlier file and saving it again writes the same JSON: nothing dropped, nothing added.
    func testEarlierFileRoundTripsWithoutLosingOrAddingAnything() throws {
        let original = Data(Self.earlierFile.utf8)
        let progress = try ProgressStore.decoder.decode(ProgressData.self, from: original)
        let saved = try ProgressStore.encoder.encode(progress)
        XCTAssertEqual(try ProgressStore.decoder.decode(ProgressData.self, from: saved), progress)

        let before = try JSONSerialization.jsonObject(with: original)
        let after = try JSONSerialization.jsonObject(with: saved)
        XCTAssertEqual(Self.differences(before, after), [])
    }

    /// Where two JSON values differ, as paths like `mockAttempts[0].essay.selfScore`.
    /// Arrays that hold a set (order not kept) are compared without regard to order.
    static func differences(_ old: Any, _ new: Any, path: String = "") -> [String] {
        switch (old, new) {
        case let (old as [String: Any], new as [String: Any]):
            return Set(old.keys).union(new.keys).sorted().flatMap { key -> [String] in
                let place = path.isEmpty ? key : "\(path).\(key)"
                guard let before = old[key] else { return ["\(place) was added"] }
                guard let after = new[key] else { return ["\(place) was dropped"] }
                return differences(before, after, path: place)
            }
        case let (old as [Any], new as [Any]):
            guard old.count == new.count else { return ["\(path) has \(new.count) items, was \(old.count)"] }
            let unordered = ["studyDays", "lessonsRead", "planChecked", "selected"].contains { path.hasSuffix($0) }
            if unordered {
                let key: (Any) -> String = { "\($0)" }
                return old.map(key).sorted() == new.map(key).sorted() ? [] : ["\(path) has different items"]
            }
            return zip(old, new).enumerated().flatMap { index, pair in
                differences(pair.0, pair.1, path: "\(path)[\(index)]")
            }
        default:
            return (old as? NSObject) == (new as? NSObject) ? [] : ["\(path): \(new) was \(old)"]
        }
    }

    func testStoreRoundTripsTheEarlierFileOnDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gre-progress-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = ProgressStore(fileURL: folder.appendingPathComponent("progress.json"))
        try Data(Self.earlierFile.utf8).write(to: store.fileURL)

        var progress = try store.load()
        progress.planChecked.insert("1122-class")
        try store.save(progress)
        let reloaded = try store.load()
        XCTAssertEqual(reloaded, progress)
        XCTAssertEqual(reloaded.mockAttempts.count, 1)
        XCTAssertEqual(reloaded.planChecked, ["2026-11-03/review-mock", "1122-class"])
    }

    func testTimedAttemptsAndResponsesAreSaved() throws {
        let blanks = Response(blankChoices: [2, nil])
        let numeric = Response(numberText: "12.5")
        // Dates are saved to the second, so use a whole second to compare after a round trip.
        let when = Date(timeIntervalSince1970: 1_795_000_000)
        let attempt = DrillAttempt(
            setId: "coach-1124-verbal", date: when,
            results: [
                QuestionResult(questionId: "c-01", category: .textCompletion, topic: "Contrast", difficulty: 3,
                               answered: false, correct: false, seconds: 80, response: blanks),
                QuestionResult(questionId: "c-02", category: .sentenceEquivalence, topic: "Definition", difficulty: 2,
                               answered: true, correct: true, seconds: 41, response: Response(selected: [1, 4])),
                QuestionResult(questionId: "c-03", category: .numericEntry, topic: "Algebra", difficulty: 4,
                               answered: true, correct: false, seconds: 130, response: numeric),
                QuestionResult(questionId: "c-04", category: .problemSolving, topic: "Geometry", difficulty: 4,
                               answered: false, correct: false, seconds: 0),
            ],
            timed: true, timeLimitMinutes: 18, secondsUsed: 1080
        )
        var progress = ProgressData()
        progress.drillAttempts = [attempt, DrillAttempt(setId: "d-tc", date: when, results: [], timed: false)]

        let data = try ProgressStore.encoder.encode(progress)
        let decoded = try ProgressStore.decoder.decode(ProgressData.self, from: data)
        XCTAssertEqual(decoded, progress)
        let saved = try XCTUnwrap(decoded.drillAttempts.first)
        XCTAssertTrue(saved.isTimed)
        XCTAssertEqual(saved.timeLimitMinutes, 18)
        XCTAssertEqual(saved.secondsUsed, 1080)
        XCTAssertEqual(saved.results[0].response, blanks)
        XCTAssertEqual(saved.results[1].response?.selected, [1, 4])
        XCTAssertEqual(saved.results[2].response?.numberText, "12.5")
        XCTAssertNil(saved.results[3].response)
        XCTAssertEqual(decoded.drillAttempts[1].timed, false)

        // The coach reads the file as plain JSON: the response is there in a form that needs no app.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let attempts = try XCTUnwrap(json["drillAttempts"] as? [[String: Any]])
        XCTAssertEqual(attempts[0]["timed"] as? Bool, true)
        XCTAssertEqual(attempts[0]["timeLimitMinutes"] as? Int, 18)
        let results = try XCTUnwrap(attempts[0]["results"] as? [[String: Any]])
        XCTAssertEqual(Set((results[1]["response"] as? [String: Any])?["selected"] as? [Int] ?? []), [1, 4])
        XCTAssertNil(results[3]["response"], "a question with no answer saved has no response key")
        XCTAssertNil(attempts[1]["timeLimitMinutes"])
    }

    func testASittingIsRecordedWithWhatTheLearnerAnswered() {
        func question(_ id: String, _ category: QuestionCategory, format: AnswerFormat, options: [String]? = nil,
                      blanks: [[String]]? = nil, selectCount: Int? = nil, correct: [Int]? = nil, value: Double? = nil) -> Question {
            Question(id: id, category: category, topic: category.measure == .verbal ? "Contrast" : "Algebra", difficulty: 3,
                     format: format, prompt: "p", options: options, blanks: blanks, selectCount: selectCount,
                     correct: correct, answerValue: value, answerDisplay: value.map { "\($0)" }, explanation: "An explanation.")
        }
        let set = DrillSet(
            id: "coach-set", title: "Coach set", measure: .verbal, summary: "s",
            questions: [
                question("q1", .textCompletion, format: .blanks, blanks: [["a", "b", "c", "d", "e"]], correct: [1]),
                question("q2", .sentenceEquivalence, format: .multiple, options: ["a", "b", "c", "d", "e", "f"], selectCount: 2, correct: [0, 2]),
                question("q3", .sentenceEquivalence, format: .multiple, options: ["a", "b", "c", "d", "e", "f"], selectCount: 2, correct: [1, 5]),
                question("q4", .textCompletion, format: .blanks, blanks: [["a", "b", "c", "d", "e"]], correct: [4]),
            ],
            timeLimitMinutes: 6
        )
        let responses: [String: Response] = [
            "q1": Response(blankChoices: [1]),          // right
            "q2": Response(selected: [0, 3]),           // wrong: one of the two is a trap
            "q3": Response(selected: [1]),              // half-finished when time ran out
        ]
        let when = Date(timeIntervalSince1970: 1_795_000_000)

        // A timed set records every question, like a section of a test.
        let timed = set.makeAttempt(responses: responses, timeSpent: ["q1": 50, "q2": 95, "q3": 120], timed: true, secondsUsed: 360, date: when)
        XCTAssertEqual(timed.setId, "coach-set")
        XCTAssertEqual(timed.date, when)
        XCTAssertTrue(timed.isTimed)
        XCTAssertEqual(timed.timeLimitMinutes, 6)
        XCTAssertEqual(timed.secondsUsed, 360)
        XCTAssertEqual(timed.results.map(\.questionId), ["q1", "q2", "q3", "q4"])
        XCTAssertEqual(timed.results.map(\.correct), [true, false, false, false])
        XCTAssertEqual(timed.results.map(\.answered), [true, true, false, false])
        XCTAssertEqual(timed.results.map(\.seconds), [50, 95, 120, 0])
        XCTAssertEqual(timed.results[0].response?.blankChoices, [1])
        XCTAssertEqual(timed.results[1].response?.selected, [0, 3], "the wrong pick is kept for the coach")
        XCTAssertEqual(timed.results[2].response?.selected, [1], "so is a half-finished answer")
        XCTAssertNil(timed.results[3].response)
        XCTAssertEqual(timed.correctCount, 1)

        // An untimed drill records only the questions that were checked or skipped, and no clock.
        let untimed = set.makeAttempt(responses: responses, timeSpent: ["q1": 50], including: ["q1", "q4"], timed: false, secondsUsed: 99, date: when)
        XCTAssertEqual(untimed.results.map(\.questionId), ["q1", "q4"])
        XCTAssertEqual(untimed.timed, false)
        XCTAssertNil(untimed.timeLimitMinutes)
        XCTAssertNil(untimed.secondsUsed)
    }

    /// The analytics the dashboard uses count coach-set results like any other drill result.
    func testDashboardCountsTimedAttempts() {
        var progress = ProgressData()
        progress.drillAttempts = [DrillAttempt(
            setId: "coach-1124-verbal",
            results: [
                QuestionResult(questionId: "c-01", category: .textCompletion, topic: "Contrast", difficulty: 3,
                               answered: true, correct: true, seconds: 60, response: Response(blankChoices: [0])),
                QuestionResult(questionId: "c-02", category: .textCompletion, topic: "Contrast", difficulty: 3,
                               answered: false, correct: false, seconds: 0),
            ],
            timed: true, timeLimitMinutes: 3, secondsUsed: 180
        )]
        let analytics = Analytics(progress: progress)
        XCTAssertEqual(analytics.questionsPracticed, 2)
        XCTAssertEqual(analytics.categoryStats.first?.category, .textCompletion)
        XCTAssertEqual(analytics.categoryStats.first?.correct, 1)
        XCTAssertEqual(analytics.categoryStats.first?.averageSeconds, 60, "questions never looked at don't drag the pace down")
    }
}
