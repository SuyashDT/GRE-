import SwiftUI
import GRECore

struct DrillsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.drillPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Practice drills").font(.largeTitle.weight(.semibold))
                        Text("Untimed sets by question type. You'll see the answer and an explanation after each question.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Measure.allCases, id: \.self) { measure in
                        let sets = (model.content?.drills.sets ?? []).filter { $0.measure == measure }
                        if !sets.isEmpty {
                            Text(measure.title).font(.title2.weight(.semibold))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                                ForEach(sets) { drillSet in
                                    NavigationLink(value: drillSet.id) {
                                        DrillCard(drill: drillSet, attempts: model.drillAttempts(setId: drillSet.id))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Practice Drills")
            .navigationDestination(for: String.self) { setId in
                if let drillSet = model.content?.drillSet(id: setId) {
                    DrillSessionView(drill: drillSet)
                }
            }
        }
    }
}

struct DrillCard: View {
    let drill: DrillSet
    let attempts: [DrillAttempt]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: Theme.icon(for: drill.category))
                    .font(.title2)
                    .foregroundStyle(Theme.color(for: drill.measure))
                Spacer()
                Text("\(drill.questions.count) questions").font(.caption).foregroundStyle(.secondary)
            }
            Text(drill.title).font(.headline)
            Text(drill.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3, reservesSpace: true)
            if let best = attempts.map(\.correctCount).max() {
                Text("Best: \(best)/\(drill.questions.count) · \(attempts.count) attempt\(attempts.count == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.color(for: drill.measure))
            } else {
                Text("Not started").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }
}

/// Works through a drill set one question at a time: answer, check, read the explanation.
struct DrillSessionView: View {
    @Environment(AppModel.self) private var model
    let drill: DrillSet

    @State private var index = 0
    @State private var responses: [String: Response] = [:]
    @State private var revealed: Set<String> = []
    @State private var timeSpent: [String: Double] = [:]
    @State private var shownAt = Date()
    @State private var finished = false
    @State private var recorded = false

    private var question: Question? { drill.questions[safe: index] }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            Divider()
            if finished {
                summary
            } else if let question {
                QuestionScreen(
                    question: question,
                    stimulus: model.content?.drillStimulus(question.stimulusId),
                    response: Binding(
                        get: { responses[question.id] ?? Response(blankChoices: Array(repeating: nil, count: question.blanks?.count ?? 0)) },
                        set: { responses[question.id] = $0 }
                    ),
                    mode: .practice(revealed: revealed.contains(question.id)),
                    timeSpent: revealed.contains(question.id) ? timeSpent[question.id] : nil
                )
                .id(question.id)
                Divider()
                controls(question)
            }
        }
        .navigationTitle(drill.title)
        .onAppear { shownAt = Date() }
        .onDisappear { recordIfNeeded() }
    }

    private var progressHeader: some View {
        HStack(spacing: 12) {
            Text(drill.title).font(.headline)
            ProgressView(value: Double(finished ? drill.questions.count : index), total: Double(max(1, drill.questions.count)))
                .frame(maxWidth: 240)
            Text(finished ? "Done" : "Question \(index + 1) of \(drill.questions.count)")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(correctCount) correct")
                .foregroundStyle(Theme.correct)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func controls(_ question: Question) -> some View {
        HStack {
            Button("Previous") { move(to: index - 1) }
                .disabled(index == 0)
            Spacer()
            if revealed.contains(question.id) {
                Button(index == drill.questions.count - 1 ? "See Results" : "Next Question") {
                    if index == drill.questions.count - 1 {
                        finished = true
                        recordIfNeeded()
                    } else {
                        move(to: index + 1)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Skip") { reveal(question) }
                Button("Check Answer") { reveal(question) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(question.state(of: responses[question.id]) != .answered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var correctCount: Int {
        drill.questions.filter { revealed.contains($0.id) && $0.isCorrect(responses[$0.id]) }.count
    }

    private func reveal(_ question: Question) {
        timeSpent[question.id, default: 0] += Date().timeIntervalSince(shownAt)
        revealed.insert(question.id)
    }

    private func move(to newIndex: Int) {
        guard drill.questions.indices.contains(newIndex) else { return }
        if let question, !revealed.contains(question.id) {
            timeSpent[question.id, default: 0] += Date().timeIntervalSince(shownAt)
        }
        index = newIndex
        shownAt = Date()
    }

    private func recordIfNeeded() {
        guard !recorded else { return }
        let results = drill.questions.filter { revealed.contains($0.id) }.map { question in
            QuestionResult(
                questionId: question.id, category: question.category, topic: question.topic,
                difficulty: question.difficulty,
                answered: question.state(of: responses[question.id]) == .answered,
                correct: question.isCorrect(responses[question.id]),
                seconds: timeSpent[question.id] ?? 0
            )
        }
        guard !results.isEmpty else { return }
        recorded = true
        model.recordDrill(DrillAttempt(setId: drill.id, results: results))
    }

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(correctCount) of \(drill.questions.count) correct")
                    .font(.largeTitle.weight(.semibold))
                Text(encouragement)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(drill.questions.enumerated()), id: \.offset) { offset, question in
                        Button {
                            finished = false
                            move(to: offset)
                        } label: {
                            HStack {
                                Image(systemName: question.isCorrect(responses[question.id]) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(question.isCorrect(responses[question.id]) ? Theme.correct : Theme.incorrect)
                                Text("Question \(offset + 1)")
                                Text(question.topic).foregroundStyle(.secondary)
                                Spacer()
                                Text("Difficulty \(question.difficulty)").font(.caption).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Button("Practice Again") { restart() }
                        .buttonStyle(.borderedProminent)
                    if let lesson = model.content?.lessons(for: drill.category).first {
                        Button("Read the \(lesson.title) lesson") {
                            model.selection = .lessons
                            model.lessonPath = [lesson.id]
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var encouragement: String {
        let ratio = Double(correctCount) / Double(max(1, drill.questions.count))
        switch ratio {
        case 0.85...: return "Excellent — you're handling this question type at a high level."
        case 0.6..<0.85: return "Solid work. Review the explanations for the ones you missed."
        default: return "Keep at it. Read the strategy lesson, then try the set again."
        }
    }

    private func restart() {
        responses = [:]
        revealed = []
        timeSpent = [:]
        index = 0
        finished = false
        recorded = false
        shownAt = Date()
    }
}
