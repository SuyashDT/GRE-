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
                Button("Study Plan") { model.selection = .studyPlan }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Mock Tests") { model.selection = .mockTests }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Practice Drills") { model.selection = .drills }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Vocabulary") { model.selection = .vocabulary }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Strategy Lessons") { model.selection = .lessons }
                    .keyboardShortcut("6", modifiers: .command)
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
        let options = UITestOptions.current
        if options.background {
            // A check run that must not disturb whoever is using the Mac: no Dock icon, no focus.
            NSApp.setActivationPolicy(.accessory)
        } else {
            // When launched with `swift run` there is no app bundle; make sure the app
            // still gets a Dock icon, a menu bar and keyboard focus.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        options.scheduleSnapshot()
    }

    /// Coming back to the app picks up anything the coach wrote to the Coach folder meanwhile.
    func applicationDidBecomeActive(_ notification: Notification) {
        model?.reloadCoach()
    }

    /// Closing the window during a test or a timed set keeps the app (and the clock) running;
    /// clicking the Dock icon brings it back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        model?.exam == nil && model?.timedDrill == nil
    }

    /// ⌘Q during a test or a timed set asks first, like the Quit button.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let inTest = model?.exam != nil
        guard inTest || model?.timedDrill != nil else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = inTest ? "Quit the test?" : "Quit the timed set?"
        alert.informativeText = inTest
            ? "Your answers will be discarded and no score will be recorded."
            : "Your answers will be discarded and nothing will be recorded."
        alert.addButton(withTitle: "Keep Going")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
