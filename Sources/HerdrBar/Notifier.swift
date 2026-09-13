import Foundation
import UserNotifications
import AppKit

@MainActor
final class Notifier {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func handle(session: HerdrSession, agent: AgentInfo, previous: AgentStatus?) {
        let d = UserDefaults.standard
        let muted = (d.string(forKey: Prefs.mutedWorkspaces) ?? "").split(separator: ",").map(String.init)
        let wsLabel = session.workspaces.first { $0.workspaceID == agent.workspaceID }?.label ?? agent.workspaceID
        if muted.contains(wsLabel) { return }

        let title: String
        switch agent.agentStatus {
        case .blocked where d.bool(forKey: Prefs.notifyBlocked):
            title = "\(agent.agent ?? "Agent") needs your input"
        case .done where d.bool(forKey: Prefs.notifyDone) && previous == .working:
            title = "\(agent.agent ?? "Agent") finished"
        default:
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = wsLabel
        content.body = agent.displayTitle
        content.userInfo = ["pane_id": agent.paneID, "socket": session.socketPath]
        if d.bool(forKey: Prefs.sound) { content.sound = .default }
        let req = UNNotificationRequest(identifier: "herdrbar-\(agent.paneID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
