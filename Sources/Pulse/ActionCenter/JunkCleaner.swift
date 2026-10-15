import Foundation
import AppKit
import PulseCore

public struct JunkItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let path: String
    public let sizeBytes: Int64
    public let isSafe: Bool
    public let icon: String
}

@MainActor
@Observable
public final class JunkCleaner {
    public var items: [JunkItem] = []
    public var totalSafeBytes: Int64 = 0
    public var isScanning: Bool = false
    public var isCleaning: Bool = false
    public var statusMessage: String? = nil

    public init() {
        Task { await scan() }
    }

    public func scan() async {
        isScanning = true
        defer { isScanning = false }

        let scanned = await Task.detached(priority: .utility) { () -> [JunkItem] in
            let fm = FileManager.default
            var results: [JunkItem] = []
            let home = fm.homeDirectoryForCurrentUser
            let cachesDir = home.appendingPathComponent("Library/Caches")

            // 1. Squirrel & App Updater caches (*.ShipIt, *updater*)
            var shipItBytes: Int64 = 0
            if let contents = try? fm.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil) {
                for url in contents where url.lastPathComponent.contains("ShipIt") || url.lastPathComponent.contains("updater") {
                    shipItBytes += Self.calcDirSize(url, fm: fm)
                }
            }
            if shipItBytes > 0 {
                results.append(JunkItem(
                    id: "updater_caches",
                    name: "App Updater & ShipIt Caches",
                    category: "Caches",
                    path: "~/Library/Caches/*ShipIt*",
                    sizeBytes: shipItBytes,
                    isSafe: true,
                    icon: "arrow.triangle.2.circlepath.circle.fill"
                ))
            }

            // 2. Playwright Browser Builds
            let playwrightDir = cachesDir.appendingPathComponent("ms-playwright")
            let playwrightBytes = Self.calcDirSize(playwrightDir, fm: fm)
            if playwrightBytes > 0 {
                results.append(JunkItem(
                    id: "playwright_caches",
                    name: "Playwright Browser Binaries",
                    category: "Developer",
                    path: "~/Library/Caches/ms-playwright",
                    sizeBytes: playwrightBytes,
                    isSafe: true,
                    icon: "globe.badge.chevron.backward"
                ))
            }

            // 3. Package Manager Caches (pnpm, npm, yarn)
            let pnpmDir = cachesDir.appendingPathComponent("pnpm")
            let npmDir = home.appendingPathComponent(".npm")
            let yarnDir = cachesDir.appendingPathComponent("Yarn")
            let pkgBytes = Self.calcDirSize(pnpmDir, fm: fm) + Self.calcDirSize(npmDir, fm: fm) + Self.calcDirSize(yarnDir, fm: fm)
            if pkgBytes > 0 {
                results.append(JunkItem(
                    id: "pkg_caches",
                    name: "Node & Package Caches (pnpm/npm)",
                    category: "Developer",
                    path: "~/Library/Caches/pnpm",
                    sizeBytes: pkgBytes,
                    isSafe: true,
                    icon: "shippingbox.fill"
                ))
            }

            // 4. Homebrew Download Cache
            let brewDir = cachesDir.appendingPathComponent("Homebrew")
            let brewBytes = Self.calcDirSize(brewDir, fm: fm)
            if brewBytes > 0 {
                results.append(JunkItem(
                    id: "homebrew_caches",
                    name: "Homebrew Download Cache",
                    category: "Developer",
                    path: "~/Library/Caches/Homebrew",
                    sizeBytes: brewBytes,
                    isSafe: true,
                    icon: "mug.fill"
                ))
            }

            // 5. Xcode DerivedData
            let xcodeDir = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
            let xcodeBytes = Self.calcDirSize(xcodeDir, fm: fm)
            if xcodeBytes > 0 {
                results.append(JunkItem(
                    id: "xcode_derived_data",
                    name: "Xcode DerivedData",
                    category: "Developer",
                    path: "~/Library/Developer/Xcode/DerivedData",
                    sizeBytes: xcodeBytes,
                    isSafe: true,
                    icon: "hammer.circle.fill"
                ))
            }

            // 6. User Logs
            let logsDir = home.appendingPathComponent("Library/Logs")
            let logsBytes = Self.calcDirSize(logsDir, fm: fm)
            if logsBytes > 0 {
                results.append(JunkItem(
                    id: "system_logs",
                    name: "System & Crash Logs",
                    category: "Logs",
                    path: "~/Library/Logs",
                    sizeBytes: logsBytes,
                    isSafe: true,
                    icon: "doc.text.fill"
                ))
            }

            // 7. Trash Bin
            let trashDir = home.appendingPathComponent(".Trash")
            let trashBytes = Self.calcDirSize(trashDir, fm: fm)
            if trashBytes > 0 {
                results.append(JunkItem(
                    id: "trash",
                    name: "Trash Bin",
                    category: "Trash",
                    path: "~/.Trash",
                    sizeBytes: trashBytes,
                    isSafe: true,
                    icon: "trash.circle.fill"
                ))
            }

            return results
        }.value

        self.items = scanned
        self.totalSafeBytes = scanned.filter(\.isSafe).map(\.sizeBytes).reduce(0, +)
    }

    public func clean(item: JunkItem) async {
        isCleaning = true
        defer { isCleaning = false }

        let success = await Task.detached(priority: .utility) { () -> Bool in
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let cachesDir = home.appendingPathComponent("Library/Caches")

            switch item.id {
            case "trash":
                let script = "tell application \"Finder\" to empty trash"
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", script]
                try? p.run()
                p.waitUntilExit()
                return p.terminationStatus == 0

            case "xcode_derived_data":
                let dir = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
                return Self.removeContents(of: dir, fm: fm)

            case "updater_caches":
                if let contents = try? fm.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil) {
                    for url in contents where url.lastPathComponent.contains("ShipIt") || url.lastPathComponent.contains("updater") {
                        try? fm.removeItem(at: url)
                    }
                }
                return true

            case "playwright_caches":
                let dir = cachesDir.appendingPathComponent("ms-playwright")
                return Self.removeContents(of: dir, fm: fm)

            case "pkg_caches":
                let pnpmDir = cachesDir.appendingPathComponent("pnpm")
                let yarnDir = cachesDir.appendingPathComponent("Yarn")
                _ = Self.removeContents(of: pnpmDir, fm: fm)
                _ = Self.removeContents(of: yarnDir, fm: fm)
                return true

            case "homebrew_caches":
                let dir = cachesDir.appendingPathComponent("Homebrew")
                return Self.removeContents(of: dir, fm: fm)

            case "system_logs":
                let dir = home.appendingPathComponent("Library/Logs")
                return Self.removeContents(of: dir, fm: fm)

            default:
                return false
            }
        }.value

        if success {
            statusMessage = "✓ Freed \(Format.bytes(item.sizeBytes)) from \(item.name)"
        }
        await scan()
    }

    public func cleanAllSafe() async {
        isCleaning = true
        defer { isCleaning = false }

        let bytesBefore = totalSafeBytes
        for item in items where item.isSafe {
            await clean(item: item)
        }
        statusMessage = "✓ Successfully reclaimed \(Format.bytes(bytesBefore)) of disk space!"
        await scan()
    }

    nonisolated private static func calcDirSize(_ url: URL, fm: FileManager) -> Int64 {
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let sz = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(sz)
            }
        }
        return total
    }

    nonisolated private static func removeContents(of dir: URL, fm: FileManager) -> Bool {
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return false }
        var ok = true
        for file in contents {
            do {
                try fm.removeItem(at: file)
            } catch {
                ok = false
            }
        }
        return ok
    }
}
