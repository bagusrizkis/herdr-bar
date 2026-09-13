import AppKit

/// Brings the terminal app that hosts Herdr to the front.
enum TerminalActivator {
    static let knownBundleIDs = [
        "com.googlecode.iterm2", "com.apple.Terminal", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "org.alacritty", "dev.warp.Warp-Stable",
    ]

    @MainActor
    static func activate() {
        for id in knownBundleIDs {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else { continue }
            let ok = app.activate(from: .current, options: [.activateIgnoringOtherApps])
            log.notice("activate \(id): \(ok)")
            if !ok, let url = app.bundleURL {
                // Cooperative activation refused; asking the workspace to open the app always activates it.
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            return
        }
        log.notice("no known terminal running")
    }
}
