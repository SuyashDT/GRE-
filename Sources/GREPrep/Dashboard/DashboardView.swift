import Charts
import SwiftUI
import GRECore

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let analytics = model.analytics
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dashboard").font(.largeTitle.weight(.semibold))
                    Text(greeting(analytics)).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                    StatTile(
                        title: "Latest Verbal",
                        value: analytics.latestScore?.verbal.map(String.init) ?? "—",
                        detail: analytics.latestScore == nil ? "Take a mock test" : "Estimated, 130–170",
                        systemImage: "text.book.closed",
                        tint: Theme.color(for: .verbal)
                    )
                    StatTile(
                        title: "Latest Quant",
                        value: analytics.latestScore?.quant.map(String.init) ?? "—",
                        detail: analytics.latestScore == nil ? "Take a mock test" : "Estimated, 130–170",
                        systemImage: "x.squareroot",
                        tint: Theme.color(for: .quant)
                    )
                    StatTile(
                        title: "Latest Writing",
                        value: analytics.latestScore?.essay.map(Format.score) ?? "—",
                        detail: "0–6 scale",
                        systemImage: "pencil.and.outline",
                        tint: .purple
                    )
                    StatTile(
                        title: "Accuracy",
                        value: analytics.overallAccuracy.map(Format.percent) ?? "—",
                        detail: "\(analytics.questionsPracticed) questions answered",
                        systemImage: "target"
                    )
                    StatTile(
                        title: "Study streak",
                        value: "\(model.streak) day\(model.streak == 1 ? "" : "s")",
                        detail: "\(model.progress.lessonsRead.count) of \(model.content?.lessons.count ?? 0) lessons read",
                        systemImage: "flame",
                        tint: .orange
                    )
                    StatTile(
                        title: "Vocabulary",
                        value: "\(analytics.vocabularyCounts(totalWords: model.content?.vocabulary.count ?? 0).mastered) mastered",
                        detail: "\(analytics.dueCardCount()) cards due now",
                        systemImage: "character.book.closed",
                        tint: Theme.correct
                    )
                }

                nextSteps(analytics)

                if analytics.scoreHistory.count >= 1 {
                    chartCard("Score history") {
                        ScoreHistoryChart(points: analytics.scoreHistory)
                    }
                }

                if !analytics.categoryStats.isEmpty {
                    chartCard("Accuracy by question type") {
                        CategoryAccuracyChart(stats: analytics.categoryStats)
                    }
                    chartCard("Average time per question") {
                        PacingChart(stats: analytics.categoryStats)
                    }
                }

                if !analytics.topicStats.isEmpty {
                    chartCard("Accuracy by content area") {
                        TopicTable(stats: analytics.topicStats)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Dashboard")
    }

    private func greeting(_ analytics: Analytics) -> String {
        if analytics.questionsPracticed == 0 && model.progress.cards.isEmpty {
            return "Welcome! Start with the GRE overview lesson, then take Mock Test 1 to find your baseline."
        }
        return "Here's how your preparation is going."
    }

    @ViewBuilder
    private func nextSteps(_ analytics: Analytics) -> some View {
        let weakest = analytics.weakestCategories()
        let due = analytics.dueCardCount()
        let hasMock = !analytics.scoreHistory.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested next steps").font(.title2.weight(.semibold))
            if !hasMock {
                suggestion("Take Mock Test 1 to get a baseline score.", systemImage: "doc.text.magnifyingglass") {
                    model.selection = .mockTests
                }
            }
            if due > 0 || model.progress.cards.isEmpty {
                suggestion(due > 0 ? "Review \(due) vocabulary cards that are due." : "Start learning vocabulary — \(model.progress.newCardsPerDay) new words a day.",
                           systemImage: "character.book.closed") {
                    model.selection = .vocabulary
                }
            }
            ForEach(weakest) { stat in
                if stat.accuracy < 0.8, let drill = model.content?.drills.sets.first(where: { $0.category == stat.category }) {
                    suggestion("Practise \(stat.category.title) — \(Format.percent(stat.accuracy)) correct so far.",
                               systemImage: Theme.icon(for: stat.category)) {
                        model.selection = .drills
                        model.drillPath = [drill.id]
                    }
                }
            }
            if model.progress.lessonsRead.isEmpty, let overview = model.content?.lesson(id: "gre-overview") {
                suggestion("Read “\(overview.title)”.", systemImage: "lightbulb") {
                    model.selection = .lessons
                    model.lessonPath = [overview.id]
                }
            }
        }
    }

    private func suggestion(_ text: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).frame(width: 24).foregroundStyle(Color.accentColor)
                Text(text)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chartCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            content()
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ScoreHistoryChart: View {
    let points: [ScorePoint]

    struct Entry: Identifiable {
        let id: String
        let label: String
        let measure: String
        let score: Int
    }

    private var entries: [Entry] {
        points.enumerated().flatMap { index, point -> [Entry] in
            let label = "Test \(index + 1)"
            var result: [Entry] = []
            if let verbal = point.verbal { result.append(Entry(id: "\(index)-v", label: label, measure: "Verbal", score: verbal)) }
            if let quant = point.quant { result.append(Entry(id: "\(index)-q", label: label, measure: "Quant", score: quant)) }
            return result
        }
    }

    var body: some View {
        Chart(entries) { entry in
            LineMark(x: .value("Attempt", entry.label), y: .value("Score", entry.score))
                .foregroundStyle(by: .value("Measure", entry.measure))
                .symbol(by: .value("Measure", entry.measure))
            PointMark(x: .value("Attempt", entry.label), y: .value("Score", entry.score))
                .foregroundStyle(by: .value("Measure", entry.measure))
                .annotation(position: .top) {
                    Text("\(entry.score)").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartYScale(domain: 130...170)
        .chartForegroundStyleScale(["Verbal": Theme.color(for: .verbal), "Quant": Theme.color(for: .quant)])
        .frame(height: 240)
    }
}

struct CategoryAccuracyChart: View {
    let stats: [CategoryStat]

    var body: some View {
        Chart(stats) { stat in
            BarMark(
                x: .value("Accuracy", stat.accuracy * 100),
                y: .value("Question type", stat.category.title)
            )
            .foregroundStyle(Theme.color(for: stat.category.measure).gradient)
            .annotation(position: .trailing) {
                Text("\(Format.percent(stat.accuracy)) of \(stat.attempted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: 0...100)
        .chartXAxisLabel { Text("% correct") }
        .frame(height: CGFloat(max(140, stats.count * 36)))
    }
}

struct PacingChart: View {
    let stats: [CategoryStat]

    var body: some View {
        let timed = stats.filter { $0.averageSeconds > 0 }
        Chart {
            ForEach(timed) { stat in
                BarMark(
                    x: .value("Seconds", stat.averageSeconds),
                    y: .value("Question type", stat.category.title)
                )
                .foregroundStyle(Theme.color(for: stat.category.measure).opacity(0.7))
                .annotation(position: .trailing) {
                    Text(Format.minutesSeconds(stat.averageSeconds)).font(.caption).foregroundStyle(.secondary)
                }
            }
            RuleMark(x: .value("Verbal target", Pacing.target(for: .verbal)))
                .foregroundStyle(Theme.color(for: .verbal))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Verbal pace 1:30").font(.caption2).foregroundStyle(.secondary)
                }
            RuleMark(x: .value("Quant target", Pacing.target(for: .quant)))
                .foregroundStyle(Theme.color(for: .quant))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .bottom, alignment: .leading) {
                    Text("Quant pace 1:45").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartXAxisLabel { Text("Seconds per question") }
        .frame(height: CGFloat(max(160, timed.count * 36 + 40)))
    }
}

struct TopicTable: View {
    let stats: [TopicStat]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                Text("Measure").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("Area").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("Correct").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("").gridCellUnsizedAxes(.horizontal)
            }
            ForEach(stats) { stat in
                GridRow {
                    Text(stat.measure.shortTitle).foregroundStyle(Theme.color(for: stat.measure))
                    Text(stat.topic)
                    Text("\(stat.correct)/\(stat.attempted)").monospacedDigit()
                    ProgressView(value: stat.accuracy)
                        .tint(stat.accuracy >= 0.75 ? Theme.correct : (stat.accuracy >= 0.5 ? Color.orange : Theme.incorrect))
                        .frame(maxWidth: 260)
                }
            }
        }
    }
}
