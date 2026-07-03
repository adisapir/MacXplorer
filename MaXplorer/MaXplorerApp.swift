import AppKit
import SwiftUI

@main
struct MaXplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var tabs = BrowserTabsViewModel()
    @StateObject private var settings = AppSettings()

    private var model: FileBrowserViewModel {
        tabs.activeModel
    }

    var body: some Scene {
        WindowGroup("MaXplorer") {
            ContentView()
                .environmentObject(tabs)
                .environmentObject(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
                .frame(minWidth: 980, minHeight: 620)
                .onAppear {
                    tabs.updateMaximumConcurrentTabs(settings.maximumConcurrentTabs)
                    tabs.applyListingOptions(DirectoryListingOptions(columns: settings.visibleColumns))
                }
                .onChange(of: settings.maximumConcurrentTabs) { _, maximumConcurrentTabs in
                    tabs.updateMaximumConcurrentTabs(maximumConcurrentTabs)
                }
                .onChange(of: settings.visibleColumns) { _, visibleColumns in
                    tabs.applyListingOptions(DirectoryListingOptions(columns: visibleColumns))
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MaXplorer") {
                    model.showAbout()
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    tabs.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!tabs.canAddTab)

                Button("Duplicate Tab") {
                    tabs.duplicateTab(tabs.selectedTabID)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!tabs.canAddTab)

                Divider()

                Button("Open") {
                    model.openSelected()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.selectedItem == nil)

                Button("Quick View") {
                    model.quickViewSelectedItem()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!model.canQuickViewSelectedItem)

                Button("New Folder") {
                    Task { await model.createFolder() }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!model.canCreateFolder)

                Divider()

                Button("Rename") {
                    model.requestRenameSelected()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedItem?.isNetworkLocation ?? true)

                Button("Move to Trash") {
                    model.requestTrashSelected()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!model.canTrashSelectedItems)

                Divider()

                Button("Add to Favorites") {
                    model.pinSelectedFolderToFavorites()
                }
                .disabled(!(model.selectedItem.map(model.canPinFolder) ?? false))

                Divider()

                Button("Reveal in Finder") {
                    model.revealSelectedInFinder()
                }
                .keyboardShortcut("r", modifiers: [.command, .control])
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    model.copySelectedItem()
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Cut") {
                    model.cutSelectedItem()
                }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(!model.canCutSelectedItem)

                Button("Paste") {
                    model.pasteItems(maximumConcurrentCopies: settings.maximumConcurrentCopiedFiles)
                }
                .keyboardShortcut("v", modifiers: .command)

                Divider()

                Button("Select All") {
                    model.selectAll()
                }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(!model.canSelectAll)

                Button("Copy Path") {
                    model.copySelectedPath()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
            }

            CommandMenu("View") {
                Button("Filter Items") {
                    model.shouldFocusFilter = true
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Reload") {
                    model.reload()
                }
                .keyboardShortcut("r", modifiers: .command)

                Toggle("Show Hidden Files", isOn: $tabs.showHiddenFiles)
                    .keyboardShortcut(".", modifiers: [.command, .shift])

                Toggle("Show Aliases", isOn: $tabs.showAliases)
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            CommandMenu("Tabs") {
                Button("Select Next Tab") {
                    tabs.selectNextTab()
                }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(!tabs.canCycleTabs)

                Button("Select Previous Tab") {
                    tabs.selectPreviousTab()
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(!tabs.canCycleTabs)
            }

            CommandMenu("Go") {
                Button("Back") {
                    model.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!model.canGoBack)

                Button("Forward") {
                    model.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!model.canGoForward)

                Button("Enclosing Folder") {
                    model.goUp()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!model.canGoUp)

                Button("Go to Folder...") {
                    model.showGoToFolder()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Divider()

                Button("Home") {
                    model.navigate(to: FileManager.default.homeDirectoryForCurrentUser)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Button("Downloads") {
                    model.navigate(to: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                }

                Divider()

                Button("Connect to Server") {
                    model.showConnectToServer()
                }
                .keyboardShortcut("k", modifiers: .command)
            }

            CommandMenu("Tools") {
                Button("Open in Terminal") {
                    model.openSelectedInTerminal()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Copy Path") {
                    model.copySelectedPath()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}
