import AppKit
import SwiftUI

@main
struct MacXplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = FileBrowserViewModel(
        fileSystem: LocalFileSystemService()
    )
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup("MacXplorer") {
            ContentView()
                .environmentObject(model)
                .environmentObject(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open") {
                    model.openSelected()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.selectedItem == nil)

                Button("New Folder") {
                    Task { await model.createFolder() }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!model.canCreateFolder)

                Divider()

                Button("Rename") {
                    model.requestRenameSelected()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(model.selectedItem?.isNetworkLocation ?? true)

                Button("Move to Trash") {
                    model.requestTrashSelected()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedItem?.isNetworkLocation ?? true)

                Divider()

                Button("Add to Favorites") {
                    model.pinSelectedFolderToFavorites()
                }
                .disabled(!(model.selectedItem.map(model.canPinFolder) ?? false))

                Divider()

                Button("Reveal in Finder") {
                    model.revealSelectedInFinder()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    model.cutSelectedItem()
                }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(!model.canCutSelectedItem)

                Button("Paste") {
                    Task { await model.pasteCutItems() }
                }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(!model.canPasteCutItems)

                Divider()

                Button("Copy Path") {
                    model.copySelectedPath()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
            }

            CommandMenu("View") {
                Button("Reload") {
                    model.reload()
                }
                .keyboardShortcut("r", modifiers: .command)

                Toggle("Show Hidden Files", isOn: $model.showHiddenFiles)
                    .keyboardShortcut(".", modifiers: [.command, .shift])
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
