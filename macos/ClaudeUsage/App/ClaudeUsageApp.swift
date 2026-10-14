import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let collector = Collector()
    let store = UsageStore()
    lazy var settings = SettingsWindow(collector: collector, store: store)
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `kill`, logout scripts and `pkill` send SIGTERM, which would end the
        // app without applicationWillTerminate and leave the collector
        // running. Route it through a normal quit instead.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigterm = source

        Task { @MainActor in
            await collector.start()
            store.startPolling()
        }

        // A menu bar app otherwise gives no sign it started, so greet the
        // first launch with the settings window.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didShowWelcome") {
            defaults.set(true, forKey: "didShowWelcome")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.settings.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        collector.stopNow()
    }

    /// Double-clicking the app while it runs: there is no Dock icon or
    /// window, so show settings rather than appear to do nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settings.show()
        return false
    }
}

/// A menu bar app (no Dock icon) that carries the Notification Center
/// widget and runs the bundled Python collector both of them read from.
@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environmentObject(delegate.collector)
                .environmentObject(delegate.store)
                .environmentObject(delegate.settings)
        } label: {
            MenuBarLabel()
                .environmentObject(delegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The text next to the clock: session usage, plus tokens per minute while
/// Claude Code is working.
struct MenuBarLabel: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.50percent")
            Text(title).monospacedDigit()
        }
    }

    private var title: String {
        guard store.reachable, let s = store.snapshot else { return "–" }
        let pct = s.sessionUtilization.formatted(.percent.precision(.fractionLength(0)))
        return s.isLive ? "\(pct) · \(compactCount(s.tokensPerMinute))/min" : pct
    }
}
