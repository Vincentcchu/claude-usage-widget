import Foundation

/// The part of the Python collector's `/usage` JSON that the app and the
/// widget show.
struct UsageSnapshot: Codable, Equatable {
    var sessionUtilization: Double   // 0...1
    var sessionReset: Date?
    var weeklyUtilization: Double
    var weeklyReset: Date?
    var scopedUtilization: Double
    var scopedReset: Date?
    var scopedLabel: String          // e.g. "Opus"; empty when the plan has no scoped cap
    var todayCost: Double
    var weekCost: Double
    var todayTokens: Int
    var todayMessages: Int
    var isLive: Bool                 // Claude Code produced output in the last few minutes
    var tokensPerMinute: Double
    var rateLimitError: String
    var fetchedAt: Date
}

extension UsageSnapshot {
    /// Decode the Python payload: snake_case keys, unix-second timestamps
    /// where 0 means "unknown".
    init(apiJSON data: Data, fetchedAt: Date = Date()) throws {
        struct Live: Decodable {
            var is_live: Bool?
            var tokens_per_minute: Double?
        }
        struct Raw: Decodable {
            var session_utilization: Double?
            var session_reset: Double?
            var weekly_utilization: Double?
            var weekly_reset: Double?
            var scoped_utilization: Double?
            var scoped_reset: Double?
            var scoped_label: String?
            var today_cost: Double?
            var week_cost: Double?
            var today_tokens: Int?
            var today_messages: Int?
            var live_activity: Live?
            var rate_limit_error: String?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        func date(_ t: Double?) -> Date? {
            guard let t, t > 0 else { return nil }
            return Date(timeIntervalSince1970: t)
        }
        func pct(_ v: Double?) -> Double { min(1, max(0, v ?? 0)) }
        self.init(
            sessionUtilization: pct(raw.session_utilization),
            sessionReset: date(raw.session_reset),
            weeklyUtilization: pct(raw.weekly_utilization),
            weeklyReset: date(raw.weekly_reset),
            scopedUtilization: pct(raw.scoped_utilization),
            scopedReset: date(raw.scoped_reset),
            scopedLabel: raw.scoped_label ?? "",
            todayCost: raw.today_cost ?? 0,
            weekCost: raw.week_cost ?? 0,
            todayTokens: raw.today_tokens ?? 0,
            todayMessages: raw.today_messages ?? 0,
            isLive: raw.live_activity?.is_live ?? false,
            tokensPerMinute: raw.live_activity?.tokens_per_minute ?? 0,
            rateLimitError: raw.rate_limit_error ?? "",
            fetchedAt: fetchedAt
        )
    }

    /// Shown in the widget gallery and while a real reading loads.
    static let sample = UsageSnapshot(
        sessionUtilization: 0.42,
        sessionReset: Date().addingTimeInterval(2 * 3600 + 13 * 60),
        weeklyUtilization: 0.18,
        weeklyReset: Date().addingTimeInterval(4 * 86400),
        scopedUtilization: 0.07,
        scopedReset: Date().addingTimeInterval(4 * 86400),
        scopedLabel: "Opus",
        todayCost: 12.40,
        weekCost: 58.15,
        todayTokens: 167_496,
        todayMessages: 214,
        isLive: true,
        tokensPerMinute: 2993,
        rateLimitError: "",
        fetchedAt: Date()
    )
}

/// Compact counts for tight spaces: 167496 -> "167K", 2993 -> "3K".
func compactCount(_ n: Double) -> String {
    n.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
}

/// Remembers the last good reading so the widget can show it, marked as
/// stale, when the collector is not running. Each process (app, widget)
/// has its own sandboxed defaults; the widget's copy is the one that matters.
enum SnapshotCache {
    private static let key = "lastSnapshot"

    static func save(_ snapshot: UsageSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> UsageSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
