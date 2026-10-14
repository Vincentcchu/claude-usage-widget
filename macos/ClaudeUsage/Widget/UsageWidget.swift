import SwiftUI
import WidgetKit

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .sample, offline: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await Self.load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let entry = await Self.load()
            completion(Timeline(entries: [entry], policy: .after(Self.nextRefresh(for: entry))))
        }
    }

    /// macOS gives each widget a daily refresh budget, so spend it where it
    /// matters: often while Claude Code is busy, rarely when idle or when the
    /// collector is not running. The menu bar app also pushes a refresh when
    /// a limit percentage changes, and the refresh button works any time.
    static func nextRefresh(for entry: UsageEntry, now: Date = Date()) -> Date {
        let minutes: Double
        if entry.offline {
            minutes = 15
        } else if entry.snapshot?.isLive == true {
            minutes = 5
        } else {
            minutes = 15
        }
        return now.addingTimeInterval(minutes * 60)
    }

    static func load() async -> UsageEntry {
        do {
            let snapshot = try await UsageClient.fetch()
            SnapshotCache.save(snapshot)
            return UsageEntry(date: Date(), snapshot: snapshot, offline: false)
        } catch {
            return UsageEntry(date: Date(), snapshot: SnapshotCache.load(), offline: true)
        }
    }
}

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageWidgetView(entry: entry, family: family, interactive: true)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct ClaudeUsageWidget: Widget {
    let kind = "ClaudeUsage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Session and weekly Claude Code limits, tokens and cost.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
