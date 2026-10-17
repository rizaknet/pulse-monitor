import SwiftUI
import Charts
import PulseCore

struct AppDetailPanel: View {
    let app: AppUsage
    @Bindable var store: AppStore

    @State private var intel: AppIntel? = nil
    @State private var isResearching = false

    var body: some View {
        let currentIntel = intel ?? AppIntelligence.shared.lookup(app: app)

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                AppIconView(app: app, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(currentIntel.bundleID ?? (app.kind == .app ? (app.bundlePath ?? "Application") : "Command Line Tool"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    store.selectedAppID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider().opacity(0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // MARK: AI Legitimacy Banner
                    HStack(spacing: 8) {
                        Image(systemName: currentIntel.legitimacy.icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(currentIntel.legitimacy.color)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(currentIntel.legitimacy.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(currentIntel.legitimacy.color)
                            Text(currentIntel.summary)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(currentIntel.legitimacy.badgeBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(currentIntel.legitimacy.color.opacity(0.25)))

                    // MARK: AI Security & Intelligence Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.agents)
                            Text("AI Security & Provenance")
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Spacer()

                            Button {
                                runDeepResearch()
                            } label: {
                                HStack(spacing: 4) {
                                    if isResearching {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: "sparkle.magnifyingglass")
                                            .font(.system(size: 10.5))
                                    }
                                    Text(isResearching ? "Auditing…" : "Deep Scan")
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                                .foregroundStyle(Theme.agents)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.agents.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(isResearching)
                        }

                        // Developer & Signing Metadata
                        VStack(spacing: 5) {
                            metaRow("Developer", currentIntel.vendor)
                            if let team = currentIntel.teamID {
                                metaRow("Team ID", team)
                            }
                            metaRow("Code Signature", currentIntel.signingAuthority.isEmpty ? "Unsigned / Ad-hoc" : currentIntel.signingAuthority)
                            metaRow("Notarized", currentIntel.isNotarized ? "Yes (Apple Verified)" : "No / Unsigned")
                            metaRow("Safety Verdict", currentIntel.riskVerdict)
                        }
                        .padding(10)
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        // AI Analysis Details
                        if !currentIntel.deepDetails.isEmpty {
                            Text(currentIntel.deepDetails)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.ink)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // AI Recommendation
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.accent)
                                .padding(.top, 1)
                            Text(currentIntel.recommendation)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Quick Stats Cards
                    VStack(spacing: 8) {
                        metricRow("CPU", Format.cpuShare(app.cpu), color: Theme.cpu)
                        metricRow("Memory", Format.bytes(app.memory), color: Theme.memory)
                        metricRow("GPU", app.gpu > 0.005 ? Format.percent(app.gpu) : "—", color: Theme.gpu)
                        metricRow("Network", app.network > 100 ? Format.rate(app.network) : "Idle", color: Theme.network)
                        metricRow("Disk I/O", app.diskIO > 100 ? Format.rate(app.diskIO) : "Idle", color: Theme.disk)
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Sub-processes list
                    Text("Processes (\(app.processes.count))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, 4)

                    VStack(spacing: 4) {
                        ForEach(app.processes.sorted { $0.cpu > $1.cpu }) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    Text("PID \(p.pid)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.inkTertiary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Format.cpuShare(p.cpu))
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.cpu)
                                    Text(Format.bytes(p.memory, compact: true))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                            }
                            .padding(8)
                            .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .padding(16)
            }

            Divider().opacity(0.6)

            // Bottom Actions
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button("Quit App") {
                        store.terminate(app: app, force: false)
                    }
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity)

                    Button("Force Quit") {
                        store.terminate(app: app, force: true)
                    }
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity)
                }

                if let b = app.bundlePath {
                    Button {
                        NSWorkspace.shared.selectFile(b, inFileViewerRootedAtPath: "")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("Reveal in Finder")
                                .font(.system(size: 11.5))
                        }
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Theme.bg)
        }
        .background(Theme.bg)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: -4, y: 0)
        .onAppear {
            intel = AppIntelligence.shared.lookup(app: app)
        }
        .onChange(of: app.id) { _, _ in
            intel = AppIntelligence.shared.lookup(app: app)
        }
    }

    private func runDeepResearch() {
        isResearching = true
        Task {
            let res = await AppIntelligence.shared.research(app: app)
            await MainActor.run {
                self.intel = res
                self.isResearching = false
            }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func metricRow(_ title: String, _ val: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(val)
                .font(.system(size: 12.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }
}
