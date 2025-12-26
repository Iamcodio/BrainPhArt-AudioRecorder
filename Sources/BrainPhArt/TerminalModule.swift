import SwiftUI
import AppKit

// MARK: - Terminal Tab View

struct TerminalTabView: View {
    @State private var commandInput = ""
    @State private var outputText = ""
    @State private var isRunning = false
    @State private var currentProcess: Process?
    @FocusState private var isInputFocused: Bool

    private let welcomeMessage = """
    Welcome to BrainPhArt Terminal
    ==============================

    Run shell commands here. Useful commands:
    - claude login     : Authenticate with Max Plan
    - claude --version : Check Claude CLI version
    - which claude     : Find Claude CLI location

    Note: For interactive programs (vim, etc), use Terminal.app

    """

    var body: some View {
        VStack(spacing: 0) {
            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    Text(outputText.isEmpty ? welcomeMessage : outputText)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("output")
                }
                .onChange(of: outputText) { _ in
                    withAnimation {
                        proxy.scrollTo("output", anchor: .bottom)
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // Input area
            HStack(spacing: 12) {
                Text("$")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)

                TextField("Enter command...", text: $commandInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .focused($isInputFocused)
                    .onSubmit {
                        runCommand()
                    }
                    .disabled(isRunning)

                if isRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button(action: runCommand) {
                        Image(systemName: "return")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(commandInput.isEmpty)
                }

                Button(action: clearOutput) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear output")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            isInputFocused = true
            // Check if claude CLI is available on startup
            Task {
                await checkClaudeCLI()
            }
        }
    }

    private func checkClaudeCLI() async {
        let result = await runShellCommand("which claude")
        if result.isEmpty || result.contains("not found") {
            outputText = welcomeMessage + "\n⚠️  Claude CLI not found in PATH\n   Install: npm install -g @anthropic-ai/claude-code\n\n"
        } else {
            outputText = welcomeMessage + "✓ Claude CLI found: \(result)\n"
        }
    }

    private func runCommand() {
        guard !commandInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let cmd = commandInput
        commandInput = ""
        isRunning = true

        // Add command to output
        outputText += "\n$ \(cmd)\n"

        Task {
            let result = await runShellCommand(cmd)
            await MainActor.run {
                outputText += result
                if !result.hasSuffix("\n") {
                    outputText += "\n"
                }
                isRunning = false
                isInputFocused = true
            }
        }
    }

    private func runShellCommand(_ command: String) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set proper environment
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:\(env["PATH"] ?? "")"
        env["TERM"] = "xterm-256color"
        process.environment = env

        // Set current directory
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        do {
            try process.run()

            await MainActor.run {
                currentProcess = process
            }

            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""

            await MainActor.run {
                currentProcess = nil
            }

            if process.terminationStatus != 0 && !error.isEmpty {
                return error
            }

            return output.isEmpty ? (error.isEmpty ? "(no output)" : error) : output
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func clearOutput() {
        outputText = welcomeMessage
    }
}

// MARK: - Quick Commands View

struct QuickCommandsView: View {
    let onCommand: (String) -> Void

    private let commands = [
        ("claude login", "Authenticate with Max Plan"),
        ("claude --version", "Check CLI version"),
        ("claude logout", "Sign out"),
        ("which claude", "Find CLI location"),
        ("pwd", "Current directory"),
        ("ls -la", "List files")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Commands")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            ForEach(commands, id: \.0) { cmd, desc in
                Button(action: { onCommand(cmd) }) {
                    HStack {
                        Text(cmd)
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
            }
        }
        .padding()
    }
}
