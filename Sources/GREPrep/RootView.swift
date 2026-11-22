import SwiftUI
import GRECore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let exam = model.exam {
                ExamView(session: exam)
            } else if let timed = model.timedDrill {
                TimedDrillView(session: timed)
            } else if let error = model.loadError {
                ContentUnavailableView("Couldn't load study content", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.content == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MainView()
            }
        }
        .overlay(alignment: .bottom) {
            if let error = model.saveError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .onTapGesture { model.saveError = nil }
            }
        }
        .background { if UITestOptions.current.background { InvisibleWindow() } }
        .task {
            // The Coach folder is also read when the app becomes active (see AppDelegate). This catches
            // files the coach writes while the app stays in front. It only reads a few file dates.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                model.reloadCoach()
            }
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            // Re-render every minute so the "cards due" and plan badges stay current.
            TimelineView(.everyMinute) { context in
                List(selection: $model.selection) {
                    Section("Study") {
                        ForEach(SidebarItem.allCases) { item in
                            Label(item.title, systemImage: item.systemImage)
                                .badge(badge(for: item, now: context.date))
                                .tag(item)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            switch model.selection ?? .dashboard {
            case .dashboard: DashboardView()
            case .studyPlan: StudyPlanView()
            case .mockTests: MockTestsView()
            case .drills: DrillsView()
            case .vocabulary: VocabularyView()
            case .lessons: LessonsView()
            }
        }
    }

    private func badge(for item: SidebarItem, now: Date) -> Int {
        switch item {
        case .vocabulary: return model.analytics.dueCardCount(now: now)
        case .studyPlan: return model.openPlanTaskCount(now: now)
        default: return 0
        }
    }
}
