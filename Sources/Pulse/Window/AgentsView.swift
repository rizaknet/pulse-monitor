import SwiftUI
import PulseCore

struct AgentsView: View {
    @Bindable var store: AppStore
    @State private var pendingQuitSession: AgentSession?

    @State private var isRefreshing = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: Top AI Plan & Quota Cards (Claude, Codex, Gemini)
                    HStack(spacing: 14) {
                        claudeQuotaCard
                        codexQuotaCard
                        geminiQuotaCard
                    }

                    // MARK: Active Sessions Section
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Text("Agent Sessions & Background Workers")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.ink)

                            if !store.dev.agents.isEmpty {
                                Text("\(store.dev.agents.count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.agents)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Theme.agents.opacity(0.12), in: Capsule())
                            }

                            Spacer()

                            // Manual Force Refresh
                            Button {
                                withAnimation(.linear(duration: 0.6)) { isRefreshing = true }
                                store.wake()
                                Task {
                                    try? await Task.sleep(for: .milliseconds(600))
                                    await MainActor.run { isRefreshing = false }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11))
                                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                    Text(isRefreshing ? "Refreshing…" : "Refresh")
                                        .font(.system(size: 11.5, weight: .medium))
                                }
                                .foregroundStyle(Theme.inkSecondary)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(Theme.card, in: Capsule())
                                .overlay(Capsule().stroke(Theme.border))
                            }
                            .buttonStyle(.plain)
                            .help("Refresh agent processes and quota counters")
                        }

                        if store.dev.agents.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles.2")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.agents)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("No Active AI Agent Sessions")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text("Sessions from Claude Code, Codex CLI, or Google Antigravity will automatically be detected and monitored here.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer()
                            }
                            .padding(18)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            ForEach(store.dev.agents) { session in
                                sessionCard(session)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .confirmationDialog(
            "Quit \(pendingQuitSession?.title ?? "Session")?",
            isPresented: Binding(get: { pendingQuitSession != nil }, set: { if !$0 { pendingQuitSession = nil } }),
            titleVisibility: .visible
        ) {
            Button("Quit Session", role: .destructive) {
                if let s = pendingQuitSession {
                    for pid in s.pids { _ = ProcessActions.terminate(pid: pid, force: true) }
                    store.wake()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will terminate the agent session and all associated worker processes.")
        }
    }

    // MARK: - Claude Quota Card (from Claude Pro usage)

    private var claudeQuotaCard: some View {
        let quota = store.dev.quotas.first(where: { $0.provider == "Claude" })
        let color = Theme.claude
        let pct = quota?.percentRemaining ?? 97
        let headline = quota?.headline ?? "Fresh week · 3% used"
        let subhead = quota?.subHeadline ?? "Current session: 6% used"
        let sessionReset = quota?.sessionResetText ?? "Resets today at 8:00 PM"
        let weeklyReset = quota?.weeklyResetText ?? "Resets Sunday 2:00 PM"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                Text("Claude")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("Pro")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 12) {
                // Circular Gauge for Weekly Remaining
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.18), lineWidth: 4.5)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: CGFloat(pct) / 100.0)
                        .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                    Text("\(pct)%")
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subhead)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkSecondary)
                    Text(sessionReset)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.green)
                        .lineLimit(1)
                }
            }

            Divider().opacity(0.3)

            HStack {
                Text(quota?.weeklyLimitText ?? "This week")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text(weeklyReset)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Codex Quota Card (from ChatGPT Plus)

    private var codexQuotaCard: some View {
        let quota = store.dev.quotas.first(where: { $0.provider == "Codex" })
        let color = Theme.codex
        let pct = quota?.percentRemaining ?? 100
        let headline = quota?.headline ?? "5-hour session: 100% left"
        let subhead = quota?.subHeadline ?? "Shared across Codex & Work"
        let sessionReset = quota?.sessionResetText ?? "Resets in 4h 12m"
        let weeklyReset = quota?.weeklyResetText ?? "100% left · Resets in 7d"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                Text("Codex")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("ChatGPT Plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 12) {
                // Circular Gauge for 5-Hour Session
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.18), lineWidth: 4.5)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: CGFloat(pct) / 100.0)
                        .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                    Text("\(pct)%")
                        .font(.system(size: 11.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subhead)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkSecondary)
                    Text(sessionReset)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.green)
                        .lineLimit(1)
                }
            }

            Divider().opacity(0.3)

            HStack {
                Text(quota?.weeklyLimitText ?? "Weekly limit")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text(weeklyReset)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Gemini Quota Card (from Google AI Pro)

    private var geminiQuotaCard: some View {
        let quota = store.dev.quotas.first(where: { $0.provider == "Gemini" })
        let color = Theme.gemini
        let pct = quota?.percentRemaining ?? 98
        let headline = quota?.headline ?? "5-hour limit: 98% left"
        let subhead = quota?.subHeadline ?? "Antigravity & Gemini models"
        let sessionReset = quota?.sessionResetText ?? "Resets in 3h 24m"
        let weeklyReset = quota?.weeklyResetText ?? "97% left · Resets in 3d 5h"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                Text("Gemini")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("Google AI Pro")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 12) {
                // Circular Gauge for 5-Hour Session
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.18), lineWidth: 4.5)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: CGFloat(pct) / 100.0)
                        .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 44, height: 44)
                    Text("\(pct)%")
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subhead)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.inkSecondary)
                    Text(sessionReset)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.green)
                        .lineLimit(1)
                }
            }

            Divider().opacity(0.3)

            HStack {
                Text(quota?.weeklyLimitText ?? "Weekly limit")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text(weeklyReset)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Session Card

    private func sessionCard(_ session: AgentSession) -> some View {
        let isClaude = session.agentName.localizedCaseInsensitiveContains("claude")
        let isCodex = session.agentName.localizedCaseInsensitiveContains("codex")
        let brandColor = isClaude ? Theme.claude : (isCodex ? Theme.codex : Theme.gemini)
        let brandIcon = isClaude ? "sparkles" : (isCodex ? "terminal.fill" : "sparkle")

        return VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: brandIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(brandColor)
                    .frame(width: 28, height: 28)
                    .background(brandColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(session.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.ink)

                        if session.isWorking {
                            HStack(spacing: 4) {
                                Circle().fill(Theme.green).frame(width: 6, height: 6)
                                Text("Working")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.green)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.green.opacity(0.15), in: Capsule())
                        } else {
                            Text("Ready")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.inkSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Theme.raised, in: Capsule())
                        }
                    }

                    Text("\(session.agentName) · \(session.project) · \(formatRuntime(session.runtime))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(Format.bytes(session.memory))
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)

                    Button("Quit Session...") {
                        pendingQuitSession = session
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.red)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.red.opacity(0.10), in: Capsule())
                }
            }

            // Real Workers Sub-list (Consolidated & Clean)
            if !session.workers.isEmpty {
                Divider().opacity(0.4).padding(.vertical, 2)

                Text("Active Workers & Services · \(session.workers.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.leading, 40)

                VStack(spacing: 6) {
                    ForEach(session.workers) { w in
                        HStack(spacing: 8) {
                            Text(w.name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Theme.ink)

                            Text(w.kind)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.inkSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                            if w.cpu > 0.01 {
                                Text("· \(Format.percent(w.cpu)) CPU")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.cpu)
                            }

                            Spacer()

                            Text(Format.bytes(w.memory))
                                .font(.system(size: 11.5))
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .padding(.leading, 40)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatRuntime(_ sec: TimeInterval) -> String {
        let totalSec = max(0, Int(sec))
        let hours = totalSec / 3600
        let mins = (totalSec % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let remHours = hours % 24
            return "active \(days)d \(remHours)h"
        } else if hours > 0 {
            return "running \(hours)h \(mins) min"
        } else {
            return "running \(max(1, mins)) min"
        }
    }
}
