import SwiftUI
import AppKit
import UserNotifications

@main
struct HerdrBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = SessionStore()
    @State private var notifier = Notifier()
    @AppStorage(Prefs.showCount) private var showCount = true
    @AppStorage(Prefs.badgeBlocked) private var badgeBlocked = true

    init() {
        StatusIconRenderer.dumpIfRequested()
        Prefs.registerDefaults()
        let store = SessionStore()
        let notifier = Notifier()
        store.onTransition = { session, agent, prev in notifier.handle(session: session, agent: agent, previous: prev) }
        notifier.requestAuthorization()
        store.start()
        _store = State(initialValue: store)
        _notifier = State(initialValue: notifier)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environment(store)
        } label: {
            let state = (store.iconState == .blocked && !badgeBlocked) ? StatusIconState.working : store.iconState
            Image(nsImage: StatusIconRenderer.image(state: state, count: store.summary.working, showCount: showCount))
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:_:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    /// herdrbar://event?json=… from the Herdr plugin hook. Currently a hint: the socket is the source of truth.
    @objc func handleURL(_ event: NSAppleEventDescriptor, _ reply: NSAppleEventDescriptor) {
        guard let str = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: str) else { return }
        NotificationCenter.default.post(name: .herdrBarURL, object: url)
    }
}

extension AppDelegate {
    /// Show banners even while the popover (our "active" state) is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Click on a notification: focus that agent's pane in Herdr, then bring the terminal to the front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let paneID = info["pane_id"] as? String, let socket = info["socket"] as? String else { return }
        log.notice("notification click → focus \(paneID)")
        _ = try? await HerdrClient.call(socketPath: socket, method: "agent.focus", params: ["target": paneID])
        await TerminalActivator.activate()
    }
}

extension Notification.Name {
    static let herdrBarURL = Notification.Name("me.bagus.herdrbar.url")
}

