import SwiftUI

// MARK: - Block model

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletList(items: [String])
    case codeBlock(code: String, language: String?)
    case table(header: [String], rows: [[String]])
}

// MARK: - Parser

enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Headings
            if trimmed.hasPrefix("### ") {
                blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("## ") {
                blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("# ") {
                blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            // Fenced code block
            if trimmed.hasPrefix("```") {
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                i += 1
                var codeLines: [String] = []
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1 // consume closing ```
                blocks.append(.codeBlock(
                    code: codeLines.joined(separator: "\n"),
                    language: lang.isEmpty ? nil : String(lang)
                ))
                continue
            }

            // Table (rows start with |)
            if trimmed.hasPrefix("|") {
                var tableLines: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    tableLines.append(lines[i])
                    i += 1
                }
                guard tableLines.count >= 2 else { continue }
                let header = parseTableRow(tableLines[0])
                // tableLines[1] is the separator row (| --- | --- |) — skip it
                let rows = tableLines.dropFirst(2).map { parseTableRow($0) }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("- ") { items.append(String(t.dropFirst(2))); i += 1 }
                    else if t.hasPrefix("* ") { items.append(String(t.dropFirst(2))); i += 1 }
                    else { break }
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            // Paragraph — collect until blank line or block-level marker
            var paraLines: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if t.hasPrefix("#") || t.hasPrefix("```") || t.hasPrefix("|")
                    || t.hasPrefix("- ") || t.hasPrefix("* ") { break }
                paraLines.append(t)
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(text: paraLines.joined(separator: " ")))
            }
        }

        return blocks
    }

    private static func parseTableRow(_ line: String) -> [String] {
        line.split(separator: "|", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != "---" && !$0.allSatisfy({ $0 == "-" || $0 == ":" }) }
    }
}

// MARK: - Renderer

struct MarkdownDocumentView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] { MarkdownBlockParser.parse(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(for: block)
                    .padding(.bottom, bottomPadding(for: block, nextBlock: index + 1 < blocks.count ? blocks[index + 1] : nil))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level: level))
                .padding(.top, level == 1 ? 0 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let text):
            Text(inline(text))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(inline(item))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .codeBlock(let code, _):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }

        case .table(let header, let rows):
            tableView(header: header, rows: rows)
        }
    }

    @ViewBuilder
    private func tableView(header: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(header.enumerated()), id: \.offset) { _, col in
                    Text(col)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, col in
                        Text(inline(col))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                    }
                }
                .background(idx % 2 == 1 ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)

                if idx < rows.count - 1 {
                    Divider().opacity(0.4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    // MARK: - Helpers

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 22, weight: .bold, design: .rounded)
        case 2: return .system(size: 16, weight: .semibold, design: .rounded)
        default: return .headline
        }
    }

    private func bottomPadding(for block: MarkdownBlock, nextBlock: MarkdownBlock?) -> CGFloat {
        if case .heading(let level, _) = block { return level == 1 ? 8 : 6 }
        if case .heading = nextBlock { return 16 }
        return 10
    }

    /// Renders inline markdown (bold, italic, code, links) via AttributedString.
    private func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
