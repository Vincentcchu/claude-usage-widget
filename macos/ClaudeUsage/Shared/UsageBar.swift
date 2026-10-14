import SwiftUI
import WidgetKit

/// Claude's clay orange, then the same warning levels the Python app uses
/// for notifications (75% and 90%).
func usageColor(_ value: Double) -> Color {
    switch value {
    case ..<0.75: return Color(red: 0.85, green: 0.47, blue: 0.34)
    case ..<0.90: return .orange
    default: return .red
    }
}

/// A thin capsule progress bar, shared by the widget and the menu bar panel.
struct UsageBar: View {
    let value: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(usageColor(value))
                    .frame(width: max(height * 0.67, geo.size.width * value))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}
