import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.displayName)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.radioGroup)

                Picker("Color Theme Element", selection: $settings.colorTheme) {
                    ForEach(AppColorTheme.allCases) { colorTheme in
                        Text(colorTheme.settingsDisplayName)
                            .tag(colorTheme)
                    }
                }

                Toggle("Banded file and folder rows", isOn: $settings.showsBandedFileRows)

                HStack {
                    Text("Folder Icon Style")
                    Spacer()
                    Picker("Folder Icon Style", selection: $settings.folderIconStyle) {
                        ForEach(FolderIconStyle.allCases) { style in
                            Text(style.displayName)
                                .tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
            }

            Section("Workspace") {
                settingSlider(
                    title: "Maximum number of concurrent tabs",
                    value: $settings.maximumConcurrentTabs,
                    range: AppSettings.maximumConcurrentTabsRange
                )

                settingSlider(
                    title: "Folders kept in navigation history",
                    value: $settings.manualFolderHistoryLimit,
                    range: AppSettings.manualFolderHistoryLimitRange
                )
            }

            Section("Space Analyzer") {
                Picker("Default Mode", selection: $settings.defaultSpaceAnalyzerMode) {
                    ForEach(SpaceAnalyzerMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text("All Files Mode shows the complete scanned hierarchy. Drill-Down Mode shows only the current folder's contents and lets you open folders to explore the largest areas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("File Transfers") {
                settingSlider(
                    title: "Maximum number of concurrent copied files",
                    value: $settings.maximumConcurrentCopiedFiles,
                    range: AppSettings.maximumConcurrentCopiedFilesRange
                )

                settingSlider(
                    title: "Files kept in transfer history",
                    value: $settings.transferHistoryLimit,
                    range: AppSettings.transferHistoryLimitRange
                )
            }
        }
        .formStyle(.grouped)
        .padding(28)
        .frame(width: 620)
    }

    private func settingSlider(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }

            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
        }
        .padding(.vertical, 4)
    }
}
