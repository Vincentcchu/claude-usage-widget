import Foundation
import WidgetKit

/// Polls the collector's local server for the menu bar. The collector
/// gathers new numbers about once a minute (`refresh_seconds`), the same
/// cadence as the original desktop overlay; polling every few seconds just means
/// each new reading shows up almost as soon as it exists.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var reachable = false

    private var pollTask: Task<Void, Never>?
    private var lastWidgetReload = Date.distantPast
    private var lastReloadedKey: String?

    /// Widget refreshes come from a daily budget, so push one only when a
    /// limit percentage has moved, and at most every few minutes.
    private static let widgetReloadSpacing: TimeInterval = 180

    init() {}

    #if DEBUG
    /// For previews and layout checks.
    init(preview: UsageSnapshot) {
        snapshot = preview
        reachable = true
    }
    #endif

    func startPolling(every interval: Duration = .seconds(5)) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func poll() async {
        do {
            let s = try await UsageClient.fetch(port: CollectorConfig.port)
            let wasReachable = reachable
            snapshot = s
            reachable = true
            maybeReloadWidget(s, cameOnline: !wasReachable)
        } catch {
            reachable = false
        }
    }

    func reloadWidgetNow() {
        WidgetCenter.shared.reloadAllTimelines()
        lastWidgetReload = Date()
    }

    private func maybeReloadWidget(_ s: UsageSnapshot, cameOnline: Bool) {
        let key = "\(Int(s.sessionUtilization * 100))/\(Int(s.weeklyUtilization * 100))"
        let due = Date().timeIntervalSince(lastWidgetReload) >= Self.widgetReloadSpacing
        guard cameOnline || (key != lastReloadedKey && due) else { return }
        lastReloadedKey = key
        reloadWidgetNow()
    }
}
