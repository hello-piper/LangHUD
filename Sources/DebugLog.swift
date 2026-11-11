import Foundation

/// 调试日志：HUD_DEBUG=1 时写入 /tmp/langhud-debug.log
enum DebugLog {
    /// HUD_DEBUG=1 或 UserDefaults 的 debugLog=true（可随时开关，不用重编）
    static let enabled = ProcessInfo.processInfo.environment["HUD_DEBUG"] != nil
        || UserDefaults.standard.bool(forKey: "debugLog")

    private static let url = URL(fileURLWithPath: "/tmp/langhud-debug.log")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func reset() {
        guard enabled else { return }
        try? Data().write(to: url)
    }

    static func write(_ message: String) {
        guard enabled else { return }
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
