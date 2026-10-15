import SwiftUI
import PulseCore

struct ActionCenterView: View {
    @Bindable var store: AppStore
    @State private var cleaner = JunkCleaner()
    @State private var aiAudit = AIAuditEngine()
    @State private var actionFeedback: String? = nil

    var body: some View {
        let snap = store.snapshot
        let sys = snap.system
        let heavyCPUApps = snap.apps.filter { $0.cpu >= 25.0 }
        let heavyMemApps = snap.apps.filter { $0.memory >= 1_200_000_000 }
        let blockers = store.dev.blockers
        let ports = store.dev.ports.filter { !$0.isDynamic }

        let attentionCount = heavyCPUApps.count +
            (sys.pressure != .normal ? 1 : 0) +
            heavyMemApps.count +
            (cleaner.totalSafeBytes > 1_000_000_000 ? 1 : 0) +
            blockers.count

        let healthScore = max(20, 100 - (heavyCPUApps.count * 12) - (sys.pressure == .critical ? 35 : (sys.pressure == .warning ? 15 : 0)) - (heavyMemApps.count * 8) - (cleaner.totalSafeBytes > 2_000_000_000 ? 10 : 0))

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: Health Score Hero
                heroCard(healthScore: healthScore, attentionCount: attentionCount)

                // Feedback Banner
                if let msg = actionFeedback ?? cleaner.statusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                        Text(msg)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Button {
                            actionFeedback = nil
                            cleaner.statusMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Theme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.green.opacity(0.3)))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // MARK: AI Health & Resource Audit
                aiAuditSection

                // MARK: Storage & Temp Cleaners
                storageSection

                // MARK: CPU Runaways Benchmark (>25%)
                cpuSection(heavyCPUApps: heavyCPUApps)

                // MARK: Memory Hogs Benchmark (>1.2GB)
                memorySection(heavyMemApps: heavyMemApps, pressure: sys.pressure)

                // MARK: Energy & Sleep Blockers
                if !blockers.isEmpty {
                    sleepBlockersSection(blockers: blockers)
                }

                // MARK: Developer Ports
                if !ports.isEmpty {
                    portsSection(ports: ports)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Hero Card

    private func heroCard(healthScore: Int, attentionCount: Int) -> some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Theme.card, lineWidth: 10)
                    .frame(width: 90, height: 90)
                Circle()
                    .trim(from: 0, to: CGFloat(healthScore) / 100.0)
                    .stroke(
                        healthScore > 80 ? Theme.green : (healthScore > 60 ? Theme.yellow : Theme.red),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 90, height: 90)
                VStack(spacing: 0) {
                    Text("\(healthScore)%")
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                    Text("Health")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Action Center")
                        .font(.system(size: 20, weight: .bold))
                    Pill(
                        attentionCount == 0 ? "Optimal" : "\(attentionCount) Need Attention",
                        color: attentionCount == 0 ? Theme.green : (attentionCount > 3 ? Theme.red : Theme.orange)
                    )
                }

                Text(
                    attentionCount == 0
                        ? "Your Mac is running smoothly. All active applications and resources are within healthy benchmarks."
                        : "Detected \(attentionCount) item\(attentionCount == 1 ? "" : "s") outside optimal benchmarks. Review recommended actions below."
                )
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    if cleaner.totalSafeBytes > 0 {
                        Button {
                            Task {
                                await cleaner.cleanAllSafe()
                                feedback("Cleaned all safe temporary data!")
                            }
                        } label: {
                            Label(
                                cleaner.isCleaning ? "Cleaning..." : "Clean All Safe Junk (\(Format.bytes(cleaner.totalSafeBytes)))",
                                systemImage: "sparkles"
                            )
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Theme.orange, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(cleaner.isCleaning)
                    }

                    Button {
                        Task { await cleaner.scan() }
                    } label: {
                        Label(cleaner.isScanning ? "Scanning..." : "Rescan Disk", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                    }
                    .buttonStyle(.plain)
                    .disabled(cleaner.isScanning)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    // MARK: - Storage & Junk Cleaner Section

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Disk Space & Temporary Data", systemImage: "internaldrive")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.disk)
                Spacer()
                Text("\(Format.bytes(cleaner.totalSafeBytes)) Reclaimable")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }

            if cleaner.items.isEmpty {
                emptyCard(message: "No cleanable temporary files found.", icon: "checkmark.circle")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                    ForEach(cleaner.items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 24))
                                .foregroundStyle(Theme.orange)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(Format.bytes(item.sizeBytes))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.inkSecondary)
                            }

                            Spacer()

                            Button {
                                Task {
                                    await cleaner.clean(item: item)
                                    feedback("Cleaned \(item.name)")
                                }
                            } label: {
                                Text("Clean")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Theme.orange)
                                    .padding(.horizontal, 10)
                                    .frame(height: 24)
                                    .background(Theme.orange.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(cleaner.isCleaning)
                        }
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - CPU Benchmark Section

    private func cpuSection(heavyCPUApps: [AppUsage]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("CPU Runaways", systemImage: "cpu")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.cpu)
                Spacer()
                Text("Benchmark: > 25% CPU")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }

            if heavyCPUApps.isEmpty {
                emptyCard(message: "All applications are operating within normal CPU limits (< 25%).", icon: "checkmark.shield")
            } else {
                VStack(spacing: 8) {
                    ForEach(heavyCPUApps) { app in
                        HStack(spacing: 12) {
                            if let bundlePath = app.bundlePath {
                                Image(nsImage: IconCache.icon(forPath: bundlePath))
                                    .resizable()
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 24))
                                    .frame(width: 32, height: 32)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    if let pid = app.processes.first?.pid {
                                        Text("PID: \(pid)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.inkTertiary)
                                    }
                                }
                                Text("High compute load exceeding 25% benchmark")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkSecondary)
                            }

                            Spacer()

                            Text(Format.percent(app.cpu))
                                .font(.system(size: 14, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.red)

                            Button {
                                store.selectedAppID = app.id
                            } label: {
                                Text("Inspect")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .frame(height: 24)
                                    .background(Theme.raised, in: Capsule())
                                    .overlay(Capsule().stroke(Theme.border))
                            }
                            .buttonStyle(.plain)

                            Button {
                                forceQuit(app: app)
                            } label: {
                                Label("Force Quit", systemImage: "xmark.circle.fill")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .frame(height: 24)
                                    .background(Theme.red, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Memory Benchmark Section

    private func memorySection(heavyMemApps: [AppUsage], pressure: MemoryPressure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Memory Hogs & Pressure", systemImage: "memorychip")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.memory)
                Spacer()
                HStack(spacing: 6) {
                    Text("Pressure:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                    Pill(
                        pressure.label,
                        color: pressure == .critical ? Theme.red : (pressure == .warning ? Theme.orange : Theme.green)
                    )
                }
            }

            if heavyMemApps.isEmpty && pressure == .normal {
                emptyCard(message: "Memory pressure is Normal and no apps exceed the 1.2 GB benchmark.", icon: "checkmark.shield")
            } else {
                VStack(spacing: 8) {
                    ForEach(heavyMemApps) { app in
                        HStack(spacing: 12) {
                            if let bundlePath = app.bundlePath {
                                Image(nsImage: IconCache.icon(forPath: bundlePath))
                                    .resizable()
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 24))
                                    .frame(width: 32, height: 32)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .semibold))
                                    if let pid = app.processes.first?.pid {
                                        Text("PID: \(pid)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.inkTertiary)
                                    }
                                }
                                Text("Consumes \(Format.bytes(app.memory)) of RAM")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkSecondary)
                            }

                            Spacer()

                            Text(Format.bytes(app.memory))
                                .font(.system(size: 14, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.memory)

                            Button {
                                forceQuit(app: app)
                            } label: {
                                Text("Quit App")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Theme.red)
                                    .padding(.horizontal, 10)
                                    .frame(height: 24)
                                    .background(Theme.red.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Sleep Blockers Section

    private func sleepBlockersSection(blockers: [SleepBlocker]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sleep Blockers (Battery Drain)", systemImage: "powersleep")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.battery)

            VStack(spacing: 8) {
                ForEach(blockers) { b in
                    HStack(spacing: 12) {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(Theme.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.processName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(b.reason)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                        Button {
                            _ = ProcessActions.terminate(pid: b.pid, force: true)
                            feedback("Terminated sleep blocker \(b.processName)")
                            store.wake()
                        } label: {
                            Text("Stop")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.red)
                                .padding(.horizontal, 10)
                                .frame(height: 24)
                                .background(Theme.red.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    // MARK: - Developer Ports Section

    private func portsSection(ports: [ListeningPort]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Active Dev Ports & Servers", systemImage: "network")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.network)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(ports) { p in
                    HStack(spacing: 10) {
                        Text(":\(p.port)")
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.network)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.network.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.processName)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("PID: \(p.pid) · \(Format.bytes(p.memory))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.inkSecondary)
                        }

                        Spacer()

                        Button {
                            _ = ProcessActions.terminate(pid: p.pid, force: true)
                            feedback("Freed port :\(p.port)")
                            store.wake()
                        } label: {
                            Text("Kill")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.red)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Theme.red.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    // MARK: - AI Resource Audit Section

    private var aiAuditSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with Model Picker & Run Button
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(aiAudit.selectedProvider.color)

                Text("AI Resource Audit & Health Check")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Spacer()

                // AI Model Provider Picker
                Menu {
                    ForEach(AIModelProvider.allCases) { p in
                        Button {
                            aiAudit.selectedProvider = p
                        } label: {
                            HStack {
                                Text(p.rawValue)
                                if aiAudit.selectedProvider == p {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: aiAudit.selectedProvider.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(aiAudit.selectedProvider.color)
                        Text(aiAudit.selectedProvider.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border))
                }
                .menuStyle(.borderlessButton)

                // Run Audit Button
                Button {
                    Task {
                        await aiAudit.runAudit(snapshot: store.snapshot)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if aiAudit.isAnalyzing {
                            ProgressView().controlSize(.small)
                            Text(aiAudit.analysisStep)
                                .font(.system(size: 12, weight: .medium))
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                            Text(aiAudit.currentReport == nil ? "Run AI Audit" : "Re-analyze")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(aiAudit.selectedProvider.color, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(aiAudit.isAnalyzing)
            }

            // Results Card
            if let report = aiAudit.currentReport {
                VStack(alignment: .leading, spacing: 14) {
                    // Verdict Box
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: report.provider.icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(report.provider.color)
                            .frame(width: 32, height: 32)
                            .background(report.provider.color.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("AI Health Verdict")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.ink)

                                Text(report.provider.modelBadge)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(report.provider.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(report.provider.color.opacity(0.12), in: Capsule())
                            }

                            Text(report.summaryVerdict)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        if report.safeQuitCount > 0 {
                            Button {
                                let reclaimed = aiAudit.reclaimAllSafe()
                                feedback("Reclaimed resources from \(reclaimed) background apps!")
                                store.wake()
                            } label: {
                                Label("Reclaim All (\(Format.bytes(report.totalReclaimableMemory)))", systemImage: "sparkles")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .frame(height: 30)
                                    .background(Theme.green, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Stat Pills Row
                    HStack(spacing: 12) {
                        statPill(title: "Reclaimable RAM", value: Format.bytes(report.totalReclaimableMemory), color: Theme.green)
                        statPill(title: "Reclaimable CPU", value: Format.percent(report.totalReclaimableCPU), color: Theme.cpu)
                        statPill(title: "Safe Apps", value: "\(report.safeQuitCount)", color: Theme.green)
                        statPill(title: "System Core Protected", value: "\(report.systemCriticalCount)", color: Theme.red)
                    }

                    Divider().opacity(0.4)

                    // Risk Filter Chips
                    HStack(spacing: 8) {
                        riskFilterChip(title: "All (\(report.findings.count))", level: nil)
                        riskFilterChip(title: "Safe to Quit (\(report.safeQuitCount))", level: .safeToQuit)
                        riskFilterChip(title: "Background Helpers (\(report.backgroundHelperCount))", level: .backgroundHelper)
                        riskFilterChip(title: "macOS Core (\(report.systemCriticalCount))", level: .macOSCore)
                    }

                    // Findings Table
                    let filteredFindings = report.findings.filter {
                        aiAudit.filterRisk == nil || $0.riskLevel == aiAudit.filterRisk
                    }

                    VStack(spacing: 8) {
                        ForEach(filteredFindings) { finding in
                            aiFindingRow(finding)
                        }
                    }
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if !aiAudit.isAnalyzing {
                // Standby Prompt Card
                HStack(spacing: 14) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(aiAudit.selectedProvider.color)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Analyze Resource Hogs & Background Processes with AI")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Theme.ink)

                        Text("Use \(aiAudit.selectedProvider.rawValue) to audit which processes are vital macOS system daemons and which idle apps can be safely closed to reclaim RAM and CPU.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    Spacer()

                    Button {
                        Task {
                            await aiAudit.runAudit(snapshot: store.snapshot)
                        }
                    } label: {
                        Text("Start Audit")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                            .background(aiAudit.selectedProvider.color, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func statPill(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
            Text(value)
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Theme.raised, in: Capsule())
    }

    private func riskFilterChip(title: String, level: AIRiskLevel?) -> some View {
        let isSelected = aiAudit.filterRisk == level
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                aiAudit.filterRisk = level
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .white : Theme.inkSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(isSelected ? Theme.ink : Theme.raised, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func aiFindingRow(_ finding: AIProcessFinding) -> some View {
        HStack(spacing: 12) {
            // Icon
            if let path = finding.iconPath, !path.isEmpty {
                Image(nsImage: IconCache.icon(forPath: path))
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: finding.riskLevel == .macOSCore ? "lock.shield.fill" : "app.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(finding.riskLevel.color)
                    .frame(width: 28, height: 28)
                    .background(finding.riskLevel.color.opacity(0.12), in: Circle())
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(finding.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ink)

                    if finding.pid > 0 {
                        Text("PID \(finding.pid)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.inkTertiary)
                    }

                    // Risk Badge
                    HStack(spacing: 4) {
                        Image(systemName: finding.riskLevel.icon)
                            .font(.system(size: 9))
                        Text(finding.riskLevel.rawValue)
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(finding.riskLevel.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(finding.riskLevel.color.opacity(0.12), in: Capsule())
                }

                Text(finding.aiInsight)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Usage Numbers
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.bytes(finding.memory))
                    .font(.system(size: 12.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)

                if finding.cpu > 0.01 {
                    Text("\(Format.percent(finding.cpu)) CPU")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.cpu)
                }
            }

            // Action
            if finding.canQuit {
                Button {
                    let success = aiAudit.quitProcess(pid: finding.pid)
                    if success {
                        feedback("Quit \(finding.name)")
                        store.wake()
                    }
                } label: {
                    Text("Quit")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Theme.red.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text("Protected")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(Theme.inkTertiary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Theme.raised, in: Capsule())
            }
        }
        .padding(12)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers

    private func emptyCard(message: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Theme.green)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func forceQuit(app: AppUsage) {
        store.terminate(app: app, force: true)
        feedback("Terminated \(app.name)")
    }

    private func feedback(_ msg: String) {
        withAnimation { actionFeedback = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { if actionFeedback == msg { actionFeedback = nil } }
        }
    }
}
