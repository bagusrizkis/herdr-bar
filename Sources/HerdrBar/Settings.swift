import SwiftUI
import ServiceManagement

enum Prefs {
    static let showCount = "showCount"
    static let badgeBlocked = "badgeBlocked"
    static let notifyBlocked = "notifyBlocked"
    static let notifyDone = "notifyDone"
    static let sound = "sound"
    static let mutedWorkspaces = "mutedWorkspaces"  // comma-separated workspace labels
    static let panelSort = "panelSort"              // "spaces" | "priority" (mirrors herdr agent_panel_sort)

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showCount: true, badgeBlocked: true, notifyBlocked: true, notifyDone: true, sound: false,
            panelSort: "spaces",
        ])
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.showCount) private var showCount = true
    @AppStorage(Prefs.badgeBlocked) private var badgeBlocked = true
    @AppStorage(Prefs.notifyBlocked) private var notifyBlocked = true
    @AppStorage(Prefs.notifyDone) private var notifyDone = true
    @AppStorage(Prefs.sound) private var sound = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView {
            Form {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                Text("Herdr Bar reads the Herdr socket API; it never writes to your panes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Toggle("Show number of working agents", isOn: $showCount)
                Toggle("Badge when an agent needs input", isOn: $badgeBlocked)
            }
            .tabItem { Label("Icon", systemImage: "circle.dotted") }

            Form {
                Toggle("Agent needs input (blocked)", isOn: $notifyBlocked)
                Toggle("Agent finished (done)", isOn: $notifyDone)
                Toggle("Sound", isOn: $sound)
            }
            .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 260)
    }
}

/// Own the Settings window explicitly: the SwiftUI `Settings` scene is unreliable from a MenuBarExtra popover.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Herdr Bar Settings"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
