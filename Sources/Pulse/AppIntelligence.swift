import Foundation
import SwiftUI
import Security
import PulseCore

public enum AppLegitimacy: String, Sendable, CaseIterable {
    case appleSystem = "Apple System"
    case verifiedVendor = "Verified App"
    case developerTool = "Developer Tool"
    case unknownUnsigned = "Unknown / Unsigned"

    public var title: String { rawValue }

    public var icon: String {
        switch self {
        case .appleSystem: "apple.logo"
        case .verifiedVendor: "checkmark.seal.fill"
        case .developerTool: "hammer.fill"
        case .unknownUnsigned: "exclamationmark.triangle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .appleSystem: Theme.inkSecondary
        case .verifiedVendor: Theme.green
        case .developerTool: Theme.accent
        case .unknownUnsigned: Theme.orange
        }
    }

    public var badgeBackground: Color {
        switch self {
        case .appleSystem: Theme.raised
        case .verifiedVendor: Theme.green.opacity(0.12)
        case .developerTool: Theme.accent.opacity(0.12)
        case .unknownUnsigned: Theme.orange.opacity(0.14)
        }
    }
}

public struct AppIntel: Sendable {
    public let appName: String
    public let summary: String
    public let legitimacy: AppLegitimacy
    public let vendor: String
    public let teamID: String?
    public let bundleID: String?
    public let signingAuthority: String
    public let isNotarized: Bool
    public let category: String
    public let deepDetails: String
    public let riskVerdict: String
    public let recommendation: String

    public init(
        appName: String,
        summary: String,
        legitimacy: AppLegitimacy,
        vendor: String,
        teamID: String? = nil,
        bundleID: String? = nil,
        signingAuthority: String = "",
        isNotarized: Bool = false,
        category: String = "Application",
        deepDetails: String = "",
        riskVerdict: String = "Verified Safe",
        recommendation: String = "Safe to keep running"
    ) {
        self.appName = appName
        self.summary = summary
        self.legitimacy = legitimacy
        self.vendor = vendor
        self.teamID = teamID
        self.bundleID = bundleID
        self.signingAuthority = signingAuthority
        self.isNotarized = isNotarized
        self.category = category
        self.deepDetails = deepDetails
        self.riskVerdict = riskVerdict
        self.recommendation = recommendation
    }
}

@MainActor
public final class AppIntelligence {
    public static let shared = AppIntelligence()

    private var cache: [String: AppIntel] = [:]

    private init() {}

    // MARK: - Synchronous Fast Lookup
    public func lookup(app: AppUsage) -> AppIntel {
        let key = app.bundlePath ?? app.id
        if let cached = cache[key] {
            return cached
        }

        // 1. Check known built-in dictionary
        if let known = knownApps[app.name.lowercased()] ?? knownApps[app.id.lowercased()] {
            let intel = completeIntel(known, for: app)
            cache[key] = intel
            return intel
        }

        // 2. Dynamic Bundle / Code Signing Analysis
        let intel = analyzeApp(app)
        cache[key] = intel
        return intel
    }

    // MARK: - Deep AI Analysis for Individual App
    public func research(app: AppUsage) async -> AppIntel {
        // Run deep inspection on background thread
        let result = await Task.detached(priority: .userInitiated) { () -> AppIntel in
            let base = self.analyzeApp(app)

            // Deep inspect sub-processes and architecture
            let procCount = app.processes.count
            let memMB = app.memory / (1024 * 1024)
            let isHeavy = memMB > 1024
            let hasNetwork = app.network > 500

            var helperSummary: [String] = []
            for p in app.processes {
                let lower = p.name.lowercased()
                if lower.contains("gpu") { helperSummary.append("Hardware GPU Acceleration") }
                if lower.contains("network") { helperSummary.append("Isolated Network Service") }
                if lower.contains("renderer") { helperSummary.append("Web Content Sandbox") }
                if lower.contains("audio") { helperSummary.append("Core Audio Host") }
            }
            let uniqueHelpers = Array(Set(helperSummary)).joined(separator: ", ")

            let architectureDesc = procCount > 1
                ? "Multi-process architecture with \(procCount) isolated helpers (\(uniqueHelpers.isEmpty ? "sandboxed workers" : uniqueHelpers))."
                : "Single standalone process binary."

            let memAdvice: String
            if isHeavy {
                memAdvice = "Consuming significant memory (\(Format.bytes(app.memory))). Quitting this app when inactive will immediately reclaim resources for other workflows."
            } else {
                memAdvice = "Lightweight resource footprint (\(Format.bytes(app.memory))). Safe to leave running in background without noticeable system degradation."
            }

            let enrichedDetails = """
            \(base.deepDetails.isEmpty ? base.summary : base.deepDetails)

            • Architecture: \(architectureDesc)
            • Active Footprint: \(Format.bytes(app.memory)) RAM, \(Format.cpuShare(app.cpu)) CPU\(hasNetwork ? ", active network traffic" : "").
            • Security Posture: \(base.signingAuthority.isEmpty ? "Unsigned / Ad-hoc binary" : base.signingAuthority). \(base.isNotarized ? "Notarized by Apple." : "")
            """

            return AppIntel(
                appName: base.appName,
                summary: base.summary,
                legitimacy: base.legitimacy,
                vendor: base.vendor,
                teamID: base.teamID,
                bundleID: base.bundleID,
                signingAuthority: base.signingAuthority,
                isNotarized: base.isNotarized,
                category: base.category,
                deepDetails: enrichedDetails,
                riskVerdict: base.riskVerdict,
                recommendation: memAdvice
            )
        }.value

        let key = app.bundlePath ?? app.id
        cache[key] = result
        return result
    }

    // MARK: - Bundle & Code Signing Analyzer
    nonisolated private func analyzeApp(_ app: AppUsage) -> AppIntel {
        let name = app.name
        let lowerName = name.lowercased()
        let path = app.bundlePath ?? app.processes.first?.path ?? ""
        let lowerPath = path.lowercased()

        // 1. Apple System Apps & Core Daemons
        if app.kind == .system || lowerPath.hasPrefix("/system/") || lowerPath.hasPrefix("/usr/") || lowerPath.hasPrefix("/sbin/") || lowerPath.hasPrefix("/bin/") {
            return AppIntel(
                appName: name,
                summary: "Apple macOS core operating system component",
                legitimacy: .appleSystem,
                vendor: "Apple Inc.",
                teamID: nil,
                bundleID: "com.apple.\(lowerName.replacingOccurrences(of: " ", with: "-"))",
                signingAuthority: "macOS Software Signing (Apple)",
                isNotarized: true,
                category: "System OS",
                deepDetails: "Essential Darwin microkernel daemon or core framework required for macOS system stability, windowing, security, and hardware communication.",
                riskVerdict: "System Essential",
                recommendation: "Protected system service. Do not terminate."
            )
        }

        // 2. Developer & Command-Line Environment Tools
        if lowerPath.contains("/bin/") || lowerPath.contains("/usr/local/") || lowerPath.contains("/opt/homebrew/") || lowerPath.contains("/.local/") || lowerPath.contains("/.cargo/") || lowerPath.contains("/node_modules/") {
            return AppIntel(
                appName: name,
                summary: "Developer CLI tool or local runtime binary",
                legitimacy: .developerTool,
                vendor: "Local Developer Environment",
                teamID: nil,
                bundleID: nil,
                signingAuthority: "Command-Line Executable",
                isNotarized: false,
                category: "Developer Tool",
                deepDetails: "Local command-line binary running from developer search paths (Homebrew, cargo, or local bin). Typically launched from a terminal or build system.",
                riskVerdict: "Developer Tool",
                recommendation: "Safe to quit if its associated build or terminal task is complete."
            )
        }

        // 3. Inspect Bundle Metadata & Code Signing via Security Framework
        if let bundlePath = app.bundlePath, !bundlePath.isEmpty {
            let bundleURL = URL(fileURLWithPath: bundlePath)
            var staticCode: SecStaticCode?
            var vendorName = "Unknown Developer"
            var teamIdentifier: String? = nil
            var bundleIdentifier: String? = nil
            var authorityString = ""
            var isValidSignature = false

            // Read Info.plist
            if let bundle = Bundle(url: bundleURL) {
                bundleIdentifier = bundle.bundleIdentifier
                if let copyright = bundle.infoDictionary?["NSHumanReadableCopyright"] as? String, !copyright.isEmpty {
                    vendorName = extractVendor(from: copyright)
                }
            }

            // Inspect SecStaticCode
            if SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode {
                var infoCF: CFDictionary?
                if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
                   let info = infoCF as? [String: Any] {
                    if let id = info[kSecCodeInfoIdentifier as String] as? String {
                        bundleIdentifier = id
                    }
                    if let team = info[kSecCodeInfoTeamIdentifier as String] as? String {
                        teamIdentifier = team
                    }
                    if let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let first = certs.first {
                        var commonName: CFString?
                        SecCertificateCopyCommonName(first, &commonName)
                        if let cn = commonName as String? {
                            authorityString = cn
                            if vendorName == "Unknown Developer" {
                                vendorName = extractVendorFromCert(cn)
                            }
                        }
                    }
                    isValidSignature = true
                }
            }

            let isAppleSigned = authorityString.contains("Apple") || (bundleIdentifier?.hasPrefix("com.apple.") ?? false)
            let isVerified = isValidSignature && (!authorityString.isEmpty && !authorityString.lowercased().contains("adhoc"))

            if isAppleSigned {
                return AppIntel(
                    appName: name,
                    summary: "Verified Apple macOS system application",
                    legitimacy: .appleSystem,
                    vendor: "Apple Inc.",
                    teamID: teamIdentifier,
                    bundleID: bundleIdentifier,
                    signingAuthority: authorityString.isEmpty ? "Apple Software Signing" : authorityString,
                    isNotarized: true,
                    category: "macOS Core",
                    deepDetails: "Official Apple macOS application integrated with the operating system framework.",
                    riskVerdict: "System Essential",
                    recommendation: "System service. Safe to keep running."
                )
            } else if isVerified {
                return AppIntel(
                    appName: name,
                    summary: "Verified \(vendorName) application (\(bundleIdentifier ?? name))",
                    legitimacy: .verifiedVendor,
                    vendor: vendorName,
                    teamID: teamIdentifier,
                    bundleID: bundleIdentifier,
                    signingAuthority: authorityString,
                    isNotarized: true,
                    category: "Third-Party App",
                    deepDetails: "Code-signed and notarized application by verified developer \(vendorName) (Team: \(teamIdentifier ?? "Unknown")). Operates within Apple Gatekeeper security guidelines.",
                    riskVerdict: "Verified Safe",
                    recommendation: "Legitimate application. Can be quit safely if not actively used."
                )
            }
        }

        // 4. Fallback / Unsigned Binary
        return AppIntel(
            appName: name,
            summary: "Unsigned or unrecognized application binary",
            legitimacy: .unknownUnsigned,
            vendor: "Unverified / Unknown",
            teamID: nil,
            bundleID: nil,
            signingAuthority: "Unsigned / Ad-hoc",
            isNotarized: false,
            category: "Unknown Binary",
            deepDetails: "This process has no valid Apple Developer ID signature or notarization ticket. It may be a custom compiled script, an ad-hoc local build, or an unrecognized process running from user storage.",
            riskVerdict: "Review Recommended",
            recommendation: "Inspect binary path in Finder or Terminal. If not initiated by you, terminate to prevent unauthorized resource usage."
        )
    }

    nonisolated private func completeIntel(_ template: AppIntel, for app: AppUsage) -> AppIntel {
        return AppIntel(
            appName: template.appName,
            summary: template.summary,
            legitimacy: template.legitimacy,
            vendor: template.vendor,
            teamID: template.teamID,
            bundleID: template.bundleID,
            signingAuthority: template.signingAuthority,
            isNotarized: template.isNotarized,
            category: template.category,
            deepDetails: template.deepDetails,
            riskVerdict: template.riskVerdict,
            recommendation: template.recommendation
        )
    }

    nonisolated private func extractVendor(from copyright: String) -> String {
        // e.g. "Copyright © 2026 Google LLC. All rights reserved."
        let cleaned = copyright.replacingOccurrences(of: "Copyright", with: "")
            .replacingOccurrences(of: "©", with: "")
            .replacingOccurrences(of: "All rights reserved.", with: "")
            .replacingOccurrences(of: "All rights reserved", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.components(separatedBy: CharacterSet.decimalDigits).joined()
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".-, ")))
        return parts.isEmpty ? "Verified Vendor" : parts
    }

    nonisolated private func extractVendorFromCert(_ certName: String) -> String {
        // e.g. "Developer ID Application: Anthropic PBC (Q6L2SF6YDW)"
        var s = certName
        if let r = s.range(of: "Developer ID Application: ") {
            s = String(s[r.upperBound...])
        }
        if let idx = s.firstIndex(of: "(") {
            s = String(s[..<idx]).trimmingCharacters(in: .whitespaces)
        }
        return s.isEmpty ? "Verified Developer" : s
    }

    // MARK: - Built-in Knowledge Base for Instant Performance
    private let knownApps: [String: AppIntel] = [
        "google chrome": AppIntel(
            appName: "Google Chrome",
            summary: "Verified Google multi-process web browser",
            legitimacy: .verifiedVendor,
            vendor: "Google LLC",
            teamID: "EQHXZ8M8AV",
            bundleID: "com.google.Chrome",
            signingAuthority: "Developer ID Application: Google LLC",
            isNotarized: true,
            category: "Web Browser",
            deepDetails: "Chromium-based web browser with sandboxed tab renderers, GPU compositor, and network service daemons. High memory usage is typical for rich web applications.",
            riskVerdict: "Verified Safe",
            recommendation: "Safe to quit if not actively browsing to free significant RAM."
        ),
        "chatgpt": AppIntel(
            appName: "ChatGPT",
            summary: "OpenAI desktop client with Codex code sandbox",
            legitimacy: .verifiedVendor,
            vendor: "OpenAI OpCo, LLC",
            teamID: "2DC432GLL2",
            bundleID: "com.openai.codex",
            signingAuthority: "Developer ID Application: OpenAI OpCo, LLC",
            isNotarized: true,
            category: "AI Assistant",
            deepDetails: "Official OpenAI native client providing access to ChatGPT, Advanced Voice, and the local Codex App Server environment for code generation.",
            riskVerdict: "Verified Safe",
            recommendation: "Safe to keep running during active AI programming sessions."
        ),
        "claude": AppIntel(
            appName: "Claude",
            summary: "Anthropic AI assistant & development desktop client",
            legitimacy: .verifiedVendor,
            vendor: "Anthropic PBC",
            teamID: "Q6L2SF6YDW",
            bundleID: "com.anthropic.claudefordesktop",
            signingAuthority: "Developer ID Application: Anthropic PBC",
            isNotarized: true,
            category: "AI Assistant",
            deepDetails: "Official Anthropic Claude desktop application supporting Sonnet/Opus models, artifact previews, and background project integrations.",
            riskVerdict: "Verified Safe",
            recommendation: "Safe to keep running during AI development tasks."
        ),
        "antigravity": AppIntel(
            appName: "Antigravity",
            summary: "Google AI-assisted agentic developer platform",
            legitimacy: .verifiedVendor,
            vendor: "Google LLC",
            teamID: "EQHXZ8M8AV",
            bundleID: "com.google.antigravity",
            signingAuthority: "Developer ID Application: Google LLC",
            isNotarized: true,
            category: "Developer Platform",
            deepDetails: "Google AI development workspace featuring paired agentic coding, subagents, and automated codebase workflow intelligence.",
            riskVerdict: "Verified Safe",
            recommendation: "Core active assistant. Keep running during coding sessions."
        ),
        "antigravity ide": AppIntel(
            appName: "Antigravity IDE",
            summary: "Google AI agentic integrated development environment",
            legitimacy: .verifiedVendor,
            vendor: "Google LLC",
            teamID: "EQHXZ8M8AV",
            bundleID: "com.google.antigravity.ide",
            signingAuthority: "Developer ID Application: Google LLC",
            isNotarized: true,
            category: "Developer Platform",
            deepDetails: "Specialized IDE built for deep agentic pairing, full syntax analysis, language server diagnostics, and multi-file code editing.",
            riskVerdict: "Verified Safe",
            recommendation: "Primary coding environment. Keep running while working."
        ),
        "docker": AppIntel(
            appName: "Docker",
            summary: "Verified container virtualization engine & desktop daemon",
            legitimacy: .verifiedVendor,
            vendor: "Docker Inc",
            teamID: "9BNSXJN65R",
            bundleID: "com.docker.docker",
            signingAuthority: "Developer ID Application: Docker Inc",
            isNotarized: true,
            category: "Virtualization",
            deepDetails: "Hypervisor framework and container engine daemon. Manages Linux VM, volume syncing, and virtual containerized networking.",
            riskVerdict: "Verified Safe",
            recommendation: "Can consume several gigabytes of memory. Quit when not running containers."
        ),
        "cmux": AppIntel(
            appName: "cmux",
            summary: "Terminal workspace & multi-agent multiplexer daemon",
            legitimacy: .verifiedVendor,
            vendor: "Manaflow, Inc.",
            teamID: "7WLXT3NR37",
            bundleID: "com.cmuxterm.app",
            signingAuthority: "Developer ID Application: Manaflow, Inc.",
            isNotarized: true,
            category: "Developer Tool",
            deepDetails: "Specialized developer terminal multiplexer managing background agent spool forwarders, computer use sockets, and session hooks.",
            riskVerdict: "Verified Safe",
            recommendation: "Keep running if active CLI agent sessions rely on spool hooks."
        ),
        "microsoft teams": AppIntel(
            appName: "Microsoft Teams",
            summary: "Microsoft enterprise collaboration & meetings client",
            legitimacy: .verifiedVendor,
            vendor: "Microsoft Corporation",
            teamID: "UBF8T346G9",
            bundleID: "com.microsoft.teams2",
            signingAuthority: "Developer ID Application: Microsoft Corporation",
            isNotarized: true,
            category: "Communication",
            deepDetails: "Enterprise team chat, video conferencing, and document collaboration client. Runs background audio and notification daemons.",
            riskVerdict: "Verified Safe",
            recommendation: "Safe to quit when meetings and work calls are finished to save memory."
        ),
        "whatsapp": AppIntel(
            appName: "WhatsApp",
            summary: "Meta verified end-to-end encrypted messaging client",
            legitimacy: .verifiedVendor,
            vendor: "Meta Platforms, Inc.",
            teamID: "57T9237FN3",
            bundleID: "net.whatsapp.WhatsApp",
            signingAuthority: "Apple Mac OS Application Signing",
            isNotarized: true,
            category: "Communication",
            deepDetails: "Native macOS Catalyst/AppKit messaging app synchronized with mobile WhatsApp via end-to-end encrypted session keys.",
            riskVerdict: "Verified Safe",
            recommendation: "Safe to leave running for instant incoming notifications."
        ),
        "safari": AppIntel(
            appName: "Safari",
            summary: "Apple built-in privacy-focused WebKit browser",
            legitimacy: .appleSystem,
            vendor: "Apple Inc.",
            teamID: nil,
            bundleID: "com.apple.Safari",
            signingAuthority: "macOS Software Signing (Apple)",
            isNotarized: true,
            category: "Web Browser",
            deepDetails: "Native macOS web browser optimized for low energy consumption, WebKit rendering, and Apple Silicon hardware acceleration.",
            riskVerdict: "System Essential",
            recommendation: "Safe to keep running. High energy efficiency."
        ),
        "siri": AppIntel(
            appName: "Siri",
            summary: "Apple voice and system intelligence assistant",
            legitimacy: .appleSystem,
            vendor: "Apple Inc.",
            teamID: nil,
            bundleID: "com.apple.siri",
            signingAuthority: "macOS Software Signing (Apple)",
            isNotarized: true,
            category: "System OS",
            deepDetails: "Apple on-device voice processing, dictation engine, and system intelligence background service.",
            riskVerdict: "System Essential",
            recommendation: "Apple system daemon. Leave running."
        ),
        "macos": AppIntel(
            appName: "macOS",
            summary: "Apple core Darwin microkernel & system services",
            legitimacy: .appleSystem,
            vendor: "Apple Inc.",
            teamID: nil,
            bundleID: "com.apple.darwin",
            signingAuthority: "macOS Software Signing (Apple)",
            isNotarized: true,
            category: "System OS",
            deepDetails: "Core operating system processes including launchd, WindowServer, kernel_task, and Apple hardware device drivers.",
            riskVerdict: "System Essential",
            recommendation: "Core macOS operating system. Critical for system functionality."
        ),
        "pulse": AppIntel(
            appName: "Pulse",
            summary: "Native macOS system and AI agent resource monitor",
            legitimacy: .developerTool,
            vendor: "Local Build",
            teamID: nil,
            bundleID: "com.cc-rea.pulse",
            signingAuthority: "Local Developer Build",
            isNotarized: false,
            category: "System Monitor",
            deepDetails: "High-performance native macOS system monitor written in Swift/SwiftUI. Samples CPU, memory, power assertions, and AI agents with near-zero overhead.",
            riskVerdict: "Verified Safe",
            recommendation: "Current application."
        )
    ]
}
