import Foundation
import AppKit
import PulseCore

public enum StorageCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All Categories"
    case apps = "Applications"
    case developer = "Developer"
    case caches = "Caches & Logs"
    case largeFiles = "Large Files"
    case trash = "Trash"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: "square.grid.2x2.fill"
        case .apps: "app.badge.fill"
        case .developer: "hammer.fill"
        case .caches: "archivebox.fill"
        case .largeFiles: "doc.badge.arrow.up.fill"
        case .trash: "trash.fill"
        }
    }
}

public struct StorageItem: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let category: StorageCategory
    public let sizeBytes: Int64
    public let isDeletable: Bool
    public let iconName: String?
    public let isAppBundle: Bool

    public init(id: String, name: String, path: String, category: StorageCategory, sizeBytes: Int64, isDeletable: Bool, iconName: String? = nil, isAppBundle: Bool = false) {
        self.id = id; self.name = name; self.path = path; self.category = category
        self.sizeBytes = sizeBytes; self.isDeletable = isDeletable; self.iconName = iconName; self.isAppBundle = isAppBundle
    }
}

public struct VolumeStats: Sendable {
    public var totalBytes: Int64 = 0
    public var freeBytes: Int64 = 0
    public var usedBytes: Int64 = 0

    public var percentUsed: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
}

@MainActor
@Observable
public final class StorageScanner {
    public var items: [StorageItem] = []
    public var volume = VolumeStats()
    public var isScanning: Bool = false
    public var statusMessage: String? = nil
    public var selectedCategory: StorageCategory = .all
    public var searchQuery: String = ""

    // Computed totals by category
    public var totalAppsBytes: Int64 = 0
    public var totalDevBytes: Int64 = 0
    public var totalCachesBytes: Int64 = 0
    public var totalLargeFilesBytes: Int64 = 0
    public var totalTrashBytes: Int64 = 0

    public init() {
        Task { await scanAll() }
    }

    public func scanAll() async {
        isScanning = true
        defer { isScanning = false }

        // 1. Read Root Volume Stats
        updateVolumeStats()

        // 2. Scan Storage Items in Background
        let scanned = await Task.detached(priority: .utility) { () -> [StorageItem] in
            var list: [StorageItem] = []
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser

            // A. Applications
            let appDirs = [
                URL(fileURLWithPath: "/Applications"),
                home.appendingPathComponent("Applications")
            ]
            for appDir in appDirs {
                if let apps = try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: .skipsHiddenFiles) {
                    for appURL in apps where appURL.pathExtension == "app" {
                        let size = Self.calculatePathSize(appURL, fm: fm)
                        if size > 10_000_000 { // >= 10MB
                            list.append(StorageItem(
                                id: appURL.path,
                                name: appURL.deletingPathExtension().lastPathComponent,
                                path: appURL.path,
                                category: .apps,
                                sizeBytes: size,
                                isDeletable: !appURL.path.hasPrefix("/System/"),
                                iconName: "app.fill",
                                isAppBundle: true
                            ))
                        }
                    }
                }
            }

            // B. Developer Build & Cache Directories
            let devTargets: [(name: String, path: URL, safe: Bool)] = [
                ("Xcode DerivedData", home.appendingPathComponent("Library/Developer/Xcode/DerivedData"), true),
                ("Xcode iOS Simulators", home.appendingPathComponent("Library/Developer/CoreSimulator/Devices"), true),
                ("Swift PM & Build Cache", home.appendingPathComponent("Library/Caches/org.swift.swiftpm"), true),
                ("Node / npm Cache", home.appendingPathComponent(".npm"), true),
                ("pnpm Store", home.appendingPathComponent("Library/Caches/pnpm"), true),
                ("Yarn Cache", home.appendingPathComponent("Library/Caches/Yarn"), true),
                ("Homebrew Cache", home.appendingPathComponent("Library/Caches/Homebrew"), true),
                ("CocoaPods Cache", home.appendingPathComponent("Library/Caches/CocoaPods"), true),
                ("Playwright Browser Binaries", home.appendingPathComponent("Library/Caches/ms-playwright"), true),
                ("Rust / Cargo Registry", home.appendingPathComponent(".cargo/registry"), true)
            ]

            for target in devTargets {
                let size = Self.calculatePathSize(target.path, fm: fm)
                if size > 5_000_000 {
                    list.append(StorageItem(
                        id: target.path.path,
                        name: target.name,
                        path: target.path.path,
                        category: .developer,
                        sizeBytes: size,
                        isDeletable: target.safe,
                        iconName: "hammer.fill",
                        isAppBundle: false
                    ))
                }
            }

            // C. Caches & Logs
            let cacheTargets: [(name: String, path: URL)] = [
                ("User Caches", home.appendingPathComponent("Library/Caches")),
                ("Diagnostic & Crash Logs", home.appendingPathComponent("Library/Logs")),
                ("App Updater Staging", home.appendingPathComponent("Library/Caches/com.apple.nsurlsessiond"))
            ]
            for target in cacheTargets {
                let size = Self.calculatePathSize(target.path, fm: fm)
                if size > 20_000_000 {
                    list.append(StorageItem(
                        id: target.path.path,
                        name: target.name,
                        path: target.path.path,
                        category: .caches,
                        sizeBytes: size,
                        isDeletable: true,
                        iconName: "archivebox.fill",
                        isAppBundle: false
                    ))
                }
            }

            // D. Trash Bin
            let trashDir = home.appendingPathComponent(".Trash")
            let trashSize = Self.calculatePathSize(trashDir, fm: fm)
            if trashSize > 0 {
                list.append(StorageItem(
                    id: trashDir.path,
                    name: "Trash Bin",
                    path: trashDir.path,
                    category: .trash,
                    sizeBytes: trashSize,
                    isDeletable: true,
                    iconName: "trash.fill",
                    isAppBundle: false
                ))
            }

            // E. Large Files (> 100 MB in Downloads & Documents)
            let scanFolders = [
                home.appendingPathComponent("Downloads"),
                home.appendingPathComponent("Documents")
            ]
            for folder in scanFolders {
                if let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsPackageDescendants, .skipsHiddenFiles]) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if let res = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                           res.isRegularFile == true,
                           let fileSize = res.fileSize,
                           fileSize >= 100_000_000 { // >= 100 MB
                            list.append(StorageItem(
                                id: fileURL.path,
                                name: fileURL.lastPathComponent,
                                path: fileURL.path,
                                category: .largeFiles,
                                sizeBytes: Int64(fileSize),
                                isDeletable: true,
                                iconName: "doc.fill",
                                isAppBundle: false
                            ))
                        }
                    }
                }
            }

            // Sort descending by size
            return list.sorted { $0.sizeBytes > $1.sizeBytes }
        }.value

        self.items = scanned
        recomputeCategoryTotals()
    }

    public func clean(item: StorageItem) async {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: item.path)

        if item.category == .trash {
            // Empty trash
            try? fm.removeItem(at: url)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        } else if item.category == .developer || item.category == .caches {
            // Delete folder contents but keep the folder itself
            if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                for file in contents {
                    try? fm.removeItem(at: file)
                }
            }
        } else if item.isDeletable {
            // Move item to trash safely
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }

        self.statusMessage = "Cleaned \(item.name) (\(Format.bytes(item.sizeBytes)))"
        await scanAll()
    }

    public func revealInFinder(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    private func updateVolumeStats() {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0
            self.volume = VolumeStats(
                totalBytes: total,
                freeBytes: free,
                usedBytes: max(0, total - free)
            )
        }
    }

    private func recomputeCategoryTotals() {
        totalAppsBytes = items.filter { $0.category == .apps }.map(\.sizeBytes).reduce(0, +)
        totalDevBytes = items.filter { $0.category == .developer }.map(\.sizeBytes).reduce(0, +)
        totalCachesBytes = items.filter { $0.category == .caches }.map(\.sizeBytes).reduce(0, +)
        totalLargeFilesBytes = items.filter { $0.category == .largeFiles }.map(\.sizeBytes).reduce(0, +)
        totalTrashBytes = items.filter { $0.category == .trash }.map(\.sizeBytes).reduce(0, +)
    }

    private nonisolated static func calculatePathSize(_ url: URL, fm: FileManager) -> Int64 {
        var size: Int64 = 0
        guard fm.fileExists(atPath: url.path) else { return 0 }

        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }

        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsPackageDescendants]) else {
            return 0
        }
        while let fileURL = enumerator.nextObject() as? URL {
            if let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               res.isRegularFile == true,
               let s = res.fileSize {
                size += Int64(s)
            }
        }
        return size
    }
}
