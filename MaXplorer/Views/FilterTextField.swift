import AppKit
import SwiftUI

/// Allows external callers (menu commands, etc.) to make the filter field
/// first responder without going through SwiftUI's @FocusState, which cannot
/// steal focus from an NSTableView held by SwiftUI's Table.
final class FilterFocusProxy {
    var activate: (() -> Void)?

    func focus() { activate?() }
}

/// AppKit-backed text field for the folder filter.
///
/// Using NSViewRepresentable lets `window.makeFirstResponder()` be called
/// directly, which is the only reliable way to move focus away from
/// an NSTableView that is currently first responder.
struct FilterTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let proxy: FilterFocusProxy

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        proxy.activate = { [weak nsView] in
            guard let nsView, let window = nsView.window else { return }
            window.makeFirstResponder(nsView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) { _text = text }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        /// Escape clears the filter and resigns first responder.
        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            text = ""
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}
