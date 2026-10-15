import SwiftUI
import AppKit
import PulseCore

struct StorageView: View {
    @Bindable var store: AppStore
    @State private var scanner = StorageScanner()
    @State private var pendingDeleteItem: StorageItem?
    @State private var showConfirmDelete: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // MARK: Top Disk Usage Overview Hero
                    diskOverviewHero

                    // Feedback Banner
                    if let msg = scanner.statusMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.green)
                            Text(msg)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Button {
                                scanner.statusMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Theme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.green.opacity(0.3)))
                    }

                    // MARK: Category Switcher & Search Bar
                    HStack(spacing: 12) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(StorageCategory.allCases) { cat in
                                    let isSelected = scanner.selectedCategory == cat
                                    Button {
                                        withAnimation(.snappy(duration: 0.2)) {
                                            scanner.selectedCategory = cat
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: cat.icon)
                                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                            Text(cat.rawValue)
                                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                            
                                            // Size badge
                                            let catSize = categorySize(cat)
                                            if catSize > 0 && cat != .all {
                                                Text(Format.bytes(catSize))
                                                    .font(.system(size: 10.5, weight: .bold))
                                                    .foregroundStyle(isSelected ? .white : Theme.inkSecondary)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(isSelected ? Color.white.opacity(0.25) : Theme.cardHover, in: Capsule())
                                            }
                                        }
                                        .foregroundStyle(isSelected ? .white : Theme.inkSecondary)
                                        .padding(.horizontal, 11)
                                        .frame(height: 28)
                                        .background(isSelected ? Theme.disk : Theme.card, in: Capsule())
                                        .overlay(Capsule().stroke(Theme.border))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Spacer()

                        // Search Box
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkTertiary)
                            TextField("Filter items...", text: $scanner.searchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .frame(width: 140)
                            if !scanner.searchQuery.isEmpty {
                                Button { scanner.searchQuery = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.inkTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border))

                        // Refresh Button
                        Button {
                            Task { await scanner.scanAll() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.inkSecondary)
                                .frame(width: 28, height: 28)
                                .background(Theme.card, in: Circle())
                                .overlay(Circle().stroke(Theme.border))
                                .rotationEffect(.degrees(scanner.isScanning ? 360 : 0))
                                .animation(scanner.isScanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: scanner.isScanning)
                        }
                        .buttonStyle(.plain)
                        .help("Rescan storage")
                    }

                    // MARK: Items List
                    let filtered = filteredItems
                    if filtered.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 24))
                                .foregroundStyle(Theme.inkTertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scanner.isScanning ? "Scanning Macintosh HD storage..." : "No items match your filter")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text(scanner.isScanning ? "Calculating application bundle and cache directory sizes." : "Try selecting another category or clearing your search query.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer()
                        }
                        .padding(20)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        VStack(spacing: 8) {
                            ForEach(filtered) { item in
                                storageItemRow(item)
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
            "Clean \(pendingDeleteItem?.name ?? "Item")?",
            isPresented: $showConfirmDelete,
            titleVisibility: .visible
        ) {
            Button("Clean / Remove", role: .destructive) {
                if let it = pendingDeleteItem {
                    Task { await scanner.clean(item: it) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let it = pendingDeleteItem {
                Text("Are you sure you want to clean \(it.name) (\(Format.bytes(it.sizeBytes)))? This will reclaim free space on your drive.")
            }
        }
    }

    // MARK: - Disk Overview Hero Card

    private var diskOverviewHero: some View {
        let vol = scanner.volume
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.disk)
                    .frame(width: 48, height: 48)
                    .background(Theme.disk.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Macintosh HD")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.ink)

                        Text("\(Format.bytes(vol.usedBytes)) used of \(Format.bytes(vol.totalBytes))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    Text("\(Format.bytes(vol.freeBytes)) Available")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.green)
                }

                Spacer()

                if scanner.totalTrashBytes > 0 {
                    Button {
                        if let trashItem = scanner.items.first(where: { $0.category == .trash }) {
                            pendingDeleteItem = trashItem
                            showConfirmDelete = true
                        }
                    } label: {
                        Label("Empty Trash (\(Format.bytes(scanner.totalTrashBytes)))", systemImage: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Theme.red, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Segmented Storage Bar
            GeometryReader { geo in
                let total = max(1, Double(vol.totalBytes))
                let appsWidth = max(2, geo.size.width * CGFloat(Double(scanner.totalAppsBytes) / total))
                let devWidth = max(2, geo.size.width * CGFloat(Double(scanner.totalDevBytes) / total))
                let cachesWidth = max(2, geo.size.width * CGFloat(Double(scanner.totalCachesBytes) / total))
                let largeWidth = max(2, geo.size.width * CGFloat(Double(scanner.totalLargeFilesBytes) / total))
                let otherWidth = max(2, geo.size.width * CGFloat(max(0, Double(vol.usedBytes - scanner.totalAppsBytes - scanner.totalDevBytes - scanner.totalCachesBytes - scanner.totalLargeFilesBytes)) / total))
                let freeWidth = max(2, geo.size.width * CGFloat(Double(vol.freeBytes) / total))

                HStack(spacing: 2) {
                    // Apps (Blue)
                    Rectangle()
                        .fill(Theme.cpu)
                        .frame(width: appsWidth)
                    // Developer (Orange)
                    Rectangle()
                        .fill(Theme.orange)
                        .frame(width: devWidth)
                    // Caches (Purple)
                    Rectangle()
                        .fill(Theme.memory)
                        .frame(width: cachesWidth)
                    // Large Files (Yellow)
                    Rectangle()
                        .fill(Theme.yellow)
                        .frame(width: largeWidth)
                    // Other / macOS System (Slate)
                    Rectangle()
                        .fill(Theme.inkSecondary.opacity(0.4))
                        .frame(width: otherWidth)
                    // Free Space (Light Green / Dim)
                    Rectangle()
                        .fill(Theme.green.opacity(0.3))
                        .frame(width: freeWidth)
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)

            // Legend Row
            HStack(spacing: 16) {
                legendItem(title: "Apps", size: scanner.totalAppsBytes, color: Theme.cpu)
                legendItem(title: "Developer", size: scanner.totalDevBytes, color: Theme.orange)
                legendItem(title: "Caches & Logs", size: scanner.totalCachesBytes, color: Theme.memory)
                legendItem(title: "Large Files", size: scanner.totalLargeFilesBytes, color: Theme.yellow)
                legendItem(title: "Free", size: vol.freeBytes, color: Theme.green)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkSecondary)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func legendItem(title: String, size: Int64, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 11, weight: .medium))
            Text(Format.bytes(size))
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
    }

    // MARK: - Storage Item Row

    private func storageItemRow(_ item: StorageItem) -> some View {
        HStack(spacing: 12) {
            // App or Folder Icon
            if item.isAppBundle {
                Image(nsImage: IconCache.icon(forPath: item.path))
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: item.iconName ?? "folder.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.category == .developer ? Theme.orange : (item.category == .caches ? Theme.memory : Theme.disk))
                    .frame(width: 28, height: 28)
                    .background(Theme.cardHover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    Text(item.category.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.raised, in: Capsule())
                }

                Text(item.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(Format.bytes(item.sizeBytes))
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)

            // Action Buttons
            HStack(spacing: 6) {
                Button {
                    scanner.revealInFinder(path: item.path)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 26, height: 26)
                        .background(Theme.cardHover, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                if item.isDeletable {
                    Button {
                        pendingDeleteItem = item
                        showConfirmDelete = true
                    } label: {
                        Image(systemName: item.category == .trash ? "trash.fill" : "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.red)
                            .frame(width: 26, height: 26)
                            .background(Theme.red.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(item.category == .trash ? "Empty Trash" : "Clean item")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var filteredItems: [StorageItem] {
        scanner.items.filter { item in
            let matchesCategory = (scanner.selectedCategory == .all) || (item.category == scanner.selectedCategory)
            let matchesSearch = scanner.searchQuery.isEmpty ||
                item.name.localizedCaseInsensitiveContains(scanner.searchQuery) ||
                item.path.localizedCaseInsensitiveContains(scanner.searchQuery)
            return matchesCategory && matchesSearch
        }
    }

    private func categorySize(_ cat: StorageCategory) -> Int64 {
        switch cat {
        case .all: return 0
        case .apps: return scanner.totalAppsBytes
        case .developer: return scanner.totalDevBytes
        case .caches: return scanner.totalCachesBytes
        case .largeFiles: return scanner.totalLargeFilesBytes
        case .trash: return scanner.totalTrashBytes
        }
    }
}
