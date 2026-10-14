import Foundation

/// Reads usage from the Python collector's local JSON server
/// (`api_server_enabled` in ~/.config/claude-usage/config.json). The widget
/// runs sandboxed and cannot read Claude Code's Keychain login, so the
/// collector stays the one place that talks to Anthropic.
enum UsageClient {
    /// The collector's default `api_server_port`. The sandboxed widget cannot
    /// read the config file, so it always uses this; the app warns when the
    /// config says otherwise.
    static let defaultPort = 8765

    static func url(port: Int) -> URL {
        URL(string: "http://127.0.0.1:\(port)/usage")!
    }

    static func fetch(port: Int = defaultPort) async throws -> UsageSnapshot {
        let request = URLRequest(
            url: url(port: port),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 5
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try UsageSnapshot(apiJSON: data)
    }
}
