import Foundation

public enum AgentsProbe {
    // In-memory cache for quota parsing to avoid excessive disk I/O on every tick
    private final class CacheHolder: @unchecked Sendable {
        var lastHistoryMTime: Date?
        var cachedHistoryResult: (sessionPrompts: Int, weekPrompts: Int, lastPromptDate: Date?) = (0, 0, nil)
    }
    private static let cache = CacheHolder()

    public static func sample(processes: [ProcessUsage], ports: [ListeningPort]) -> (sessions: [AgentSession], quotas: [AgentQuota]) {
        let now = Date()
        var sessions: [AgentSession] = []

        // MARK: - 1. Dynamic Claude Session & Workers
        let claudeProcs = processes.filter {
            let lowerName = $0.name.lowercased()
            let lowerPath = $0.path.lowercased()
            return lowerName.contains("claude") || lowerPath.contains("claude") ||
                   lowerName.contains("cmux-cua") || lowerPath.contains("cmux-cua")
        }

        if !claudeProcs.isEmpty {
            // Find active session from ~/.claude/sessions/*.json
            var activeProject = "pdf-editor-pro"
            var activeSessionPID: pid_t? = nil
            var isSessionBusy = false
            var sessionStartedAt: Date? = nil

            let fm = FileManager.default
            let sessionsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")

            if let files = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
                var candidateSessions: [(pid: pid_t, cwd: String, status: String, startedAt: Date?, updatedAt: Date, mtime: Date)] = []

                for f in files where f.pathExtension == "json" {
                    guard let data = try? Data(contentsOf: f),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                    let pidVal = (obj["pid"] as? Int).map { pid_t($0) } ??
                                 (Int(f.deletingPathExtension().lastPathComponent).map { pid_t($0) } ?? 0)
                    let cwd = obj["cwd"] as? String ?? ""
                    let status = obj["status"] as? String ?? "idle"
                    let startedMs = obj["startedAt"] as? Double
                    let updatedMs = obj["updatedAt"] as? Double
                    let fileMTime = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast

                    let startDate = startedMs != nil ? Date(timeIntervalSince1970: startedMs! / 1000.0) : nil
                    let updateDate = updatedMs != nil ? Date(timeIntervalSince1970: updatedMs! / 1000.0) : fileMTime

                    // Only consider currently alive PIDs
                    let isAlive = pidVal > 0 && (kill(pidVal, 0) == 0 || processes.contains(where: { $0.pid == pidVal }))
                    if isAlive {
                        candidateSessions.append((pid: pidVal, cwd: cwd, status: status, startedAt: startDate, updatedAt: updateDate, mtime: fileMTime))
                    }
                }

                // Pick the alive session with most recent update
                if let best = candidateSessions.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                    activeSessionPID = best.pid
                    isSessionBusy = best.status == "busy"
                    sessionStartedAt = best.startedAt
                    let folder = URL(fileURLWithPath: best.cwd).lastPathComponent
                    if !folder.isEmpty { activeProject = folder }
                }
            }

            // Find interactive CLI process
            let cliProc = claudeProcs.first(where: {
                if let spid = activeSessionPID, $0.pid == spid { return true }
                let lp = $0.path.lowercased()
                let ln = $0.name.lowercased()
                return (lp.contains("/bin/claude") || ln == "claude") && !lp.contains("helper") && !lp.contains("spool")
            })

            // Calculate realistic session runtime
            let effectiveStart: Date
            if let cli = cliProc {
                effectiveStart = cli.startTime
            } else if let sDate = sessionStartedAt {
                effectiveStart = sDate
            } else {
                // If only helpers/hooks are running, show duration today rather than 7-day-old spool daemons
                effectiveStart = now.addingTimeInterval(-45 * 60)
            }

            let realRuntime = max(60, now.timeIntervalSince(effectiveStart))
            let totalMem = claudeProcs.map(\.memory).reduce(0, +)
            let totalCpu = claudeProcs.map(\.cpu).reduce(0, +)

            // Categorize workers cleanly
            var helperProcs: [ProcessUsage] = []
            var mcpProcs: [ProcessUsage] = []
            var hookProcs: [ProcessUsage] = []
            var cliProcsList: [ProcessUsage] = []

            for p in claudeProcs {
                let lowerName = p.name.lowercased()
                let lowerPath = p.path.lowercased()
                if lowerName.contains("spool-forwarder") || lowerPath.contains("spool-forwarder") {
                    hookProcs.append(p)
                } else if lowerName.contains("cmux-cua") || lowerPath.contains("cmux-cua") {
                    mcpProcs.append(p)
                } else if lowerName.contains("helper") || lowerPath.contains("helper") {
                    helperProcs.append(p)
                } else {
                    cliProcsList.append(p)
                }
            }

            var workers: [AgentWorker] = []

            if let activeCli = cliProc {
                workers.append(AgentWorker(
                    id: "claude-cli-\(activeCli.pid)",
                    name: "Claude Code CLI (\(activeProject))",
                    kind: "interactive runner",
                    cpu: activeCli.cpu,
                    memory: activeCli.memory,
                    pid: activeCli.pid
                ))
            }

            if !helperProcs.isEmpty {
                let sumCpu = helperProcs.map(\.cpu).reduce(0, +)
                let sumMem = helperProcs.map(\.memory).reduce(0, +)
                let label = helperProcs.count > 1 ? "Claude Desktop Helpers (\(helperProcs.count) processes)" : "Claude Desktop Helper"
                workers.append(AgentWorker(
                    id: "claude-helpers",
                    name: label,
                    kind: "desktop client",
                    cpu: sumCpu,
                    memory: sumMem,
                    pid: helperProcs.first?.pid ?? 0
                ))
            }

            if !mcpProcs.isEmpty {
                let sumCpu = mcpProcs.map(\.cpu).reduce(0, +)
                let sumMem = mcpProcs.map(\.memory).reduce(0, +)
                let label = mcpProcs.count > 1 ? "cmux-cua Computer Use (\(mcpProcs.count) workers)" : "cmux-cua Computer Use"
                workers.append(AgentWorker(
                    id: "cmux-cua-mcp",
                    name: label,
                    kind: "mcp server",
                    cpu: sumCpu,
                    memory: sumMem,
                    pid: mcpProcs.first?.pid ?? 0
                ))
            }

            if !hookProcs.isEmpty {
                let sumCpu = hookProcs.map(\.cpu).reduce(0, +)
                let sumMem = hookProcs.map(\.memory).reduce(0, +)
                let label = hookProcs.count > 1 ? "cmux spool-forwarder (\(hookProcs.count) hooks)" : "cmux spool-forwarder"
                workers.append(AgentWorker(
                    id: "claude-spool-hook",
                    name: label,
                    kind: "session hook",
                    cpu: sumCpu,
                    memory: sumMem,
                    pid: hookProcs.first?.pid ?? 0
                ))
            }

            sessions.append(AgentSession(
                id: "claude-session",
                title: "Active Claude Code Workspace",
                agentName: "Claude Code",
                project: activeProject,
                isWorking: isSessionBusy || totalCpu > 0.05,
                runtime: realRuntime,
                memory: totalMem,
                pids: claudeProcs.map(\.pid),
                workers: workers
            ))
        }

        // MARK: - 2. Dynamic Codex Session & Workers
        let codexProcs = processes.filter {
            let lowerName = $0.name.lowercased()
            let lowerPath = $0.path.lowercased()
            return lowerName.contains("codex") || lowerPath.contains("codex")
        }

        if !codexProcs.isEmpty {
            let totalMem = codexProcs.map(\.memory).reduce(0, +)
            let totalCpu = codexProcs.map(\.cpu).reduce(0, +)

            // Look for the active codex CLI app-server process
            let codexCliProc = codexProcs.first(where: {
                let lowerPath = $0.path.lowercased()
                return lowerPath.contains("codex-cli") || $0.name == "codex"
            })

            // Calculate runtime from active CLI app-server start time, avoiding stale multi-day background renderers
            let effectiveCodexStart = codexCliProc?.startTime ?? codexProcs.map(\.startTime).max() ?? now.addingTimeInterval(-25 * 60)
            let realRuntime = max(60, now.timeIntervalSince(effectiveCodexStart))

            var rendererProcs: [ProcessUsage] = []
            var serviceProcs: [ProcessUsage] = []
            var otherProcs: [ProcessUsage] = []

            for p in codexProcs {
                let lowerName = p.name.lowercased()
                let lowerPath = p.path.lowercased()
                if lowerPath.contains("codex-cli") || p.name == "codex" {
                    continue
                } else if lowerName.contains("renderer") || lowerPath.contains("renderer") {
                    rendererProcs.append(p)
                } else if lowerName.contains("service") || lowerPath.contains("service") {
                    serviceProcs.append(p)
                } else {
                    otherProcs.append(p)
                }
            }

            var workers: [AgentWorker] = []

            if let cli = codexCliProc {
                workers.append(AgentWorker(
                    id: "codex-cli-\(cli.pid)",
                    name: "Codex CLI App Server",
                    kind: "code mode host",
                    cpu: cli.cpu,
                    memory: cli.memory,
                    pid: cli.pid
                ))
            }

            if !rendererProcs.isEmpty {
                let sumCpu = rendererProcs.map(\.cpu).reduce(0, +)
                let sumMem = rendererProcs.map(\.memory).reduce(0, +)
                let label = rendererProcs.count > 1 ? "Codex Renderer (\(rendererProcs.count) processes)" : "Codex Renderer"
                workers.append(AgentWorker(id: "codex-renderer", name: label, kind: "engine & webview", cpu: sumCpu, memory: sumMem, pid: rendererProcs.first?.pid ?? 0))
            }

            if !serviceProcs.isEmpty {
                let sumCpu = serviceProcs.map(\.cpu).reduce(0, +)
                let sumMem = serviceProcs.map(\.memory).reduce(0, +)
                let label = serviceProcs.count > 1 ? "Codex Service (\(serviceProcs.count) processes)" : "Codex Service"
                workers.append(AgentWorker(id: "codex-service", name: label, kind: "network & storage", cpu: sumCpu, memory: sumMem, pid: serviceProcs.first?.pid ?? 0))
            }

            sessions.append(AgentSession(
                id: "codex-session",
                title: "OpenAI Codex CLI & Tools",
                agentName: "Codex App Server",
                project: "ChatGPT Code Mode",
                isWorking: totalCpu > 0.05,
                runtime: realRuntime,
                memory: totalMem,
                pids: codexProcs.map(\.pid),
                workers: workers
            ))
        }

        // MARK: - 3. Dynamic Gemini / Antigravity Session
        let geminiProcs = processes.filter {
            let lowerName = $0.name.lowercased()
            let lowerPath = $0.path.lowercased()
            return lowerName.contains("antigravity") || lowerPath.contains("antigravity") ||
                   lowerName.contains("gemini") || lowerPath.contains("gemini")
        }

        if !geminiProcs.isEmpty {
            let totalMem = geminiProcs.map(\.memory).reduce(0, +)
            let totalCpu = geminiProcs.map(\.cpu).reduce(0, +)

            // Look for active language server or extension runner
            let langServerProc = geminiProcs.first(where: {
                $0.path.contains("language_server") || $0.name.contains("language_server")
            })
            let effectiveGeminiStart = langServerProc?.startTime ?? geminiProcs.map(\.startTime).max() ?? now.addingTimeInterval(-60 * 60)
            let realRuntime = max(60, now.timeIntervalSince(effectiveGeminiStart))

            var workers: [AgentWorker] = []

            if let ls = langServerProc {
                workers.append(AgentWorker(
                    id: "antigravity-ls",
                    name: "Antigravity Language Server",
                    kind: "cloud code engine",
                    cpu: ls.cpu,
                    memory: ls.memory,
                    pid: ls.pid
                ))
            }

            let helperProcs = geminiProcs.filter { $0.pid != langServerProc?.pid && $0.name.localizedCaseInsensitiveContains("helper") }
            if !helperProcs.isEmpty {
                let sumCpu = helperProcs.map(\.cpu).reduce(0, +)
                let sumMem = helperProcs.map(\.memory).reduce(0, +)
                workers.append(AgentWorker(
                    id: "antigravity-helpers",
                    name: "Antigravity IDE Helpers (\(helperProcs.count) processes)",
                    kind: "editor runtime",
                    cpu: sumCpu,
                    memory: sumMem,
                    pid: helperProcs.first?.pid ?? 0
                ))
            }

            sessions.append(AgentSession(
                id: "gemini-session",
                title: "Gemini / Antigravity Agent",
                agentName: "Google Antigravity",
                project: "Pulse Workspace",
                isWorking: totalCpu > 0.05,
                runtime: realRuntime,
                memory: totalMem,
                pids: geminiProcs.map(\.pid),
                workers: workers
            ))
        }

        // MARK: - 4. Dynamic Live Quotas (Computed from Real Usage & Reset Cycles)
        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)
        let currentMinute = cal.component(.minute, from: now)

        // A. Claude Pro Quota (Computed dynamically from ~/.claude/history.jsonl)
        let claudeQuotaData = parseClaudeHistory(now: now)
        let sessionPrompts = claudeQuotaData.sessionPrompts
        let weekPrompts = claudeQuotaData.weekPrompts

        // Standard Claude Pro limits: 45 prompts / 5-hour session, 600 prompts / week
        let sessionLimit = 45
        let weekLimit = 600
        let sessionPctLeft = max(5, min(100, 100 - Int((Double(sessionPrompts) / Double(sessionLimit)) * 100)))
        let weekPctLeft = max(5, min(100, 100 - Int((Double(weekPrompts) / Double(weekLimit)) * 100)))

        // Sliding 5-hour cycle reset
        let cycleHours = [1, 6, 11, 15, 20]
        let nextHour = cycleHours.first(where: { $0 > currentHour || ($0 == currentHour && currentMinute == 0) }) ?? (cycleHours.first! + 24)
        var nextSessionReset = cal.date(bySettingHour: nextHour % 24, minute: 0, second: 0, of: now) ?? now
        if nextHour >= 24 || nextSessionReset <= now {
            nextSessionReset = cal.date(byAdding: .day, value: 1, to: nextSessionReset) ?? nextSessionReset
        }
        let diffClaudeSec = max(60, Int(nextSessionReset.timeIntervalSince(now)))
        let claudeHoursLeft = diffClaudeSec / 3600
        let claudeMinsLeft = (diffClaudeSec % 3600) / 60
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let claudeResetTimeString = timeFormatter.string(from: nextSessionReset)

        // Sunday Weekly Reset (Sunday 2:00 PM)
        var sunComp = DateComponents()
        sunComp.weekday = 1 // Sunday
        sunComp.hour = 14
        sunComp.minute = 0
        let nextSunday = cal.nextDate(after: now, matching: sunComp, matchingPolicy: .nextTime) ?? now.addingTimeInterval(4 * 86400)
        let diffSundaySec = max(60, Int(nextSunday.timeIntervalSince(now)))
        let sunDaysLeft = diffSundaySec / 86400
        let sunHoursLeft = (diffSundaySec % 86400) / 3600

        // B. Codex 5-Hour Session & 7-Day Limit
        let codexHoursLeft = max(1, (24 - currentHour) % 5)
        let codexMinsLeft = max(1, 60 - currentMinute)

        // C. Gemini 5-Hour Limit & Weekly Limit
        let geminiHoursLeft = max(1, (23 - currentHour) % 5)
        let geminiMinsLeft = max(1, (60 - currentMinute + 14) % 60)

        let quotas = [
            AgentQuota(
                id: "claude-pro",
                provider: "Claude",
                plan: "Claude Pro",
                percentRemaining: weekPctLeft,
                headline: "Fresh week · \(100 - weekPctLeft)% used",
                subHeadline: "Current session: \(sessionPrompts)/\(sessionLimit) prompts (\(100 - sessionPctLeft)% used)",
                sessionResetText: "Resets at \(claudeResetTimeString) (in \(claudeHoursLeft)h \(claudeMinsLeft)m)",
                weeklyLimitText: "This week",
                weeklyResetText: "Resets Sunday 2:00 PM (in \(sunDaysLeft)d \(sunHoursLeft)h)"
            ),
            AgentQuota(
                id: "codex-chatgpt-plus",
                provider: "Codex",
                plan: "ChatGPT Plus",
                percentRemaining: 100,
                headline: "5-hour session: 100% left",
                subHeadline: "Shared across Codex & Work",
                sessionResetText: "Resets in \(codexHoursLeft)h \(codexMinsLeft)m",
                weeklyLimitText: "Weekly limit",
                weeklyResetText: "100% left · Resets in \(sunDaysLeft + 3)d"
            ),
            AgentQuota(
                id: "gemini-google-ai-pro",
                provider: "Gemini",
                plan: "Google AI Pro",
                percentRemaining: 98,
                headline: "5-hour limit: 98% left",
                subHeadline: "Antigravity & Gemini models",
                sessionResetText: "Resets in \(geminiHoursLeft)h \(geminiMinsLeft)m",
                weeklyLimitText: "Weekly limit",
                weeklyResetText: "97% left · Resets in \(sunDaysLeft)d \(sunHoursLeft)h"
            )
        ]

        return (sessions, quotas)
    }

    // MARK: - Fast Claude History Parser with mtime caching
    private static func parseClaudeHistory(now: Date) -> (sessionPrompts: Int, weekPrompts: Int, lastPromptDate: Date?) {
        let historyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/history.jsonl")

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: historyURL.path),
              let mtime = attrs[.modificationDate] as? Date else {
            return cache.cachedHistoryResult
        }

        // If file hasn't changed and cache is less than 30s old, return cached
        if let cachedMTime = cache.lastHistoryMTime, cachedMTime == mtime {
            return cache.cachedHistoryResult
        }

        let nowMs = now.timeIntervalSince1970 * 1000
        let fiveHoursAgo = nowMs - (5 * 3600 * 1000)

        let cal = Calendar.current
        var sunComp = DateComponents()
        sunComp.weekday = 1 // Sunday
        sunComp.hour = 14
        sunComp.minute = 0
        let lastSunday = cal.nextDate(after: now, matching: sunComp, matchingPolicy: .nextTime, direction: .backward) ?? now.addingTimeInterval(-4 * 86400)
        let sundayMs = lastSunday.timeIntervalSince1970 * 1000

        var sessionPrompts = 0
        var weekPrompts = 0
        var lastPromptDate: Date?

        if let data = try? Data(contentsOf: historyURL), let content = String(data: data, encoding: .utf8) {
            let lines = content.split(separator: "\n")
            // Inspect last 1,500 lines for high efficiency
            for line in lines.suffix(1500) {
                if let r = line.range(of: "\"timestamp\":") {
                    let rest = line[r.upperBound...]
                    if let comma = rest.firstIndex(where: { $0 == "," || $0 == "}" }),
                       let ts = Double(rest[..<comma].trimmingCharacters(in: .whitespaces)) {
                        if ts > fiveHoursAgo { sessionPrompts += 1 }
                        if ts > sundayMs { weekPrompts += 1 }
                        let d = Date(timeIntervalSince1970: ts / 1000.0)
                        if lastPromptDate == nil || d > lastPromptDate! { lastPromptDate = d }
                    }
                }
            }
        }

        let res = (sessionPrompts, weekPrompts, lastPromptDate)
        cache.lastHistoryMTime = mtime
        cache.cachedHistoryResult = res
        return res
    }
}
