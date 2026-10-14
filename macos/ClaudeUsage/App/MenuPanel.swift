import ServiceManagement
import SwiftUI

/// The panel that drops down from the menu bar item.
struct MenuPanel: View {
    @EnvironmentObject private var store: UsageStore
    @EnvironmentObject private var collector: Collector
    @EnvironmentObject private var settings: SettingsWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude Usage").font(.headline)
                Spacer()
                StatusBadge(snapshot: store.snapshot, reachable: store.reachable)
            }

            if store.reachable, let s = store.snapshot {
                UsageDetails(snapshot: s)
            } else {
                CollectorProblem(status: collector.status)
            }

            Divider()

            PanelToggles()

            HStack {
                Button("Settings…") { settings.show() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
    }
}

struct StatusBadge: View {
    let snapshot: UsageSnapshot?
    let reachable: Bool

    var body: some View {
        let (label, color): (String, Color) =
            !reachable ? ("Offline", .orange)
            : snapshot?.isLive == true ? ("Live", .green)
            : ("Idle", .secondary)
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct UsageDetails: View {
    let snapshot: UsageSnapshot

    var body: some View {
        let s = snapshot
        VStack(alignment: .leading, spacing: 12) {
            Limit(title: "Session", value: s.sessionUtilization) {
                if let r = s.sessionReset, r > Date() {
                    Text("Resets in \(r, style: .relative)")
                }
            }
            Limit(title: "Weekly", value: s.weeklyUtilization) {
                if let r = s.weeklyReset, r > Date() {
                    Text("Resets \(r.formatted(.dateTime.weekday(.wide).hour().minute()))")
                }
            }
            if !s.scopedLabel.isEmpty {
                Limit(title: "Weekly \(s.scopedLabel)", value: s.scopedUtilization) {
                    if let r = s.scopedReset, r > Date() {
                        Text("Resets \(r.formatted(.dateTime.weekday(.wide).hour().minute()))")
                    }
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Activity").foregroundStyle(.secondary)
                    if s.isLive {
                        Text("\(s.tokensPerMinute.formatted(.number.precision(.fractionLength(0)))) tokens/min")
                    } else {
                        Text("Idle")
                    }
                }
                GridRow {
                    Text("Today").foregroundStyle(.secondary)
                    Text(s.todayCost, format: .currency(code: "USD"))
                }
                GridRow {
                    Text("").gridCellUnsizedAxes(.horizontal)
                    Text("\(s.todayTokens.formatted()) tokens · \(s.todayMessages.formatted()) messages")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("This week").foregroundStyle(.secondary)
                    Text(s.weekCost, format: .currency(code: "USD"))
                }
            }
            .font(.callout)

            if !s.rateLimitError.isEmpty {
                Text("Limits are delayed: \(s.rateLimitError). Retrying automatically.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("Updated \(s.fetchedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct Limit<Footer: View>: View {
    let title: String
    let value: Double
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.body.weight(.semibold).monospacedDigit())
            }
            UsageBar(value: value, height: 7)
            footer
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Explains why there are no numbers, in terms of what to do next.
struct CollectorProblem: View {
    let status: Collector.Status

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch status {
            case .starting, .running:
                Label("Starting the collector…", systemImage: "hourglass")
                Text("The first reading takes a few seconds.")
                    .font(.caption).foregroundStyle(.secondary)
            case .external:
                Label("Lost the running claude-usage", systemImage: "exclamationmark.triangle")
                Text("It was serving the numbers but stopped answering. Use Restart in Settings to start the bundled collector.")
                    .font(.caption).foregroundStyle(.secondary)
            case .missing:
                Label("No collector in this build", systemImage: "exclamationmark.triangle")
                Text("Build with macos/build.sh to bundle it, or run claude-usage with \"api_server_enabled\": true.")
                    .font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Label("The collector isn't running", systemImage: "exclamationmark.triangle")
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The "Open at login" switch, shared by the panel and the settings window.
struct PanelToggles: View {
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwitchRow("Open at login", isOn: Binding(
                get: { openAtLogin },
                set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                    }
                    openAtLogin = SMAppService.mainApp.status == .enabled
                }
            ))
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { openAtLogin = SMAppService.mainApp.status == .enabled }
    }
}

/// Label on the left, switch on the right, like System Settings.
private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
