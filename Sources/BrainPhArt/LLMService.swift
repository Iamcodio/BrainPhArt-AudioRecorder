import Foundation

// MARK: - LLM Response

struct LLMResponse {
    let text: String
    let model: String
    let tokensUsed: Int?
    let error: String?

    var isSuccess: Bool { error == nil }

    init(text: String, model: String = "claude-cli", tokensUsed: Int? = nil, error: String? = nil) {
        self.text = text
        self.model = model
        self.tokensUsed = tokensUsed
        self.error = error
    }
}

// MARK: - LLM Service (Claude CLI Wrapper)

actor LLMService {
    static let shared = LLMService()

    private init() {}

    // MARK: - Main API

    /// Send a prompt to Claude via CLI (uses Max Plan OAuth)
    func send(
        prompt: String,
        systemPrompt: String? = nil
    ) async -> LLMResponse {
        return await sendToClaude(prompt: prompt, systemPrompt: systemPrompt)
    }

    // MARK: - Claude CLI Implementation

    private func sendToClaude(prompt: String, systemPrompt: String?) async -> LLMResponse {
        // Build full prompt with system context if provided
        var fullPrompt = prompt
        if let system = systemPrompt {
            fullPrompt = "System: \(system)\n\nUser: \(prompt)"
        }

        // Use Process to run claude CLI
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "-p", fullPrompt]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Set environment to ensure proper PATH
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin:\(env["PATH"] ?? "")"
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus != 0 {
                // Check if it's an auth error
                if errorOutput.contains("not logged in") || errorOutput.contains("auth") {
                    return LLMResponse(
                        text: "",
                        error: "Not logged in. Run 'claude login' in Terminal tab to authenticate."
                    )
                }
                return LLMResponse(text: "", error: errorOutput.isEmpty ? "Claude CLI failed" : errorOutput)
            }

            return LLMResponse(text: output, error: nil)
        } catch {
            return LLMResponse(text: "", error: "Failed to run Claude CLI: \(error.localizedDescription)")
        }
    }
}
