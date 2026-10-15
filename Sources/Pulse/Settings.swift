import Foundation
import SwiftUI

enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case cpuAndMem = "CPU & Memory"
    case cpuMemNet = "CPU, Memory & Network"
    case sparkline = "Sparkline & CPU"
    case cpuOnly = "CPU"
    case memOnly = "Memory"
    case network = "Network"
    case iconOnly = "Icon Only"

    var id: String { rawValue }
}

/// User preferences, persisted to UserDefaults on every change.
@MainActor
@Observable
final class PulseSettings {
    private let defaults = UserDefaults.standard

    var activeSamplingInterval: TimeInterval { didSet { defaults.set(activeSamplingInterval, forKey: "activeInterval") } }
    var idleSamplingInterval: TimeInterval { didSet { defaults.set(idleSamplingInterval, forKey: "idleInterval") } }
    var menuBarMode: MenuBarDisplayMode { didSet { defaults.set(menuBarMode.rawValue, forKey: "menuBarMode") } }
    var sendNotifications: Bool { didSet { defaults.set(sendNotifications, forKey: "notifications") } }

    init() {
        let d = UserDefaults.standard
        activeSamplingInterval = d.object(forKey: "activeInterval") as? Double ?? 2
        idleSamplingInterval = d.object(forKey: "idleInterval") as? Double ?? 5
        menuBarMode = MenuBarDisplayMode(rawValue: d.string(forKey: "menuBarMode") ?? "") ?? .cpuAndMem
        sendNotifications = d.object(forKey: "notifications") as? Bool ?? true
    }
}
