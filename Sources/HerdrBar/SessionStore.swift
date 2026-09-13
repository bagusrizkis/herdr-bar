import Foundation
import Observation

/// One connected Herdr session (default or named).
@MainActor
@Observable
final class HerdrSession: @MainActor Identifiable {
    let name: String
    let socketPath: String
    var id: String { socketPath }

    private(set) var agents: [AgentInfo] = []
    private(set) var workspaces: [WorkspaceInfo] = []
    private(set) var connected = false
    private(set) var lastError: String?
    /// When each pane last changed status (for the "3 min" column).
    private(set) var statusSince: [String: Date] = [:]
    private var lastStatus: [String: AgentStatus] = [:]

    /// Streaming connection (events.subscribe only). Ordinary calls go through HerdrClient.call.
    private var client: HerdrClient?
    private var refetchScheduled = false
    private var reconnectDelay: TimeInterval = 1
    private var reconnectTask: Task<Void, Never>?

    /// Emitted on status transitions the notifier cares about.
    var onTransition: ((AgentInfo, AgentStatus?) -> Void)?

    init(name: String, socketPath: String) {
        self.name = name
        self.socketPath = socketPath
    }

    var summary: Summary { Summary(agents: agents) }

    func start() {
        reconnectTask?.cancel()
        attemptConnect()
    }

    func stop() {
        reconnectTask?.cancel(); reconnectTask = nil
        client?.disconnect(); client = nil
        connected = false
    }

    private func attemptConnect() {
        let c = HerdrClient(socketPath: socketPath)
        // HerdrClient delivers callbacks on the main queue.
        c.onEvent = { [weak self] event, _ in
            MainActor.assumeIsolated { self?.handle(event: event) }
        }
        c.onDisconnect = { [weak self] err in
            MainActor.assumeIsolated { self?.handleDisconnect(err) }
        }
        do {
            try c.connect()
            client = c
            connected = true
            lastError = nil
            reconnectDelay = 1
            Task { await self.bootstrap() }
        } catch {
            connected = false
            lastError = error.localizedDescription
            scheduleReconnect()
        }
    }

    private func bootstrap() async {
        guard let client else { return }
        let subs: [[String: Any]] = [
            ["type": "pane.updated"], ["type": "pane.created"], ["type": "pane.closed"],
            ["type": "pane.agent_detected"], ["type": "pane.exited"],
            ["type": "workspace.created"], ["type": "workspace.updated"], ["type": "workspace.closed"],
            ["type": "workspace.renamed"], ["type": "workspace.focused"],
            ["type": "tab.created"], ["type": "tab.closed"],
        ]
        do {
            _ = try await client.request("events.subscribe", params: ["subscriptions": subs])
        } catch {
            lastError = "subscribe failed: \(error.localizedDescription)"
        }
        await refetch()
    }

    private func handle(event: String) {
        // Any structural or status change → refetch snapshot (debounced). Simpler than patching.
        scheduleRefetch()
    }

    private func handleDisconnect(_ error: Error?) {
        connected = false
        client = nil
        lastError = error?.localizedDescription ?? "Herdr server is not running"
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.attemptConnect()
        }
    }

    private func scheduleRefetch() {
        guard !refetchScheduled else { return }
        refetchScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            refetchScheduled = false
            await refetch()
        }
    }

    func refetch() async {
        do {
            let result = try await HerdrClient.call(socketPath: socketPath, method: "session.snapshot")
            guard let snap = result["snapshot"] else { return }
            let data = try JSONSerialization.data(withJSONObject: snap)
            let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
            apply(decoded)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func apply(_ snap: SessionSnapshot) {
        let now = Date()
        var since = statusSince
        var last = lastStatus
        let known = Set(snap.agents.map(\.paneID))
        for a in snap.agents {
            let prev = last[a.paneID]
            if prev != a.agentStatus {
                last[a.paneID] = a.agentStatus
                // Herdr exposes no timestamp, so "since" is only known for transitions we observed.
                if prev != nil {
                    since[a.paneID] = now
                    onTransition?(a, prev)
                }
            }
        }
        for key in Array(since.keys) where !known.contains(key) { since[key] = nil; last[key] = nil }
        statusSince = since
        lastStatus = last
        agents = snap.agents
        workspaces = snap.workspaces
    }

    // MARK: actions

    func read(agent: AgentInfo, lines: Int = 3) async -> String? {
        guard let r = try? await HerdrClient.call(socketPath: socketPath, method: "agent.read", params: [
            "target": agent.paneID, "source": "recent", "lines": lines, "strip_ansi": true, "format": "text",
        ]) else { return nil }
        if let read = r["read"] as? [String: Any] {
            if let text = read["text"] as? String { return text }
            if let lines = read["lines"] as? [String] { return lines.joined(separator: "\n") }
        }
        if let text = r["text"] as? String { return text }
        if let lines = r["lines"] as? [String] { return lines.joined(separator: "\n") }
        return nil
    }
}

/// Discovers Herdr sessions (default + named) and owns one HerdrSession each.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [HerdrSession] = []
    private var discoveryTask: Task<Void, Never>?
    var onTransition: ((HerdrSession, AgentInfo, AgentStatus?) -> Void)?

    var agents: [AgentInfo] { sessions.flatMap(\.agents) }
    var anyConnected: Bool { sessions.contains { $0.connected } }
    var summary: Summary { Summary(agents: agents) }

    var iconState: StatusIconState {
        guard anyConnected else { return .disconnected }
        let s = summary
        if s.blocked > 0 { return .blocked }
        if s.working > 0 { return .working }
        return .idle
    }

    func start() {
        discoveryTask = Task { [weak self] in
            await self?.discover()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await self?.discover()
            }
        }
    }

    /// `herdr session list --json`, with the default socket as a fallback.
    func discover() async {
        let entries = await Task.detached(priority: .utility) { SessionDiscovery.list() }.value
        apply(discovered: entries)
    }

    private func apply(discovered: [HerdrSessionEntry]) {
        var entries = discovered
        if entries.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            entries = [HerdrSessionEntry(name: "default", running: true,
                                          socketPath: home + "/.config/herdr/herdr.sock", isDefault: true)]
        }
        let wanted = entries.filter(\.running)
        let wantedPaths = Set(wanted.map(\.socketPath))
        // drop sessions that disappeared
        for s in sessions where !wantedPaths.contains(s.socketPath) { s.stop() }
        sessions.removeAll { !wantedPaths.contains($0.socketPath) }
        // add new ones
        let have = Set(sessions.map(\.socketPath))
        for e in wanted where !have.contains(e.socketPath) {
            let s = HerdrSession(name: e.name, socketPath: e.socketPath)
            s.onTransition = { [weak self, weak s] agent, prev in
                guard let s else { return }
                self?.onTransition?(s, agent, prev)
            }
            s.start()
            sessions.append(s)
        }
        sessions.sort { ($0.name == "default" ? 0 : 1, $0.name) < ($1.name == "default" ? 0 : 1, $1.name) }
    }

    func refetchAll() async {
        for s in sessions { await s.refetch() }
    }
}

enum SessionDiscovery {
    static func herdrBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [home + "/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func list() -> [HerdrSessionEntry] {
        guard let bin = herdrBinary() else { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["session", "list", "--json"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        struct Wrapper: Codable { let sessions: [HerdrSessionEntry] }
        return (try? JSONDecoder().decode(Wrapper.self, from: data))?.sessions ?? []
    }
}
