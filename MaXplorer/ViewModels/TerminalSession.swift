import Foundation
import Combine
import Darwin

@_silgen_name("openpty")
private func openPseudoTerminal(
    _ master: UnsafeMutablePointer<Int32>,
    _ slave: UnsafeMutablePointer<Int32>,
    _ name: UnsafeMutablePointer<CChar>?,
    _ termios: OpaquePointer?,
    _ windowSize: OpaquePointer?
) -> Int32

@MainActor
final class TerminalSession: ObservableObject {
    @Published private(set) var output = ""
    @Published private(set) var isRunning = false
    @Published private(set) var didExit = false

    private var process: Process?
    private var terminalHandle: FileHandle?
    private var generation = UUID()
    private(set) var directoryURL: URL?

    func start(in directoryURL: URL) {
        stop()
        let generation = UUID()
        self.generation = generation
        didExit = false

        let process = Process()
        var masterDescriptor: Int32 = -1
        var slaveDescriptor: Int32 = -1
        guard openPseudoTerminal(&masterDescriptor, &slaveDescriptor, nil, nil, nil) == 0 else {
            output = "Unable to create terminal: \(String(cString: strerror(errno)))\n"
            isRunning = false
            return
        }
        var initialWindowSize = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterDescriptor, TIOCSWINSZ, &initialWindowSize)
        let terminalHandle = FileHandle(fileDescriptor: masterDescriptor, closeOnDealloc: true)
        let shellHandle = FileHandle(fileDescriptor: slaveDescriptor, closeOnDealloc: true)

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Use a clean interactive Zsh prompt. User themes commonly rely on cursor
        // positioning and a right-side prompt; this lightweight terminal surface
        // intentionally supports text and ANSI styling, not full screen emulation.
        process.arguments = ["-d", "-f", "-i"]
        process.currentDirectoryURL = directoryURL
        process.standardInput = shellHandle
        process.standardOutput = shellHandle
        process.standardError = shellHandle
        process.environment = ProcessInfo.processInfo.environment.merging([
            "TERM": "dumb",
            "CLICOLOR": "1",
            "PROMPT": "%n@%1~ %# ",
            "RPROMPT": ""
        ]) { _, new in new }

        let receive: @Sendable (FileHandle) -> Void = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = Self.cleanTerminalOutput(String(decoding: data, as: UTF8.self))
            Task { @MainActor [weak self] in
                self?.output.append(text)
            }
        }
        terminalHandle.readabilityHandler = receive
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.generation == generation else { return }
                self?.isRunning = false
                self?.didExit = true
            }
        }

        do {
            try process.run()
            try? shellHandle.close()
            self.process = process
            self.terminalHandle = terminalHandle
            self.directoryURL = directoryURL
            output = ""
            isRunning = true
        } catch {
            try? terminalHandle.close()
            try? shellHandle.close()
            output = "Unable to start Zsh: \(error.localizedDescription)\n"
            isRunning = false
        }
    }

    func send(_ text: String) {
        guard isRunning, let data = text.data(using: .utf8) else { return }
        do {
            try terminalHandle?.write(contentsOf: data)
        } catch {
            output.append("\nTerminal input failed: \(error.localizedDescription)\n")
        }
    }

    nonisolated private static func cleanTerminalOutput(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: "\\x1B\\][^\\x07]*\\x07",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\x1B\\[(?![0-9;]*m)[0-?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
        return result.replacingOccurrences(of: "\r", with: "")
    }

    func interrupt() {
        process?.interrupt()
    }

    func restart() {
        guard let directoryURL else { return }
        start(in: directoryURL)
    }

    func stop() {
        generation = UUID()
        terminalHandle?.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        try? terminalHandle?.close()
        process = nil
        terminalHandle = nil
        isRunning = false
    }

    deinit {
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}
