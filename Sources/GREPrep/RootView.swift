import SwiftUI
import GRECore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let exam = model.exam {
                ExamView(session: exam)
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
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Study") {
                    ForEach(SidebarItem.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .badge(badge(for: item))
                            .tag(item)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            switch model.selection ?? .dashboard {
            case .dashboard: DashboardView()
            case .mockTests: MockTestsView()
            case .drills: DrillsView()
            case .vocabulary: VocabularyView()
            case .lessons: LessonsView()
            }
        }
    }

    private func badge(for item: SidebarItem) -> Int {
        item == .vocabulary ? model.analytics.dueCardCount() : 0
    }
}
