import AppKit
import SwiftUI

@main
struct GREPrepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("GRE Prep") {
            RootView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 700)
                .task {
                    appDelegate.model = model
                    await model.start()
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Study") {
                Button("Dashboard") { model.selection = .dashboard }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Mock Tests") { model.selection = .mockTests }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Practice Drills") { model.selection = .drills }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Vocabulary") { model.selection = .vocabulary }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Strategy Lessons") { model.selection = .lessons }
                    .keyboardShortcut("5", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When launched with `swift run` there is no app bundle; make sure the app
        // still gets a Dock icon, a menu bar and keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window during a test keeps the app (and the test clock) running;
    /// clicking the Dock icon brings the test back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        model?.exam == nil
    }

    /// ⌘Q during a test asks first, like the Quit Test button.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.exam != nil else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit the test?"
        alert.informativeText = "Your answers will be discarded and no score will be recorded."
        alert.addButton(withTitle: "Keep Going")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
