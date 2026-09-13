import Foundation

enum AgentStatus: String, Codable, Sendable, CaseIterable {
    case idle, working, blocked, done, unknown

    var label: String {
        switch self {
        case .idle: "idle"
        case .working: "working"
        case .blocked: "needs input"
        case .done: "done"
        case .unknown: "unknown"
        }
    }
    /// Sort weight: what deserves attention first.
    var priority: Int {
        switch self {
        case .blocked: 0
        case .working: 1
        case .done: 2
        case .idle: 3
        case .unknown: 4
        }
    }
}

struct AgentInfo: Codable, Sendable, Identifiable, Hashable {
    var id: String { paneID }
    let paneID: String
    let workspaceID: String
    let tabID: String?
    let agent: String?
    let agentStatus: AgentStatus
    let cwd: String?
    let terminalTitle: String?
    let terminalTitleStripped: String?
    let focused: Bool?
    let stateChangeSeq: Int?

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id", workspaceID = "workspace_id", tabID = "tab_id"
        case agent, agentStatus = "agent_status", cwd, focused
        case terminalTitle = "terminal_title", terminalTitleStripped = "terminal_title_stripped"
        case stateChangeSeq = "state_change_seq"
    }

    var displayTitle: String {
        if let t = terminalTitleStripped, !t.isEmpty { return t }
        if let t = terminalTitle, !t.isEmpty { return t }
        return cwd.map { ($0 as NSString).lastPathComponent } ?? paneID
    }
    var paneLabel: String { paneID.split(separator: ":").last.map(String.init) ?? paneID }
}

struct WorkspaceInfo: Codable, Sendable, Identifiable, Hashable {
    var id: String { workspaceID }
    let workspaceID: String
    let label: String
    let number: Int?
    let agentStatus: AgentStatus?
    let focused: Bool?
    let paneCount: Int?

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id", label, number, focused
        case agentStatus = "agent_status", paneCount = "pane_count"
    }
}

struct SessionSnapshot: Codable, Sendable {
    let agents: [AgentInfo]
    let workspaces: [WorkspaceInfo]
    let focusedPaneID: String?
    let focusedWorkspaceID: String?
    let version: String?

    enum CodingKeys: String, CodingKey {
        case agents, workspaces, version
        case focusedPaneID = "focused_pane_id", focusedWorkspaceID = "focused_workspace_id"
    }
}

struct HerdrSessionEntry: Codable, Sendable, Hashable {
    let name: String
    let running: Bool
    let socketPath: String
    let isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case name, running, socketPath = "socket_path", isDefault = "default"
    }
}

struct Summary: Sendable, Equatable {
    var working = 0, blocked = 0, done = 0, idle = 0, total = 0
    init(agents: [AgentInfo]) {
        total = agents.count
        for a in agents {
            switch a.agentStatus {
            case .working: working += 1
            case .blocked: blocked += 1
            case .done: done += 1
            case .idle, .unknown: idle += 1
            }
        }
    }
    init() {}
}
