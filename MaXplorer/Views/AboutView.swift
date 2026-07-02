import AppKit
import SwiftUI

/// Bundle-derived app metadata shown on the About surface.
enum AppInfo {
    static let name: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "MaXplorer"
    }()

    static let shortVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }()

    static let buildNumber: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }()

    static var versionSummary: String {
        "Version \(shortVersion) (\(buildNumber))"
    }

    static let tagline = "A native macOS file manager with Windows Explorer-style navigation and a modern Mac feel."
}

/// Modern, glass-forward About surface rendered directly on the main app
/// canvas (not a separate window). Includes a button that opens the bundled
/// changelog in a popup sheet.
struct AboutView: View {
    @State private var isChangelogPresented = false

    private let highlights: [Highlight] = [
        Highlight(icon: "rectangle.split.3x1", title: "Tabbed Browsing", detail: "Explore multiple folders at once."),
        Highlight(icon: "bolt.horizontal.circle", title: "Fast Copy Queue", detail: "Live progress with conflict handling."),
        Highlight(icon: "network", title: "Network Aware", detail: "Browse and connect to servers."),
        Highlight(icon: "sparkles", title: "Liquid Glass", detail: "Tuned for the latest macOS.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                highlightsGrid

                actions

                Text("© 2026 MaXplorer. Crafted for macOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backdrop)
        .sheet(isPresented: $isChangelogPresented) {
            ChangelogSheet {
                isChangelogPresented = false
            }
        }
    }

    private var header: some View {
        VStack(spacing: 18) {
            Image(nsImage: AppInfo.iconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 132, height: 132)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)

            VStack(spacing: 8) {
                Text(AppInfo.name)
                    .font(.system(size: 40, weight: .bold, design: .rounded))

                Text(AppInfo.versionSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: Capsule())

                Text(AppInfo.tagline)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
    }

    private var highlightsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            ForEach(highlights) { highlight in
                HStack(spacing: 14) {
                    Image(systemName: highlight.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(highlight.title)
                            .font(.headline)
                        Text(highlight.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var actions: some View {
        Button {
            isChangelogPresented = true
        } label: {
            Label("View Changelog", systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.16), Color.clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private struct Highlight: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }
}

extension AppInfo {
    /// The runtime-generated Dock/Finder icon, reused for the About header.
    static let iconImage: NSImage = AppIconFactory.makeIcon()
}

/// Loads the bundled `ChangeLog.md` copied in by a build phase.
enum ChangelogLoader {
    static func load() -> String {
        guard let url = Bundle.main.url(forResource: "ChangeLog", withExtension: "md"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "# Change Log\n\nNo changelog is available in this build."
        }

        return contents
    }
}

/// Popup window (sheet) that renders the changelog markdown.
private struct ChangelogSheet: View {
    let onClose: () -> Void

    private let entries: [ChangelogLine] = ChangelogParser.parse(ChangelogLoader.load())

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)

                Text("Change Log")
                    .font(.headline)

                Spacer(minLength: 16)

                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(.bar)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(entries) { line in
                        ChangelogLineView(line: line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 560, minHeight: 460)
    }
}

private struct ChangelogLineView: View {
    let line: ChangelogLine

    var body: some View {
        switch line.kind {
        case .title:
            Text(line.text)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(.bottom, 2)
        case .section:
            Text(line.text)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 8)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                Text(line.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
        case .body:
            Text(line.text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

struct ChangelogLine: Identifiable {
    enum Kind {
        case title
        case section
        case bullet
        case body
    }

    let id = UUID()
    let kind: Kind
    let text: String
}

/// Minimal, changelog-focused markdown parser: handles `#`/`##` headings and
/// `-`/`*` bullets, treating everything else as body text.
enum ChangelogParser {
    static func parse(_ markdown: String) -> [ChangelogLine] {
        markdown
            .components(separatedBy: .newlines)
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else {
                    return nil
                }

                if line.hasPrefix("## ") {
                    return ChangelogLine(kind: .section, text: String(line.dropFirst(3)))
                }
                if line.hasPrefix("# ") {
                    return ChangelogLine(kind: .title, text: String(line.dropFirst(2)))
                }
                if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    return ChangelogLine(kind: .bullet, text: String(line.dropFirst(2)))
                }

                return ChangelogLine(kind: .body, text: line)
            }
    }
}
