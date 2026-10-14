import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    /// Latest reading, or the last cached one when `offline`.
    let snapshot: UsageSnapshot?
    /// True when the collector could not be reached.
    let offline: Bool
}

/// Pure layout, with the family passed in rather than read from the
/// environment, so it can also be rendered outside a widget for checks.
/// `interactive` is false in those renders, where App Intent buttons
/// cannot run.
struct UsageWidgetView: View {
    let entry: UsageEntry
    let family: WidgetFamily
    var interactive = false

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .systemMedium: medium(s)
            default: small(s)
            }
        } else {
            NotConnectedView(interactive: interactive)
        }
    }

    private func small(_ s: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Header(interactive: interactive)
            LimitRow(title: "Session", value: s.sessionUtilization,
                     reset: s.sessionReset, resetStyle: .countdown)
            LimitRow(title: "Weekly", value: s.weeklyUtilization,
                     reset: s.weeklyReset, resetStyle: .weekday)
            Spacer(minLength: 0)
            Footer(snapshot: s, offline: entry.offline, showTokens: true)
        }
    }

    private func medium(_ s: UsageSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Height is tight: three full rows plus a title do not fit, so the
            // title lives in the right column and the model-scoped row, which
            // normally resets with the weekly limit, skips its reset line.
            VStack(alignment: .leading, spacing: 7) {
                LimitRow(title: "Session", value: s.sessionUtilization,
                         reset: s.sessionReset, resetStyle: .countdown)
                LimitRow(title: "Weekly", value: s.weeklyUtilization,
                         reset: s.weeklyReset, resetStyle: .weekday)
                if !s.scopedLabel.isEmpty {
                    LimitRow(title: "Weekly \(s.scopedLabel)", value: s.scopedUtilization,
                             reset: nil, resetStyle: .hidden)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Header(interactive: interactive)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Today").font(.caption).foregroundStyle(.secondary)
                    Text(s.todayCost, format: .currency(code: "USD"))
                        .font(.headline.monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Text("\(compactCount(Double(s.todayTokens))) tokens · wk \(s.weekCost.formatted(.currency(code: "USD").precision(.fractionLength(0))))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ActivityLine(snapshot: s, offline: entry.offline)
                Spacer(minLength: 0)
                Footer(snapshot: s, offline: entry.offline, showTokens: false)
            }
            .frame(width: 104, alignment: .leading)
        }
    }
}

// MARK: - Pieces

private struct Header: View {
    let interactive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("Claude Usage")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            RefreshButton(interactive: interactive)
        }
    }
}

private struct RefreshButton: View {
    let interactive: Bool

    var body: some View {
        let icon = Image(systemName: "arrow.clockwise")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        if interactive {
            Button(intent: RefreshUsageIntent()) { icon }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh")
        } else {
            icon
        }
    }
}

private enum ResetStyle { case countdown, weekday, hidden }

private struct LimitRow: View {
    let title: String
    let value: Double
    let reset: Date?
    let resetStyle: ResetStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption)
                Spacer(minLength: 4)
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .font(.callout.weight(.semibold).monospacedDigit())
            }
            UsageBar(value: value)
            if resetStyle != .hidden {
                resetText
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var resetText: some View {
        if let reset, reset > Date() {
            switch resetStyle {
            // A live countdown: WidgetKit redraws it itself between refreshes.
            case .countdown: Text("Resets in \(reset, style: .relative)")
            case .weekday, .hidden:
                Text("Resets \(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
            }
        } else {
            Text(" ")
        }
    }
}

/// "● 3K tokens/min" while Claude Code is working, "Idle" otherwise. It is
/// the rate at the last refresh, not a running number: widgets are snapshots.
private struct ActivityLine: View {
    let snapshot: UsageSnapshot
    let offline: Bool

    var body: some View {
        if !offline && snapshot.isLive {
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("\(compactCount(snapshot.tokensPerMinute)) tokens/min")
            }
            .font(.caption2)
            .lineLimit(1)
        } else {
            Text("Idle").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct Footer: View {
    let snapshot: UsageSnapshot
    let offline: Bool
    let showTokens: Bool

    var body: some View {
        Group {
            if offline {
                Text("Offline since \(snapshot.fetchedAt, style: .time)")
                    .foregroundStyle(.orange)
            } else if !snapshot.rateLimitError.isEmpty {
                Text("Limits delayed, retrying")
                    .foregroundStyle(.orange)
            } else if showTokens {
                Text("\(compactCount(Double(snapshot.todayTokens))) tokens · \(snapshot.fetchedAt, style: .time)")
                    .foregroundStyle(.tertiary)
            } else {
                Text("Updated \(snapshot.fetchedAt, style: .time)")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct NotConnectedView: View {
    let interactive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(interactive: interactive)
            Spacer(minLength: 0)
            Text("Waiting for Claude Usage")
                .font(.callout.weight(.semibold))
            Text("Open the Claude Usage app. It starts the collector this widget reads from.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
