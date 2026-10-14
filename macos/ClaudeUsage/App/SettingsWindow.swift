import AppKit
import SwiftUI

/// Owns the settings window in AppKit. A SwiftUI `Window` scene can only be
/// opened from a live view's `openWindow`, and a menu bar app has no such
/// view at launch (the menu bar label is only drawn, not run), so first
/// launch and "open the app again" could not show it.
@MainActor
final class SettingsWindow: ObservableObject {
    private var window: NSWindow?
    private let collector: Collector
    private let store: UsageStore

    init(collector: Collector, store: UsageStore) {
        self.collector = collector
        self.store = store
    }

    func show() {
        if window == nil {
            let root = SettingsView()
                .environmentObject(collector)
                .environmentObject(store)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Claude Usage Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("Settings")
            window = w
        }
        // A menu bar app may not be allowed to activate itself (for example
        // right after launch); orderFrontRegardless shows the window anyway.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
