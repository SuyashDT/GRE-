import SwiftUI
import GRECore

/// Score report for one mock-test attempt: estimated scores, essay grading
/// (Claude Code or self-scored), per-section breakdown and question review.
struct AttemptResultsView: View {
    @Environment(AppModel.self) private var model
    let attemptId: UUID

    @State private var reviewing: ReviewTarget?

    struct ReviewTarget: Identifiable, Hashable {
        let questionId: String
        var id: String { questionId }
    }

    var body: some View {
        if let attempt = model.attempt(id: attemptId), let test = model.content?.mockTest(id: attempt.testId) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(attempt, test)
                    scoreRow(attempt)
                    EssayResultSection(attempt: attempt, test: test)
                    ForEach(attempt.sections) { section in
                        SectionReview(section: section, attempt: attempt, test: test) { questionId in
                            reviewing = ReviewTarget(questionId: questionId)
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 960, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Results")
            .sheet(item: $reviewing) { target in
                QuestionReviewSheet(attempt: attempt, test: test, questionId: target.questionId)
            }
        } else {
            ContentUnavailableView("Attempt not found", systemImage: "questionmark.folder")
        }
    }

    private func header(_ attempt: MockAttempt, _ test: MockTest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(test.title).font(.largeTitle.weight(.semibold))
            Text("Finished \(Format.date.string(from: attempt.finishedAt))\(attempt.completed ? "" : " · incomplete")")
                .foregroundStyle(.secondary)
        }
    }

    private func scoreRow(_ attempt: MockAttempt) -> some View {
        HStack(spacing: 14) {
            measureTile(attempt.verbal, measure: .verbal)
            measureTile(attempt.quant, measure: .quant)
            StatTile(
                title: "Analytical Writing",
                value: attempt.essay?.score.map(Format.score) ?? (model.gradingInProgress.contains(attempt.id) ? "Grading…" : "—"),
                detail: attempt.essay?.grade != nil ? "Graded by \(attempt.essay?.grade?.model ?? "Claude")" :
                    (attempt.essay?.selfScore != nil ? "Self-scored" : "0–6 scale"),
                systemImage: "pencil.and.outline",
                tint: .purple
            )
        }
    }

    private func measureTile(_ estimate: ScoreEstimate?, measure: Measure) -> some View {
        StatTile(
            title: measure.title,
            value: estimate.map { "\($0.scaled)" } ?? "—",
            detail: estimate.map { "Likely range \($0.rangeText) · \($0.rawCorrect)/\($0.questionCount) correct · \($0.stage2Tier.title.lowercased()) section 2" }
                ?? "Not completed",
            systemImage: measure == .verbal ? "text.book.closed" : "x.squareroot",
            tint: Theme.color(for: measure)
        )
    }
}

// MARK: - Essay

struct EssayResultSection: View {
    @Environment(AppModel.self) private var model
    let attempt: MockAttempt
    let test: MockTest
    @State private var showEssay = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Analytical Writing").font(.title2.weight(.semibold))
                Spacer()
                if let essay = attempt.essay {
                    Text("\(essay.wordCount) words · \(Format.minutesSeconds(essay.secondsUsed)) used")
                        .foregroundStyle(.secondary)
                }
            }
            if let essay = attempt.essay {
                if model.gradingInProgress.contains(attempt.id) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Claude Code is grading your essay. This usually takes a minute or two…")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                } else if let grade = essay.grade {
                    EssayGradeView(grade: grade)
                    if let error = model.gradingErrors[attempt.id] {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Grade Again") { Task { await model.gradeEssay(attemptId: attempt.id) } }
                        .controlSize(.small)
                } else {
                    ungraded(essay)
                }
                DisclosureGroup("Your response", isExpanded: $showEssay) {
                    Text(essay.text.isEmpty ? "(blank)" : essay.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                }
                Text("Prompt: \(test.essay.statement)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func ungraded(_ essay: EssayResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = model.gradingErrors[attempt.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button {
                    Task { await model.gradeEssay(attemptId: attempt.id) }
                } label: {
                    Label("Grade with Claude Code", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(essay.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                SettingsLink {
                    Text("Claude Code settings…")
                }
                .buttonStyle(.link)
            }
            Text("Uses the Claude Code app installed on this Mac and your Claude login. Or score it yourself with the rubric:")
                .font(.callout)
                .foregroundStyle(.secondary)
            SelfScorePicker(attempt: attempt)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SelfScorePicker: View {
    @Environment(AppModel.self) private var model
    let attempt: MockAttempt

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Self score", selection: Binding(
                get: { attempt.essay?.selfScore ?? -1 },
                set: { model.setSelfScore($0 < 0 ? nil : $0, attemptId: attempt.id) }
            )) {
                Text("Not scored").tag(-1.0)
                ForEach(Array(stride(from: 6.0, through: 0.0, by: -0.5)), id: \.self) { value in
                    Text(Format.score(value)).tag(value)
                }
            }
            .frame(maxWidth: 260)
            DisclosureGroup("Scoring guide") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(EssayRubric.levels) { level in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(level.score)").font(.headline).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.title).font(.subheadline.weight(.semibold))
                                Text(level.description).font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}

struct EssayGradeView: View {
    let grade: EssayGrade

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Format.score(grade.score))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(EssayRubric.levels.first { Double($0.score) == grade.score.rounded(.down) }?.title ?? "")
                        .font(.headline)
                    Text("Practice estimate by \(grade.model ?? "Claude")\(grade.gradedAt.map { " · \(Format.date.string(from: $0))" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(grade.summary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if !grade.criteria.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    ForEach(Array(grade.criteria.enumerated()), id: \.offset) { _, criterion in
                        GridRow(alignment: .firstTextBaseline) {
                            Text(criterion.name).font(.subheadline.weight(.semibold))
                            Text(Format.score(criterion.score)).monospacedDigit().foregroundStyle(.purple)
                            Text(criterion.comment).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                listBox("Strengths", grade.strengths, systemImage: "hand.thumbsup", color: Theme.correct)
                listBox("To improve", grade.improvements, systemImage: "arrow.up.right", color: .orange)
            }
            if !grade.nextSteps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Before your next essay", systemImage: "flag").font(.subheadline.weight(.semibold))
                    Text(grade.nextSteps).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func listBox(_ title: String, _ items: [String], systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(.secondary)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sections

struct SectionReview: View {
    let section: SectionResult
    let attempt: MockAttempt
    let test: MockTest
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(section.measure.title) — Section \(section.stage)")
                    .font(.title2.weight(.semibold))
                if section.stage == 2 {
                    Pill(text: "\(section.tier.title) section", color: section.tier == .harder ? Theme.correct : .orange)
                }
                Spacer()
                Text("\(section.correctCount)/\(section.questionCount) correct · \(Format.minutesSeconds(section.secondsUsed)) of \(section.minutesAllowed):00")
                    .foregroundStyle(.secondary)
            }
            if section.stage == 1 {
                Text(routingNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(section.questions.enumerated()), id: \.offset) { index, result in
                    Button {
                        onSelect(result.questionId)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: result.correct ? "checkmark.circle.fill" : (result.answered ? "xmark.circle.fill" : "minus.circle"))
                                .foregroundStyle(result.correct ? Theme.correct : (result.answered ? Theme.incorrect : .secondary))
                            Text("Q\(index + 1)").monospacedDigit().frame(width: 36, alignment: .leading)
                            Text(result.category.title).frame(width: 200, alignment: .leading)
                            Text(result.topic).foregroundStyle(.secondary)
                            Spacer()
                            Text("Difficulty \(result.difficulty)").font(.caption).foregroundStyle(.secondary)
                            Text(Format.minutesSeconds(result.seconds))
                                .monospacedDigit()
                                .foregroundStyle(result.seconds > Pacing.target(for: section.measure) * 1.5 ? Color.orange : Color.secondary)
                                .frame(width: 50, alignment: .trailing)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < section.questions.count - 1 { Divider() }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var routingNote: String {
        let threshold = test.routing.threshold(for: section.measure)
        let routedHarder = section.correctCount >= threshold
        return "You needed \(threshold) of \(section.questionCount) correct for the harder second section, and got \(section.correctCount) — so you were routed to the \(routedHarder ? "harder" : "easier") section."
    }
}

struct QuestionReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let attempt: MockAttempt
    let test: MockTest
    let questionId: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Question review").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            if let question = test.allQuestions.first(where: { $0.id == questionId }) {
                QuestionScreen(
                    question: question,
                    stimulus: test.stimulus(question.stimulusId),
                    response: .constant(attempt.responses[question.id] ?? Response()),
                    mode: .review,
                    timeSpent: attempt.sections.flatMap(\.questions).first { $0.questionId == questionId }?.seconds
                )
            }
        }
        .frame(minWidth: 900, idealWidth: 1100, minHeight: 620, idealHeight: 760)
    }
}
