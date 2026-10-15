import SwiftUI
import PulseCore

struct AgentsView: View {
    @Bindable var store: AppStore
    @State private var pendingQuitSession: AgentSession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: Top Gauges Row
                HStack(spacing: 12) {
                    agentGaugeCard(
                        name: "Claude",
                        icon: "sparkles",
                        percent: 72,
                        color: Color(hex: 0xEB6834),
                        period: "This week",
                        caption: "On pace · 10% to spare",
                        captionColor: Theme.green
                    )

                    agentGaugeCard(
                        name: "Codex",
                        icon: "terminal",
                        percent: 89,
                        color: Color(hex: 0x1BAF7A),
                        period: "5-hour session",
                        caption: "Resets in 3h 12m",
                        captionColor: Theme.inkSecondary
                    )

                    agentGaugeCard(
                        name: "GitHub Copilot",
                        icon: "chevron.left.forwardslash.chevron.right",
                        percent: 36,
                        color: Color(hex: 0x6366F1),
                        period: "Premium requests",
                        caption: "Runs out in 4d at this rate",
                        captionColor: Theme.orange
                    )

                    agentGaugeCard(
                        name: "Cursor",
                        icon: "curlybraces",
                        percent: 48,
                        color: Color(hex: 0x3B82F6),
                        period: "This billing cycle",
                        caption: "Resets in 12d 5h",
                        captionColor: Theme.inkSecondary
                    )
                }

                // MARK: Active Sessions Section
                VStack(alignment: .leading, spacing: 14) {
                    Text("Agent Sessions & Background Workers")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)

                    if store.dev.agents.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles.2")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.agents)
                            Text("No AI coding agent sessions currently running. Start a session in Claude Code, Cursor, or Terminal.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.inkSecondary)
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
            Text("This will terminate the agent session and all associated child workers.")
        }
    }

    // MARK: - Circular Gauge Card

    private func agentGaugeCard(
        name: String,
        icon: String,
        percent: Int,
        color: Color,
        period: String,
        caption: String,
        captionColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 5)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: CGFloat(percent) / 100.0)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 48, height: 48)
                Text("\(percent)%")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                    Text(name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }

                Text(period)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)

                Text(caption)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(captionColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Session Card

    private func sessionCard(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.agents)
                    .frame(width: 28, height: 28)
                    .background(Theme.agents.opacity(0.12), in: Circle())

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
                            Text("idle \(Int(session.runtime / 60)) min")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.inkSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Theme.raised, in: Capsule())
                        }
                    }

                    Text("\(session.agentName) · \(session.project) · running \(Int(session.runtime / 60)) min")
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

            // Workers Sub-list
            if !session.workers.isEmpty {
                Divider().opacity(0.5).padding(.vertical, 2)

                Text("Started · \(session.workers.count)")
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
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSecondary)

                            if w.cpu > 0.01 {
                                Text("· \(Format.percent(w.cpu)) CPU")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.cpu)
                            }

                            Spacer()

                            Text(Format.bytes(w.memory))
                                .font(.system(size: 12))
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
}
