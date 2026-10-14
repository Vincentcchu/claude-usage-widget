import AppIntents
import WidgetKit

/// Backs the widget's refresh button. The work happens implicitly: after an
/// interactive widget's intent runs, WidgetKit reloads that widget's
/// timeline, which fetches fresh numbers.
struct RefreshUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Claude Usage"
    static var description = IntentDescription("Fetch the latest usage numbers.")

    func perform() async throws -> some IntentResult {
        .result()
    }
}
