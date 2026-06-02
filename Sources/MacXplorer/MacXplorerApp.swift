import SwiftUI

@main
struct MacXplorerApp: App {
    @StateObject private var model = FileBrowserViewModel(
        fileSystem: LocalFileSystemService()
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Folder") {
                    Task { await model.createFolder() }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(after: .pasteboard) {
                Button("Copy Path") {
                    model.copySelectedPath()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

                Button("Open in Terminal") {
                    model.openSelectedInTerminal()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Reveal in Finder") {
                    model.revealSelectedInFinder()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
