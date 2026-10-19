import SwiftUI
import GRECore

struct MockTestsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.mockPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    ForEach(model.content?.mockTests ?? []) { test in
                        MockTestCard(test: test)
                    }
                    pastAttempts
                }
                .padding(28)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Mock Tests")
            .navigationDestination(for: UUID.self) { id in
                AttemptResultsView(attemptId: id)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Full-length mock tests")
                .font(.largeTitle.weight(.semibold))
            Text("Timed exactly like the current GRE General Test, with section-level adaptive scoring.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var pastAttempts: some View {
        let attempts = model.progress.mockAttempts.sorted { $0.finishedAt > $1.finishedAt }
        if !attempts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your attempts").font(.title2.weight(.semibold))
                ForEach(attempts) { attempt in
                    NavigationLink(value: attempt.id) {
                        AttemptRow(attempt: attempt, title: model.content?.mockTest(id: attempt.testId)?.title ?? attempt.testId)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete Attempt", role: .destructive) { model.deleteAttempt(attempt.id) }
                    }
                }
            }
        }
    }
}

struct MockTestCard: View {
    @Environment(AppModel.self) private var model
    let test: MockTest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(test.title).font(.title2.weight(.semibold))
                    Text(test.formatVersion).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.startExam(test)
                } label: {
                    Label("Start Test", systemImage: "play.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Text(test.description)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Label("\(test.totalMinutes / 60) h \(test.totalMinutes % 60) min", systemImage: "clock")
                Label("1 essay", systemImage: "pencil.and.outline")
                Label("27 Verbal", systemImage: "text.book.closed")
                Label("27 Quant", systemImage: "x.squareroot")
                Label("Adaptive", systemImage: "arrow.triangle.branch")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            if let last = model.attempts(forTest: test.id).first(where: \.completed) {
                Text("Last result: Verbal \(last.verbal?.scaled ?? 0) · Quant \(last.quant?.scaled ?? 0)\(last.essay?.score.map { " · Writing \(Format.score($0))" } ?? "")")
                    .font(.callout.weight(.medium))
            }
        }
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AttemptRow: View {
    let attempt: MockAttempt
    let title: String

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(Format.date.string(from: attempt.finishedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if attempt.completed {
                scoreBadge("V", attempt.verbal?.scaled.description ?? "—", Theme.color(for: .verbal))
                scoreBadge("Q", attempt.quant?.scaled.description ?? "—", Theme.color(for: .quant))
                scoreBadge("AW", attempt.essay?.score.map(Format.score) ?? "…", .purple)
            } else {
                Pill(text: "Incomplete", color: .orange)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private func scoreBadge(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
        .frame(minWidth: 44)
    }
}
