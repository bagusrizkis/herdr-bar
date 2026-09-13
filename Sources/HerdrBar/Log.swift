import Foundation
import os

/// Thin logger: always goes to the unified log; also appends to ~/Library/Logs/HerdrBar.log when
/// `defaults write me.bagus.herdrbar debugLog -bool YES` is set, so users can send us a file.
struct AppLog: Sendable {
    private let logger = Logger(subsystem: "me.bagus.herdrbar", category: "app")
    private let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/HerdrBar.log")

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        guard UserDefaults.standard.bool(forKey: "debugLog") else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let h = try? FileHandle(forWritingTo: fileURL) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
    func info(_ message: String) { notice(message) }
}

let log = AppLog()
