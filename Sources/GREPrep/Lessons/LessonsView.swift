import SwiftUI
import GRECore

struct LessonsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.lessonPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Strategy lessons").font(.largeTitle.weight(.semibold))
                        Text("Short guides to every part of the test: what it asks, how to approach it, and the traps to avoid.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Lesson.Area.allCases, id: \.self) { area in
                        let lessons = (model.content?.lessons ?? []).filter { $0.measure == area }
                        if !lessons.isEmpty {
                            Text(area.title).font(.title2.weight(.semibold))
                            VStack(spacing: 0) {
                                ForEach(lessons) { lesson in
                                    NavigationLink(value: lesson.id) {
                                        LessonRow(lesson: lesson, isRead: model.progress.lessonsRead.contains(lesson.id))
                                    }
                                    .buttonStyle(.plain)
                                    if lesson.id != lessons.last?.id { Divider() }
                                }
                            }
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Strategy Lessons")
            .navigationDestination(for: String.self) { id in
                if let lesson = model.content?.lesson(id: id) {
                    LessonDetailView(lesson: lesson)
                }
            }
        }
    }
}

struct LessonRow: View {
    let lesson: Lesson
    let isRead: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: lesson.category.map(Theme.icon(for:)) ?? "lightbulb")
                .font(.title3)
                .foregroundStyle(Theme.color(for: lesson.measure))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.title).font(.headline)
                Text(lesson.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text("\(lesson.minutes) min").font(.caption).foregroundStyle(.secondary)
            if isRead {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.correct)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(14)
        .contentShape(Rectangle())
    }
}

struct LessonDetailView: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson
    @State private var showWalkthrough = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Pill(text: lesson.measure.title, color: Theme.color(for: lesson.measure))
                        if let category = lesson.category { Pill(text: category.title) }
                        Pill(text: "\(lesson.minutes) min read")
                    }
                    Text(lesson.title).font(.largeTitle.weight(.semibold))
                    Text(lesson.summary).font(.title3).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(lesson.blocks.enumerated()), id: \.offset) { _, block in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(block.heading).font(.title2.weight(.semibold))
                        MarkdownBlocks(text: block.body)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    tipBox("Key tips", lesson.keyTips, systemImage: "checkmark.seal", color: Theme.correct)
                    tipBox("Common traps", lesson.commonTraps, systemImage: "exclamationmark.triangle", color: .orange)
                }

                if let example = lesson.example {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Worked example", systemImage: "pencil.and.list.clipboard").font(.title2.weight(.semibold))
                        MarkdownBlocks(text: example.question)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                        DisclosureGroup("Walkthrough", isExpanded: $showWalkthrough) {
                            MarkdownBlocks(text: example.walkthrough)
                                .padding(.top, 8)
                        }
                        .font(.headline)
                    }
                }

                if let drillId = lesson.drillId, let drill = model.content?.drillSet(id: drillId) {
                    Button {
                        model.selection = .drills
                        model.drillPath = [drill.id]
                    } label: {
                        Label("Practice: \(drill.title) drill (\(drill.questions.count) questions)", systemImage: "target")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if lesson.id == "vocab-strategy" {
                    Button {
                        model.selection = .vocabulary
                    } label: {
                        Label("Open vocabulary flashcards", systemImage: "character.book.closed")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
            .textSelection(.enabled)
        }
        .navigationTitle(lesson.title)
        .onAppear { model.markLessonRead(lesson.id) }
    }

    private func tipBox(_ title: String, _ items: [String], systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage).font(.headline).foregroundStyle(color)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(.secondary)
                    RichText(item).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}
