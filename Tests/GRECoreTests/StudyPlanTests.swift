import XCTest
@testable import GRECore

final class StudyPlanTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func loadLibrary() throws -> ContentLibrary {
        guard ContentLibrary.bundledContentFolder() != nil else {
            throw XCTSkip("Content folder not built yet")
        }
        return try ContentLibrary.loadBundled()
    }

    /// 2026-11-02 is a Monday.
    func date(_ day: Int, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    func plan(days: Int, minutes: Int = 60, rest: Int? = nil, library: ContentLibrary) -> StudyPlan {
        let start = date(2)
        let exam = calendar.date(byAdding: .day, value: days, to: start)!
        return StudyPlan.make(
            settings: StudyPlanSettings(examDate: exam, startDate: start, minutesPerDay: minutes, restWeekday: rest),
            content: library, newCardsPerDay: 20, calendar: calendar
        )
    }

    func testLongPlanCoversEverythingInOrder() throws {
        let library = try loadLibrary()
        let plan = plan(days: 60, library: library)
        XCTAssertEqual(plan.days.count, 61)
        XCTAssertNil(plan.minutesNeeded)
        XCTAssertEqual(Set(plan.days.flatMap(\.tasks).map(\.id)).count, plan.days.flatMap(\.tasks).count, "task ids are unique")

        // Diagnostic first, after the overview lesson.
        let first = plan.days[0].tasks.map(\.kind)
        XCTAssertEqual(first, [.lesson("gre-overview"), .mockTest(library.mockTests[0].id)])
        XCTAssertEqual(plan.days[1].tasks.map(\.kind).prefix(2), [.vocabulary, .reviewMock])

        // Every lesson and every drill is scheduled before the final week.
        let finalWeek = plan.days.filter { $0.phase == .finalWeek || $0.phase == .examDay }.map(\.id)
        let early = plan.days.filter { !finalWeek.contains($0.id) }.flatMap(\.tasks).map(\.kind)
        for lesson in library.lessons {
            XCTAssertTrue(early.contains(.lesson(lesson.id)), lesson.id)
        }
        for set in library.drills.sets {
            XCTAssertTrue(early.contains(.drill(set.id)), set.id)
        }

        // A dress rehearsal about a week out, a light day before the test, and the test itself.
        let mockDays = plan.days.filter { $0.tasks.contains { if case .mockTest = $0.kind { return true }; return false } }
        XCTAssertEqual(mockDays.count, 2)
        XCTAssertEqual(mockDays.last?.date, date(25, month: 12))
        XCTAssertEqual(plan.days[59].tasks.map(\.kind), [.vocabulary, .lightReview])
        XCTAssertEqual(plan.days.last?.tasks.map(\.kind), [.examDay])
        XCTAssertEqual(plan.days.last?.date, calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)))

        // Foundations come first and are spread out rather than crammed into the first days.
        let phases = plan.days.map(\.phase)
        XCTAssertEqual(phases.first, .foundations)
        XCTAssertTrue(phases.contains(.practice))
        let foundationCount = phases.filter { $0 == .foundations }.count
        XCTAssertGreaterThan(foundationCount, 10)
        XCTAssertLessThan(foundationCount, 30)

        // Study days stay close to the daily budget (mock-test days are the exception).
        for day in plan.days where !day.tasks.contains(where: { if case .mockTest = $0.kind { return true }; return false }) && day.phase != .examDay {
            XCTAssertLessThanOrEqual(day.minutes, 60 + 30, day.id)
        }
    }

    func testRestDaysHaveNoStudy() throws {
        let library = try loadLibrary()
        let plan = plan(days: 28, rest: 1, library: library) // Sundays off
        let sundays = plan.days.filter { calendar.component(.weekday, from: $0.date) == 1 && $0.phase != .examDay }
        XCTAssertEqual(sundays.count, 4)
        // The last Sunday is the day before the test, which is always a light study day.
        XCTAssertTrue(sundays.dropLast().allSatisfy(\.isRestDay))
        XCTAssertEqual(sundays.last?.tasks.map(\.kind), [.vocabulary, .lightReview])
        XCTAssertEqual(plan.days.filter(\.isRestDay).count, 3)
    }

    func testShortPlanSaysHowMuchTimeItNeeds() throws {
        let library = try loadLibrary()
        let plan = plan(days: 6, minutes: 30, library: library)
        let kinds = plan.days.flatMap(\.tasks).map(\.kind)
        for lesson in library.lessons {
            XCTAssertTrue(kinds.contains(.lesson(lesson.id)), lesson.id)
        }
        let needed = try XCTUnwrap(plan.minutesNeeded)
        XCTAssertGreaterThan(needed, 30)
    }

    func testExamDateNotAfterStartGivesOnlyTestDay() throws {
        let library = try loadLibrary()
        let plan = plan(days: 0, library: library)
        XCTAssertEqual(plan.days.map { $0.tasks.map(\.kind) }, [[.examDay]])
    }

    func testCompletionIsDetectedFromProgress() throws {
        let library = try loadLibrary()
        let plan = plan(days: 60, library: library)
        let tasks = plan.days.flatMap { day in day.tasks.map { (day, $0) } }
        var progress = ProgressData()

        let (lessonDay, lesson) = try XCTUnwrap(tasks.first { if case .lesson("tc") = $0.1.kind { return true }; return false })
        XCTAssertFalse(StudyPlan.isDone(lesson, on: lessonDay.date, progress: progress, calendar: calendar))
        progress.lessonsRead.insert("tc")
        XCTAssertTrue(StudyPlan.isDone(lesson, on: lessonDay.date, progress: progress, calendar: calendar))

        // The first time a drill comes up, any attempt counts; a repeat needs a newer attempt.
        let drills = tasks.filter { $0.1.kind == .drill("d-tc") }
        let (firstDay, firstDrill) = try XCTUnwrap(drills.first)
        progress.drillAttempts.append(DrillAttempt(setId: "d-tc", date: firstDay.date.addingTimeInterval(3600), results: []))
        XCTAssertTrue(StudyPlan.isDone(firstDrill, on: firstDay.date, progress: progress, calendar: calendar))
        if drills.count > 1 {
            let (repeatDay, repeatDrill) = drills[1]
            XCTAssertFalse(StudyPlan.isDone(repeatDrill, on: repeatDay.date, progress: progress, calendar: calendar))
            progress.drillAttempts.append(DrillAttempt(setId: "d-tc", date: repeatDay.date.addingTimeInterval(3600), results: []))
            XCTAssertTrue(StudyPlan.isDone(repeatDrill, on: repeatDay.date, progress: progress, calendar: calendar))
        }

        // Vocabulary counts only on the day the cards were reviewed.
        let (vocabDay, vocab) = try XCTUnwrap(tasks.first { $0.1.kind == .vocabulary })
        let reviewed = vocabDay.date.addingTimeInterval(7200)
        progress.cards["w"] = CardState(wordId: "w", ease: 2.5, intervalDays: 1, repetitions: 1, lapses: 0,
                                        due: reviewed, firstSeen: reviewed, lastReviewed: reviewed)
        XCTAssertTrue(StudyPlan.isDone(vocab, on: vocabDay.date, progress: progress, calendar: calendar))
        let (laterDay, laterVocab) = try XCTUnwrap(tasks.last { $0.1.kind == .vocabulary })
        XCTAssertFalse(StudyPlan.isDone(laterVocab, on: laterDay.date, progress: progress, calendar: calendar))

        // Tasks the app can't see are ticked off by hand.
        let (reviewDay, review) = try XCTUnwrap(tasks.first { $0.1.kind == .reviewMock })
        XCTAssertFalse(StudyPlan.isDone(review, on: reviewDay.date, progress: progress, calendar: calendar))
        progress.planChecked.insert(review.id)
        XCTAssertTrue(StudyPlan.isDone(review, on: reviewDay.date, progress: progress, calendar: calendar))
    }

    func testPlanSettingsRoundTripThroughProgressFile() throws {
        var progress = ProgressData()
        progress.studyPlan = StudyPlanSettings(examDate: date(20, month: 12), startDate: date(2), minutesPerDay: 90, restWeekday: 7)
        progress.planChecked = ["2026-11-03/review-mock"]
        let data = try ProgressStore.encoder.encode(progress)
        let decoded = try ProgressStore.decoder.decode(ProgressData.self, from: data)
        XCTAssertEqual(decoded.studyPlan, progress.studyPlan)
        XCTAssertEqual(decoded.planChecked, progress.planChecked)
    }
}
