import SwiftUI
import PulseCore

struct AppsView: View {
    @Bindable var store: AppStore
    @State private var filter = ""
    @State private var primaryMetric: AppMetric = .memory

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apps")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("Helpers and child processes folded into each application")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.inkSecondary)
                        TextField("Filter apps...", text: $filter)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .frame(width: 110)
                        if !filter.isEmpty {
                            Button { filter = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border))

                    Picker("Metric", selection: $primaryMetric) {
                        ForEach(AppMetric.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }
                .padding(.horizontal, 4)

                AppTable(store: store, primary: primaryMetric, filter: filter, showDescription: true)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }
}
