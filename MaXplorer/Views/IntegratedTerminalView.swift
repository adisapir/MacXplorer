import AppKit
import SwiftUI

struct IntegratedTerminalView: View {
    let directoryURL: URL
    let onClose: () -> Void
    @StateObject private var session = TerminalSession()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                Text("Zsh")
                    .fontWeight(.semibold)
                Text(directoryURL.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    session.restart()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Restart terminal")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close terminal")
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.bar)

            TerminalTextView(output: session.output) { input in
                session.send(input)
            } onInterrupt: {
                session.interrupt()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 0, maxWidth: .infinity)
        .onAppear {
            session.start(in: directoryURL)
        }
        .onDisappear {
            session.stop()
        }
        .onChange(of: session.didExit) { _, didExit in
            if didExit {
                onClose()
            }
        }
    }
}

private struct TerminalTextView: NSViewRepresentable {
    let output: String
    let onInput: (String) -> Void
    let onInterrupt: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onInterrupt: onInterrupt)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = TerminalInputTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.onInput = context.coordinator.onInput
        textView.onInterrupt = context.coordinator.onInterrupt

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView,
              context.coordinator.lastOutput != output else { return }
        context.coordinator.lastOutput = output
        textView.textStorage?.setAttributedString(ANSITextRenderer.render(output))
        textView.scrollToEndOfDocument(nil)
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var lastOutput = ""
        let onInput: (String) -> Void
        let onInterrupt: () -> Void

        init(onInput: @escaping (String) -> Void, onInterrupt: @escaping () -> Void) {
            self.onInput = onInput
            self.onInterrupt = onInterrupt
        }
    }
}

private enum ANSITextRenderer {
    private static let expression = try? NSRegularExpression(pattern: "\\x1B\\[([0-9;]*)m")

    static func render(_ source: String) -> NSAttributedString {
        let source = applyingBackspaces(to: source)
        let result = NSMutableAttributedString()
        let nsSource = source as NSString
        var location = 0
        var foreground = NSColor.textColor
        var background = NSColor.textBackgroundColor
        var bold = false

        func attributes() -> [NSAttributedString.Key: Any] {
            [
                .foregroundColor: foreground,
                .backgroundColor: background,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: bold ? .bold : .regular)
            ]
        }

        guard let expression else {
            return NSAttributedString(string: source, attributes: attributes())
        }

        for match in expression.matches(in: source, range: NSRange(location: 0, length: nsSource.length)) {
            if match.range.location > location {
                result.append(NSAttributedString(
                    string: nsSource.substring(with: NSRange(location: location, length: match.range.location - location)),
                    attributes: attributes()
                ))
            }

            let parameters = match.range(at: 1).length == 0
                ? [0]
                : nsSource.substring(with: match.range(at: 1)).split(separator: ";").compactMap { Int($0) }
            for code in parameters {
                switch code {
                case 0:
                    foreground = .textColor
                    background = .textBackgroundColor
                    bold = false
                case 1: bold = true
                case 22: bold = false
                case 30...37: foreground = color(index: code - 30, bright: false)
                case 39: foreground = .textColor
                case 40...47: background = color(index: code - 40, bright: false)
                case 49: background = .textBackgroundColor
                case 90...97: foreground = color(index: code - 90, bright: true)
                case 100...107: background = color(index: code - 100, bright: true)
                default: break
                }
            }
            location = NSMaxRange(match.range)
        }

        if location < nsSource.length {
            result.append(NSAttributedString(
                string: nsSource.substring(from: location),
                attributes: attributes()
            ))
        }
        return result
    }

    private static func color(index: Int, bright: Bool) -> NSColor {
        let normal: [NSColor] = [.black, .systemRed, .systemGreen, .systemYellow, .systemBlue, .systemPurple, .systemCyan, .lightGray]
        let brightColors: [NSColor] = [.darkGray, .systemRed, .systemGreen, .systemYellow, .systemBlue, .systemPink, .systemTeal, .white]
        return (bright ? brightColors : normal)[index]
    }

    private static func applyingBackspaces(to source: String) -> String {
        var result = ""
        for character in source {
            if character == "\u{8}" {
                if !result.isEmpty, result.last != "\n" {
                    result.removeLast()
                }
            } else {
                result.append(character)
            }
        }
        return result.replacingOccurrences(
            of: " {20,}[^\\n]*% ",
            with: "",
            options: .regularExpression
        )
    }
}

private final class TerminalInputTextView: NSTextView {
    var onInput: ((String) -> Void)?
    var onInterrupt: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), event.charactersIgnoringModifiers == "c" {
            onInterrupt?()
            return
        }

        switch event.keyCode {
        case 36, 76:
            onInput?("\n")
        case 51:
            onInput?("\u{7f}")
        case 123:
            onInput?("\u{1b}[D")
        case 124:
            onInput?("\u{1b}[C")
        case 125:
            onInput?("\u{1b}[B")
        case 126:
            onInput?("\u{1b}[A")
        default:
            if let characters = event.characters, !characters.isEmpty {
                onInput?(characters)
            }
        }
    }
}
