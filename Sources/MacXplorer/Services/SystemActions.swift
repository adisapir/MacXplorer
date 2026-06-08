import AppKit
import Foundation

enum SystemActions {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func connectToServer(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openInTerminal(_ url: URL) {
        let directory = directoryURL(for: url)
        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return openInTerminalWithAppleScript(directory)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([directory], withApplicationAt: terminalURL, configuration: configuration) { _, error in
            if error != nil {
                openInTerminalWithAppleScript(directory)
            }
        }
    }

    private static func openInTerminalWithAppleScript(_ directory: URL) {
        let script = """
        set terminalPath to "\(escapedForAppleScript(directory.path))"
        set terminalCommand to "cd " & quoted form of terminalPath
        tell application "Terminal"
            activate
            do script terminalCommand
            activate
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    static func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    private static func directoryURL(for url: URL) -> URL {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return resourceValues?.isDirectory == true ? url : url.deletingLastPathComponent()
    }

    private static func escapedForAppleScript(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
