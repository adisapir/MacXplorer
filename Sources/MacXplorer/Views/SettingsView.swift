import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.displayName)
                        .tag(appearance)
                }
            }
            .pickerStyle(.radioGroup)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Maximum number of concurrent tabs")
                    Spacer()
                    Text("\(settings.maximumConcurrentTabs)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { Double(settings.maximumConcurrentTabs) },
                        set: { settings.maximumConcurrentTabs = Int($0.rounded()) }
                    ),
                    in: Double(AppSettings.maximumConcurrentTabsRange.lowerBound)...Double(AppSettings.maximumConcurrentTabsRange.upperBound),
                    step: 1
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Number of manual folder to keep in history")
                    Spacer()
                    Text("\(settings.manualFolderHistoryLimit)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { Double(settings.manualFolderHistoryLimit) },
                        set: { settings.manualFolderHistoryLimit = Int($0.rounded()) }
                    ),
                    in: Double(AppSettings.manualFolderHistoryLimitRange.lowerBound)...Double(AppSettings.manualFolderHistoryLimitRange.upperBound),
                    step: 1
                )
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
