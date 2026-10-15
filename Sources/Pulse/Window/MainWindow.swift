import SwiftUI
import AppKit
import PulseCore

struct MainWindowView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .background(Theme.bg)
            Divider().opacity(0.35)

            ZStack {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .trailing) {
                if let app = store.app(store.selectedAppID) {
                    AppDetailPanel(app: app, store: store)
                        .frame(width: 320)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            StatusBar(store: store)
        }
        .background(Theme.bg)
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator())
        .frame(minWidth: 1080, minHeight: 640)
        .onAppear { store.isWindowOpen = true; store.wake() }
        .onDisappear { store.isWindowOpen = false }
        .onReceive(NotificationCenter.default.publisher(for: .openPulseMainWindow)) { _ in
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: store.activeTab) { _, _ in store.selectedAppID = nil }
    }

    // MARK: - Fixed Sticky Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Traffic lights reserve area (draggable)
            Color.clear
                .frame(width: 72, height: 52)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())

            TabBar(selection: $store.activeTab)

            // Blank window drag area
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: 52)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.border))
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    @ViewBuilder private var content: some View {
        if !store.hasData {
            ProgressView().controlSize(.small)
        } else {
            switch store.activeTab {
            case .overview: OverviewView(store: store)
            case .actionCenter: ActionCenterView(store: store)
            case .apps: AppsView(store: store)
            case .battery: BatteryView(store: store)
            case .storage: StorageView(store: store)
            case .projects: ProjectsView(store: store)
            case .agents: AgentsView(store: store)
            default: MetricView(tab: store.activeTab, store: store)
            }
        }
    }
}

// MARK: - Tab Bar

struct TabBar: View {
    @Binding var selection: PulseTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(PulseTab.allCases.enumerated()), id: \.element) { i, t in
                let on = t == selection
                let shortcutChar: Character? = i < 9 ? Character("\(i + 1)") : (i == 9 ? "0" : nil)

                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = t }
                } label: {
                    HStack(spacing: 4.5) {
                        Image(systemName: t.icon)
                            .font(.system(size: 11, weight: on ? .bold : .medium))
                        Text(t.title)
                            .font(.system(size: 11.5, weight: on ? .semibold : .medium))
                            .fixedSize()
                    }
                    .foregroundStyle(on ? t.color : Theme.inkSecondary)
                    .padding(.horizontal, 7.5)
                    .frame(height: 26)
                    .background(on ? t.color.opacity(0.14) : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(shortcutChar != nil ? "\(t.title) (⌘\(String(shortcutChar!)))" : t.title)
                .modifier(TabShortcutModifier(char: shortcutChar))
            }
        }
        .padding(2.5)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.border))
        .fixedSize()
    }
}

private struct TabShortcutModifier: ViewModifier {
    let char: Character?
    func body(content: Content) -> some View {
        if let char {
            content.keyboardShortcut(KeyEquivalent(char), modifiers: .command)
        } else {
            content
        }
    }
}

// MARK: - Status Bar

struct StatusBar: View {
    let store: AppStore
    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            HStack(spacing: 6) {
                Circle().fill(Theme.green).frame(width: 6, height: 6)
                Text("\(store.snapshot.apps.count) apps · \(store.snapshot.processCount.formatted()) processes")
                Spacer()
                if store.snapshot.unmeasuredCount > 0 {
                    Image(systemName: "lock.shield").font(.system(size: 10))
                    Text("\(store.snapshot.unmeasuredCount) system processes can’t be measured without admin rights")
                        .lineLimit(1)
                }
                Text("·")
                Text("Every \(Int(store.currentInterval))s")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 14)
            .frame(height: 26)
        }
    }
}

// MARK: - Window Chrome Configurator

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let window = v.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Kept empty to prevent re-layout / safe-area jumps when switching apps!
    }
}
