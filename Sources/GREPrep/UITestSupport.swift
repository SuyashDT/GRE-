import AppKit
import SwiftUI
import GRECore

/// Launch arguments for checking a build without clicking through it, for example
///
///     GRE_DATA=$(mktemp -d)
///     GREPREP_DATA_DIR="$GRE_DATA" "build/GRE Prep.app/Contents/MacOS/GREPrep" \
///         -UITestScreen studyPlan -UITestBackground YES -UITestSnapshot /tmp/plan.png
///
/// Always set `GREPREP_DATA_DIR` for such a run, so it can't touch real progress.
/// None of this does anything unless one of the arguments is given.
struct UITestOptions {
    /// `-UITestScreen <dashboard|studyPlan|mockTests|drills|vocabulary|lessons>`: the screen to open.
    var screen: SidebarItem?
    /// `-UITestDrill <set id>`: open this set in Practice Drills.
    var drill: String?
    /// `-UITestStartTimed YES`: start that set at once if it is a timed one.
    var startTimed = false
    /// `-UITestBackground YES`: stay out of the way. No Dock icon, no focus taken, and a window that is
    /// laid out and drawn but invisible and click-through, so it can't disturb whoever is using the Mac.
    var background = false
    /// `-UITestSnapshot <file.png>`: write a picture of the window to this file, then quit.
    var snapshotPath: String?
    /// `-UITestSnapshotDelay <seconds>`: how long to let the screen settle first (default 2).
    var snapshotDelay: Double = 2

    static let current = UITestOptions(defaults: .standard)

    init(defaults: UserDefaults) {
        screen = defaults.string(forKey: "UITestScreen").flatMap(SidebarItem.init(rawValue:))
        drill = defaults.string(forKey: "UITestDrill").flatMap { $0.isEmpty ? nil : $0 }
        startTimed = defaults.bool(forKey: "UITestStartTimed")
        background = defaults.bool(forKey: "UITestBackground")
        snapshotPath = defaults.string(forKey: "UITestSnapshot").flatMap { $0.isEmpty ? nil : $0 }
        let delay = defaults.double(forKey: "UITestSnapshotDelay")
        if delay > 0 { snapshotDelay = delay }
    }

    /// Opens the screen the arguments ask for, once content and progress are loaded.
    @MainActor
    func apply(to model: AppModel) {
        if let screen { model.selection = screen }
        if let drill {
            model.selection = .drills
            model.drillPath = [drill]
            if startTimed, let set = model.content?.drillSet(id: drill) {
                model.startTimedDrill(set)
            }
        }
    }

    /// Writes the snapshot after the delay and quits. The app draws its own window into the picture,
    /// so this needs no screen-recording permission and works while the window is invisible.
    @MainActor
    func scheduleSnapshot() {
        guard let snapshotPath else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + snapshotDelay) {
            let saved = Self.writeSnapshot(to: URL(fileURLWithPath: (snapshotPath as NSString).expandingTildeInPath))
            if !saved { FileHandle.standardError.write(Data("UITestSnapshot: nothing to draw\n".utf8)) }
            exit(saved ? 0 : 1)
        }
    }

    @MainActor
    private static func writeSnapshot(to url: URL) -> Bool {
        let windows = NSApp.windows.filter { $0.contentView != nil && $0.frame.width > 200 }
        guard let window = windows.first(where: { $0.isMainWindow }) ?? windows.max(by: { $0.frame.width < $1.frame.width }),
              let view = window.contentView
        else { return false }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // The window's own background isn't part of the content view, so paint it in behind the picture.
        guard let flattened = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: flattened) else { return false }
        let frame = NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.textBackgroundColor.setFill()
            frame.fill()
        }
        bitmap.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = flattened.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            return true
        } catch {
            return false
        }
    }
}

/// Makes the window it sits in invisible and click-through. Used for `-UITestBackground YES`.
struct InvisibleWindow: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.alphaValue = 0
            window?.ignoresMouseEvents = true
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}
