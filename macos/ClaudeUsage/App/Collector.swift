import Foundation

/// The Python collector's config file, ~/.config/claude-usage/config.json
/// (or under $XDG_CONFIG_HOME), the same path `claude_usage.config` uses.
enum CollectorConfig {
    static var url: URL {
        let env = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        let base = env.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base.appendingPathComponent("claude-usage/config.json")
    }

    static func read() -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    static var port: Int {
        (read()["api_server_port"] as? Int) ?? UsageClient.defaultPort
    }

    static func bool(_ key: String, default value: Bool) -> Bool {
        (read()[key] as? Bool) ?? value
    }

    /// Merge `updates` into the file. Only call while the bundled collector
    /// is stopped: it keeps its config in memory and rewrites the whole file
    /// when you change a setting from its own menu.
    static func update(_ updates: [String: Any]) throws {
        var cfg = read()
        var changed = false
        // NSObject equality, so a JSON `true` (an NSNumber) matches Swift `true`.
        for (key, value) in updates where !((cfg[key] as? NSObject)?.isEqual(value) ?? false) {
            cfg[key] = value
            changed = true
        }
        guard changed else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}

/// Starts, watches and stops the Python collector bundled at
/// Contents/Helpers/ClaudeUsageCollector.app. The collector is the regular
/// claude-usage widget (limits, cost, notifications) run with `--no-osd`, so
/// its overlay never appears; its localhost server feeds the menu bar and
/// the widget.
@MainActor
final class Collector: ObservableObject {
    enum Status: Equatable {
        case starting
        /// Our bundled collector is running.
        case running
        /// Another claude-usage (pip, Homebrew, `python main.py`) already
        /// serves the data, so we use it and leave it alone.
        case external
        /// This build has no bundled collector (built in Xcode without
        /// macos/build.sh). The app still works with an external one.
        case missing
        case failed(String)
    }

    @Published private(set) var status: Status = .starting

    /// The collector we launched. Cleared *before* we stop it on purpose,
    /// so its exit is not mistaken for a crash.
    private var process: Process?
    private var recentExits: [Date] = []

    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Claude Usage/collector.log")

    static var helperURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Helpers/ClaudeUsageCollector.app/Contents/MacOS/ClaudeUsageCollector")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    func start() async {
        guard process == nil else { return }
        // A collector from this bundle that we don't own was left behind by
        // a previous run that didn't exit cleanly (a crash, a force quit).
        // Replace it, so Restart and quitting keep working.
        if let helper = Self.helperURL {
            await Self.stopStray(path: helper.resolvingSymlinksInPath().path)
        }
        if (try? await UsageClient.fetch(port: CollectorConfig.port)) != nil {
            status = .external
            return
        }
        guard let helper = Self.helperURL else {
            status = .missing
            return
        }
        do {
            // The menu bar and the widget read from the collector's server.
            try CollectorConfig.update(["api_server_enabled": true])
        } catch {
            status = .failed("Couldn't update \(CollectorConfig.url.path): \(error.localizedDescription)")
            return
        }
        launch(helper)
    }

    func restart() async {
        await stopAndWait()
        recentExits.removeAll()
        await start()
    }

    /// Called on quit. The collector holds no unsaved state worth waiting
    /// long for: settings are written the moment they change.
    func stopAndWait(timeout: TimeInterval = 3) async {
        guard let p = process else { return }
        process = nil
        p.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    func stopNow() {
        guard let p = process else { return }
        process = nil
        p.terminate()
        p.waitUntilExit()
    }

    private func launch(_ helper: URL) {
        let p = Process()
        p.executableURL = helper
        // The menu bar and the widget replace the desktop overlay.
        p.arguments = ["--no-osd"]
        if let log = Self.openLog() {
            p.standardOutput = log
            p.standardError = log
        }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            Task { @MainActor in self?.handleExit(proc, code: code) }
        }
        do {
            try p.run()
            process = p
            status = .running
        } catch {
            status = .failed("Couldn't start the collector: \(error.localizedDescription)")
        }
    }

    private func handleExit(_ proc: Process, code: Int32) {
        // Only the current collector matters; one we stopped on purpose has
        // already been cleared from `process`.
        guard proc === process else { return }
        process = nil
        // Unexpected exit. It quits right away with status 0 when another
        // claude-usage already holds the single-instance lock.
        let now = Date()
        recentExits = recentExits.filter { now.timeIntervalSince($0) < 120 } + [now]
        if recentExits.count >= 3 {
            status = .failed(code == 0
                ? "Another copy of claude-usage seems to be running without its local server. Quit it, or set \"api_server_enabled\": true in its config, then click Restart."
                : "The collector keeps stopping (exit code \(code)). Details are in the log.")
            return
        }
        status = .starting
        Task {
            try? await Task.sleep(for: .seconds(3))
            await start()
        }
    }

    private static func stopStray(path: String) async {
        let strays = processIDs(runningExecutable: path)
        guard !strays.isEmpty else { return }
        strays.forEach { kill($0, SIGTERM) }
        for _ in 0..<30 where strays.contains(where: { kill($0, 0) == 0 }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        strays.filter { kill($0, 0) == 0 }.forEach { kill($0, SIGKILL) }
    }

    /// PIDs of processes whose executable is exactly `path`.
    static func processIDs(runningExecutable path: String) -> [pid_t] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(max(0, count)).filter { pid in
            pid > 0 && pid != getpid()
                && proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0
                && String(cString: buffer) == path
        }
    }

    private static func openLog() -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Start fresh each launch, keeping one previous run for comparison.
        let previous = logURL.appendingPathExtension("1")
        try? fm.removeItem(at: previous)
        try? fm.moveItem(at: logURL, to: previous)
        fm.createFile(atPath: logURL.path, contents: nil)
        return try? FileHandle(forWritingTo: logURL)
    }
}
