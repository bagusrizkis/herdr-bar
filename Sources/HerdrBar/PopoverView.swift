import SwiftUI

struct PopoverView: View {
    @Environment(SessionStore.self) private var store
    @AppStorage(Prefs.panelSort) private var panelSort = "spaces"
    @State private var peekPane: String?
    @State private var peekText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.anyConnected && !store.agents.isEmpty { modeToggle }
            Divider()
            // Size to content; only scroll when the estimated list height exceeds what the screen allows.
            // (MenuBarExtra proposes a small height, so ViewThatFits cannot be trusted here.)
            if estimatedListHeight > Self.maxListHeight {
                ScrollView { listContent }.frame(height: Self.maxListHeight)
            } else {
                listContent.fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .frame(width: 340)
        .task { await store.refetchAll() }
    }

    @ViewBuilder private var listContent: some View {
        if !store.anyConnected {
            emptyState(icon: "bolt.slash", title: "Herdr isn't running",
                       body: "No running session found. Start `herdr` in your terminal.")
        } else if store.agents.isEmpty {
            emptyState(icon: "circle.dotted", title: "No agents yet",
                       body: "Run claude, codex, or opencode in a Herdr pane.")
        } else if panelSort == "priority" {
            priorityList
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.sessions) { session in
                    if session.connected { sessionSection(session) }
                }
            }
        }
    }

    /// Attention queue: one flat list, blocked first, then working, done, idle; workspace shown per row.
    private var priorityList: some View {
        let items: [(HerdrSession, AgentInfo, String)] = store.sessions.flatMap { session in
            session.connected ? session.agents.map { a in
                (session, a, session.workspaces.first { $0.workspaceID == a.workspaceID }?.label ?? a.workspaceID)
            } : []
        }.sorted { l, r in
            if l.1.agentStatus.priority != r.1.agentStatus.priority { return l.1.agentStatus.priority < r.1.agentStatus.priority }
            return l.2.localizedCaseInsensitiveCompare(r.2) == .orderedAscending
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.1.paneID) { idx, item in
                let (session, agent, ws) = item
                if idx == 0 || items[idx - 1].1.agentStatus != agent.agentStatus {
                    Text(agent.agentStatus.label.uppercased())
                        .font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(color(for: agent.agentStatus))
                        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
                }
                AgentRow(agent: agent, session: session, workspaceLabel: ws,
                         since: session.statusSince[agent.paneID],
                         isPeeking: peekPane == agent.paneID, peekText: peekText,
                         onPeek: { togglePeek(agent, session) })
            }
        }
        .padding(.bottom, 6)
    }

    /// Rough but stable estimate of the list height, used to decide whether to scroll.
    private var estimatedListHeight: CGFloat {
        guard store.anyConnected, !store.agents.isEmpty else { return 140 }
        var h: CGFloat = 8 + 34   // mode toggle
        if panelSort == "priority" {
            let statuses = Set(store.agents.map(\.agentStatus)).count
            h += CGFloat(statuses) * 26 + CGFloat(store.agents.count) * 48
            if let p = peekPane, store.agents.contains(where: { $0.paneID == p }) { h += 6 * 15 + 20 }
            return h
        }
        let multi = store.sessions.count > 1
        for session in store.sessions where session.connected {
            if multi { h += 26 }
            let grouped = Dictionary(grouping: session.agents, by: \.workspaceID)
            for ws in session.workspaces where grouped[ws.workspaceID] != nil {
                h += 30                                   // workspace header + divider
                for a in grouped[ws.workspaceID] ?? [] {
                    h += 48                               // row
                    if peekPane == a.paneID { h += 6 * 15 + 20 }
                }
            }
        }
        return h
    }

    /// Fill most of the screen instead of forcing a scroll at 460 pt.
    static var maxListHeight: CGFloat {
        let h = NSScreen.main?.visibleFrame.height ?? 800
        return max(400, h - 120)
    }

    // MARK: header

    private var header: some View {
        let s = store.summary
        return HStack(spacing: 8) {
            Circle().fill(store.anyConnected ? Color.green : Color.secondary).frame(width: 8, height: 8)
            Text(store.anyConnected ? "Herdr · \(s.total) agent" : "Not connected")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if store.anyConnected {
                HStack(spacing: 4) {
                    chip(s.working, .green); chip(s.blocked, .orange); chip(s.done, .purple); chip(s.idle, .secondary)
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
    }

    private var modeToggle: some View {
        Picker("", selection: $panelSort) {
            Text("Spaces").tag("spaces")
            Text("Priority").tag("priority")
        }
        .pickerStyle(.segmented).labelsHidden().controlSize(.small)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    @ViewBuilder private func chip(_ n: Int, _ color: Color) -> some View {
        if n > 0 {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text("\(n)").font(.caption.monospacedDigit())
            }
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().strokeBorder(.quaternary))
        }
    }

    // MARK: body

    private func sessionSection(_ session: HerdrSession) -> some View {
        let showSessionName = store.sessions.count > 1
        let grouped = Dictionary(grouping: session.agents, by: \.workspaceID)
        let workspaces = session.workspaces.filter { grouped[$0.workspaceID] != nil }
        return VStack(alignment: .leading, spacing: 0) {
            if showSessionName {
                Text(session.name.uppercased())
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 12).padding(.top, 8)
            }
            ForEach(Array(workspaces.enumerated()), id: \.element.workspaceID) { idx, ws in
                let agents = (grouped[ws.workspaceID] ?? []).sorted { $0.agentStatus.priority < $1.agentStatus.priority }
                if idx > 0 { Divider().padding(.leading, 12) }
                workspaceHeader(ws, agents: agents)
                ForEach(agents) { agent in
                    AgentRow(agent: agent, session: session, workspaceLabel: nil,
                             since: session.statusSince[agent.paneID],
                             isPeeking: peekPane == agent.paneID, peekText: peekText,
                             onPeek: { togglePeek(agent, session) })
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func workspaceHeader(_ ws: WorkspaceInfo, agents: [AgentInfo]) -> some View {
        let top = agents.map(\.agentStatus).min { $0.priority < $1.priority } ?? .idle
        return HStack {
            Text(ws.label.uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
            Spacer()
            Circle().fill(color(for: top)).frame(width: 6, height: 6)
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
    }

    private func togglePeek(_ agent: AgentInfo, _ session: HerdrSession) {
        if peekPane == agent.paneID { peekPane = nil; return }
        peekPane = agent.paneID
        peekText = "…"
        Task {
            let text = await session.read(agent: agent, lines: 60) ?? "(no output)"
            if peekPane == agent.paneID { peekText = Self.trimPeek(text) }
        }
    }

    /// Show the agent's last message(s): split the tail of the terminal into paragraphs (blank-line
    /// separated), drop TUI chrome (rules, boxes, prompt line, status bar, update notices), rejoin
    /// wrapped lines, and keep the last two paragraphs.
    static func trimPeek(_ text: String) -> String {
        let chrome: Set<Character> = ["─", "│", "┃", "╭", "╮", "╰", "╯", "┌", "┐", "└", "┘", "═", "║", "❯", "›", ">", " "]
        func isChrome(_ t: String) -> Bool {
            if t.contains("░") || t.contains("⏵⏵") { return true }
            if t.hasPrefix("❯") || t.hasPrefix("›") { return true }                      // prompt line
            if t.contains("Update installed") || t.contains("Restart to update") { return true }
            if t.allSatisfy({ c in chrome.contains(c) || (c.unicodeScalars.first.map { (0x2500...0x259F).contains($0.value) } ?? false) }) { return true }
            let nonSpace = t.filter { !$0.isWhitespace }
            let alnum = nonSpace.filter { $0.isLetter || $0.isNumber }.count
            return alnum < 3 || Double(alnum) / Double(max(nonSpace.count, 1)) < 0.3
        }
        var paragraphs: [[String]] = [[]]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { if !paragraphs.last!.isEmpty { paragraphs.append([]) }; continue }
            if isChrome(t) { continue }
            paragraphs[paragraphs.count - 1].append(t.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression))
        }
        let blocks = paragraphs.filter { !$0.isEmpty }.map { String($0.joined(separator: " ").prefix(320)) }
        let tail = blocks.suffix(2)
        return tail.isEmpty ? "(no output yet)" : tail.joined(separator: "\n")
    }

    // MARK: footer / empty

    private var footer: some View {
        HStack {
            Button("Settings…") { SettingsWindow.show() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .controlSize(.small)
    }

    private func emptyState(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(body).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32).padding(.horizontal, 20)
    }
}

func color(for status: AgentStatus) -> Color {
    switch status {
    case .working: .green
    case .blocked: .orange
    case .done: .purple
    case .idle, .unknown: .secondary
    }
}

struct AgentRow: View {
    let agent: AgentInfo
    let session: HerdrSession
    let workspaceLabel: String?
    let since: Date?
    let isPeeking: Bool
    let peekText: String
    let onPeek: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                // Align the dot with the title line, not the row's vertical center.
                Circle().fill(color(for: agent.agentStatus)).frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        if let workspaceLabel {
                            Text(workspaceLabel).font(.callout.weight(.medium)).lineLimit(1)
                            Text(agent.paneLabel).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        } else {
                            Text(agent.paneLabel).font(.callout.weight(.medium))
                        }
                        Text(agent.agent ?? "").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Text(agent.displayTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if hovering && agent.agentStatus != .working {
                    Button(isPeeking ? "Hide" : "Peek", action: onPeek)
                        .controlSize(.mini).buttonStyle(.bordered)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(agent.agentStatus.label).font(.caption2.weight(.medium))
                        if let since {
                            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                                Text(compactElapsed(from: since, to: ctx.date))
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if isPeeking {
                Text(peekText)
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(6).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
                    .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(hovering ? Color.accentColor.opacity(0.08) : .clear)
        .onHover { hovering = $0 }
    }
}

/// "44s", "10m", "1h 05m", "2d" — short enough for the row's trailing column.
func compactElapsed(from start: Date, to now: Date) -> String {
    let secs = max(0, Int(now.timeIntervalSince(start)))
    switch secs {
    case ..<60: return "\(secs)s"
    case ..<3600: return "\(secs / 60)m"
    case ..<86400: return String(format: "%dh %02dm", secs / 3600, (secs % 3600) / 60)
    default: return "\(secs / 86400)d"
    }
}
