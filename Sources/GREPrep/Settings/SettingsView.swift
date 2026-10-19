import SwiftUI
import GRECore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        @Bindable var model = model
        TabView {
            Form {
                Section {
                    Text("Essays are graded by Claude through the Claude Code command-line tool installed on this Mac, using your Claude login. The app never sees or stores an API key.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Claude Code") {
                    TextField("Location of `claude`", text: $model.claudeCustomPath, prompt: Text("Automatic (e.g. ~/.local/bin/claude)"))
                    HStack {
                        Button("Check Claude Code") { Task { await model.checkClaude() } }
                            .disabled(model.isCheckingClaude)
                        if model.isCheckingClaude { ProgressView().controlSize(.small) }
                    }
                    if let status = model.claudeStatus {
                        statusView(status)
                    }
                    if let location = model.claudeLocation {
                        LabeledContent("Using") { Text(location.executable.path).textSelection(.enabled) }
                    }
                }
                Section("Grading") {
                    Picker("Model", selection: $model.gradingModel) {
                        ForEach(ClaudeCodeGrader.Model.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Toggle("Grade essays automatically when a test ends", isOn: $model.autoGradeEssays)
                }
                Section("Set up Claude Code") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Install it: open Terminal and run")
                        Text("curl -fsSL https://claude.ai/install.sh | bash")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Text("2. Run `claude` once and sign in with your Claude account.")
                        Text("3. Click **Check Claude Code** above.")
                    }
                    .font(.callout)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Essay Grading", systemImage: "sparkles") }

            Form {
                Section("Vocabulary") {
                    Stepper("New words per day: \(model.newCardsPerDay)", value: $model.newCardsPerDay, in: 5...100, step: 5)
                }
                Section("Data") {
                    LabeledContent("Saved to") {
                        Text(ProgressStore.defaultStore().fileURL.path)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    Button("Reset All Progress…", role: .destructive) { confirmReset = true }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Study", systemImage: "book") }
        }
        .frame(width: 560, height: 520)
        .alert("Reset all progress?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every mock-test attempt, drill result and flashcard schedule. It can't be undone.")
        }
    }

    @ViewBuilder
    private func statusView(_ status: ClaudeCodeGrader.InstallationStatus) -> some View {
        if let version = status.version {
            Label("Installed: \(version)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.correct)
            switch status.loggedIn {
            case .some(true):
                Label("Signed in", systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(Theme.correct)
            case .some(false):
                Label("Not signed in. Run `claude` in Terminal and use /login.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(.orange)
            case .none:
                Label("Couldn't confirm sign-in; grading will tell you if it's needed.", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            if !status.detail.isEmpty {
                Text(status.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        } else {
            Label(status.detail.isEmpty ? "Claude Code wasn't found." : status.detail, systemImage: "xmark.octagon.fill")
                .foregroundStyle(Theme.incorrect)
        }
    }
}
