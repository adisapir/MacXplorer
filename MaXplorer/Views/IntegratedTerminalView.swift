import AppKit
import SwiftUI
import SwiftTerm

struct IntegratedTerminalView: View {
    let directoryURL: URL
    let onClose: () -> Void

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

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close terminal")
            }
            .font(.system(size: 11))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.bar)

            SwiftTermSurface(directoryURL: directoryURL, onExit: onClose)
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, 10)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 0, maxWidth: .infinity)
    }
}

private struct SwiftTermSurface: NSViewRepresentable {
    let directoryURL: URL
    let onExit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onExit: onExit)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.nativeForegroundColor = .textColor
        terminal.nativeBackgroundColor = .textBackgroundColor
        terminal.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        terminal.caretColor = .controlAccentColor
        terminal.getTerminal().setCursorStyle(.steadyBlock)

        DispatchQueue.main.async {
            terminal.startProcess(
                executable: "/bin/zsh",
                args: ["-i"],
                environment: nil,
                execName: "-zsh",
                currentDirectory: directoryURL.path
            )
            context.coordinator.startMonitoring(terminal)
            terminal.window?.makeFirstResponder(terminal)
        }
        return terminal
    }

    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        context.coordinator.onExit = onExit
    }

    static func dismantleNSView(_ terminal: LocalProcessTerminalView, coordinator: Coordinator) {
        coordinator.isDismantling = true
        coordinator.stopMonitoring()
        terminal.terminate()
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var onExit: () -> Void
        var isDismantling = false
        private var processMonitor: Timer?
        private var hasObservedRunningProcess = false

        init(onExit: @escaping () -> Void) {
            self.onExit = onExit
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func startMonitoring(_ terminal: LocalProcessTerminalView) {
            stopMonitoring()
            hasObservedRunningProcess = terminal.process.running
            processMonitor = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak terminal] _ in
                guard let self, let terminal, !self.isDismantling else { return }
                if terminal.process.running {
                    self.hasObservedRunningProcess = true
                } else if self.hasObservedRunningProcess {
                    self.closeForTerminatedProcess()
                }
            }
        }

        func stopMonitoring() {
            processMonitor?.invalidate()
            processMonitor = nil
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            closeForTerminatedProcess()
        }

        private func closeForTerminatedProcess() {
            guard !isDismantling else { return }
            isDismantling = true
            stopMonitoring()
            DispatchQueue.main.async { [weak self] in
                self?.onExit()
            }
        }
    }
}
