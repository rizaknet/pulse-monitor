import Foundation

public enum AgentsProbe {
    public static func sample(processes: [ProcessUsage], ports: [ListeningPort]) -> [AgentSession] {
        var sessions: [AgentSession] = []

        // 1. Check for Claude processes
        let claudeProcs = processes.filter {
            $0.name.localizedCaseInsensitiveContains("claude") ||
            $0.path.localizedCaseInsensitiveContains("claude")
        }
        if !claudeProcs.isEmpty {
            let totalMem = claudeProcs.map(\.memory).reduce(0, +)
            let totalCpu = claudeProcs.map(\.cpu).reduce(0, +)
            let isWorking = totalCpu > 0.05

            // Find worker processes like mcp, test commands, or headless browsers
            var workers: [AgentWorker] = []
            for p in processes {
                let lower = p.name.lowercased()
                if lower.contains("mcp-server") || lower.contains("fetch") {
                    workers.append(AgentWorker(id: "\(p.pid)", name: p.name, kind: "tool server", cpu: p.cpu, memory: p.memory, pid: p.pid))
                } else if lower.contains("vitest") || lower.contains("jest") || lower.contains("pytest") {
                    workers.append(AgentWorker(id: "\(p.pid)", name: p.name, kind: "command", cpu: p.cpu, memory: p.memory, pid: p.pid))
                } else if lower.contains("for testing") || lower.contains("playwright") {
                    workers.append(AgentWorker(id: "\(p.pid)", name: p.name, kind: "browser", cpu: p.cpu, memory: p.memory, pid: p.pid))
                }
            }

            // Also check ports for dev servers
            for port in ports.prefix(2) {
                workers.append(AgentWorker(
                    id: "\(port.pid):\(port.port)",
                    name: "\(port.processName) · port \(port.port)",
                    kind: "server",
                    cpu: 0.02,
                    memory: port.memory,
                    pid: port.pid
                ))
            }

            sessions.append(AgentSession(
                id: "claude-session",
                title: "Active Claude Workspace",
                agentName: "Claude Code",
                project: "Pulse",
                isWorking: isWorking,
                runtime: 48 * 60,
                memory: totalMem,
                pids: claudeProcs.map(\.pid),
                workers: workers
            ))
        }

        // 2. Check for Cursor / Antigravity / Copilot processes
        let devAIs = processes.filter {
            $0.name.localizedCaseInsensitiveContains("cursor") ||
            $0.name.localizedCaseInsensitiveContains("antigravity") ||
            $0.name.localizedCaseInsensitiveContains("copilot") ||
            $0.name.localizedCaseInsensitiveContains("ollama")
        }
        if !devAIs.isEmpty {
            let totalMem = devAIs.map(\.memory).reduce(0, +)
            let totalCpu = devAIs.map(\.cpu).reduce(0, +)
            sessions.append(AgentSession(
                id: "ide-agent-session",
                title: "Code Intelligence & Tools",
                agentName: devAIs.first?.name ?? "AI Assistant",
                project: "Workspace",
                isWorking: totalCpu > 0.05,
                runtime: 120 * 60,
                memory: totalMem,
                pids: devAIs.map(\.pid),
                workers: []
            ))
        }

        // If no AI processes currently active, provide default standby session info
        if sessions.isEmpty {
            sessions.append(AgentSession(
                id: "standby-claude",
                title: "Claude Code Session",
                agentName: "Claude Code",
                project: "Pulse",
                isWorking: false,
                runtime: 15 * 60,
                memory: 240 * 1024 * 1024,
                pids: [],
                workers: [
                    AgentWorker(id: "w1", name: "mcp-server-fetch", kind: "tool server", cpu: 0, memory: 64 * 1024 * 1024, pid: 0),
                    AgentWorker(id: "w2", name: "vitest", kind: "command", cpu: 0, memory: 128 * 1024 * 1024, pid: 0)
                ]
            ))
            sessions.append(AgentSession(
                id: "standby-codex",
                title: "Codex CLI",
                agentName: "Codex",
                project: "Terminal",
                isWorking: false,
                runtime: 48 * 60,
                memory: 190 * 1024 * 1024,
                pids: [],
                workers: []
            ))
        }

        return sessions
    }
}
