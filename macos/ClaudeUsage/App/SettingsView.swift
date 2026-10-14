import SwiftUI

/// Setup and status. Opens on first launch and when the app is opened again
/// while running.
struct SettingsView: View {
    @EnvironmentObject private var collector: Collector
    @EnvironmentObject private var store: UsageStore

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Usage").font(.title2.weight(.semibold))
                    Text("Version \(version) · lives in your menu bar")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            SettingsSection("Data") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatusBadge(snapshot: store.snapshot, reachable: store.reachable)
                        Text(collectorText).font(.callout)
                        Spacer()
                        Button("Restart") { Task { await collector.restart() } }
                            .disabled(collector.status == .external)
                    }
                    if !store.reachable {
                        CollectorProblem(status: collector.status)
                    }
                    if CollectorConfig.port != UsageClient.defaultPort {
                        Text("Your config sets api_server_port to \(CollectorConfig.port). The menu bar follows it, but the widget only reads port \(UsageClient.defaultPort).")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("Open Config Folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([CollectorConfig.url])
                        }
                        Button("Open Log") {
                            NSWorkspace.shared.open(Collector.logURL)
                        }
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsSection("Options") {
                PanelToggles()
            }

            SettingsSection("Notification Center widget") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Click the date and time in the menu bar, scroll down, click Edit Widgets and search for Claude Usage. You can also drag it onto the desktop.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("macOS decides when widgets refresh. This app nudges it whenever a limit changes, and the widget's ↻ button refreshes it on demand. For live numbers, use the menu bar.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Refresh Widget Now") { store.reloadWidgetNow() }
                        .controlSize(.small)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var collectorText: String {
        switch collector.status {
        case .running: return "Bundled collector running"
        case .starting: return "Starting collector…"
        case .external: return "Using claude-usage that was already running"
        case .missing: return "No bundled collector"
        case .failed: return "Collector stopped"
        }
    }
}

/// A titled, softly filled section, like grouped forms in System Settings.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
