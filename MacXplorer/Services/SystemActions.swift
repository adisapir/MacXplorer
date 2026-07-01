import AppKit
import Foundation

enum SystemActions {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func applicationsForOpening(_ url: URL) -> [OpenWithApplication] {
        let applicationURLs = NSWorkspace.shared.urlsForApplications(toOpen: url)
        var seenURLs = Set<URL>()

        return applicationURLs.compactMap { applicationURL in
            let standardizedURL = applicationURL.standardizedFileURL
            guard !seenURLs.contains(standardizedURL) else {
                return nil
            }

            seenURLs.insert(standardizedURL)
            let bundle = Bundle(url: standardizedURL)
            let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            let name = displayName ?? bundleName ?? standardizedURL.deletingPathExtension().lastPathComponent

            return OpenWithApplication(
                url: standardizedURL,
                name: name,
                bundleIdentifier: bundle?.bundleIdentifier
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func open(_ url: URL, with application: OpenWithApplication) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: application.url, configuration: configuration) { _, error in
            if error != nil {
                NSWorkspace.shared.open(url)
            }
        }
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
        NSPasteboard.general.setString(url.isFileURL ? url.path : url.absoluteString, forType: .string)
    }

    static func copyFileURLs(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
    }

    static func fileURLsFromPasteboard() -> [URL] {
        let objects = NSPasteboard.general.readObjects(forClasses: [NSURL.self])
        return objects?.compactMap { object in
            guard let url = object as? URL, url.isFileURL else {
                return nil
            }

            return url.standardizedFileURL
        } ?? []
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
