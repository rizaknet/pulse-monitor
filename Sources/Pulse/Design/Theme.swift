import SwiftUI
import AppKit

// Design tokens: soft grey cards on a white canvas (dark: near-black), one tint per metric.
private func dynColor(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = isDark ? dark : light
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    })
}

enum Theme {
    static let bg = dynColor(0xFFFFFF, 0x161618)
    static let card = dynColor(0xF5F5F7, 0x222225)
    static let cardHover = dynColor(0xEDEDF0, 0x2A2A2E)
    static let raised = dynColor(0xFFFFFF, 0x2C2C30)
    static let border = Color.primary.opacity(0.07)

    static let ink = dynColor(0x1D1D1F, 0xF5F5F7)
    static let inkSecondary = dynColor(0x6E6E73, 0xA1A1A6)
    static let inkTertiary = dynColor(0xA1A1A6, 0x6E6E73)

    static let accent = dynColor(0x007AFF, 0x0A84FF)
    static let cpu = dynColor(0x2A78D6, 0x4A94F0)
    static let memory = dynColor(0x5A4BC2, 0x9085E9)
    static let disk = dynColor(0xE89A00, 0xE0A020)
    static let network = dynColor(0x1BAF7A, 0x2BC08A)
    static let gpu = dynColor(0xE06A98, 0xE07AA4)
    static let battery = dynColor(0x1E9E3A, 0x34C759)
    static let projects = dynColor(0xEB6834, 0xF07A45)
    static let apps = dynColor(0x0A84FF, 0x409CFF)
    static let agents = dynColor(0x9333EA, 0xC084FC)

    static let claude = dynColor(0xD97757, 0xEB8A6B)
    static let codex = dynColor(0x10A37F, 0x1DBE96)
    static let gemini = dynColor(0x1A73E8, 0x4285F4)

    static let red = dynColor(0xE0352B, 0xFF5A50)
    static let orange = dynColor(0xF08A24, 0xFF9F40)
    static let green = dynColor(0x248A3D, 0x30D158)
    static let yellow = dynColor(0xE5A100, 0xF5B623)

    static let radius: CGFloat = 16
}

enum PulseTab: String, CaseIterable, Identifiable {
    case overview, actionCenter, apps, cpu, memory, disk, network, gpu, battery, projects, agents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .actionCenter: "Action Center"
        case .apps: "Apps"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .network: "Network"
        case .gpu: "GPU"
        case .battery: "Battery"
        case .projects: "Projects"
        case .agents: "Agents"
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .actionCenter: "bolt.shield"
        case .apps: "square.stack"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "globe"
        case .gpu: "square.3.layers.3d"
        case .battery: "battery.75percent"
        case .projects: "folder"
        case .agents: "sparkles.2"
        }
    }

    var color: Color {
        switch self {
        case .overview: Theme.accent
        case .actionCenter: Theme.orange
        case .apps: Theme.apps
        case .cpu: Theme.cpu
        case .memory: Theme.memory
        case .disk: Theme.disk
        case .network: Theme.network
        case .gpu: Theme.gpu
        case .battery: Theme.battery
        case .projects: Theme.projects
        case .agents: Theme.agents
        }
    }
}

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 64, height: 64)
        cache[path] = img
        return img
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
