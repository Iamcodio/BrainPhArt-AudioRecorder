import Foundation

// MARK: - Prompt Template

struct PromptTemplate: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var systemPrompt: String
    var userPromptTemplate: String  // Use {{TEXT}} as placeholder
    var category: PromptCategory
    var isBuiltIn: Bool = false

    func buildUserPrompt(with text: String) -> String {
        return userPromptTemplate.replacingOccurrences(of: "{{TEXT}}", with: text)
    }
}

enum PromptCategory: String, Codable, CaseIterable {
    case cleanup = "Cleanup"
    case grammar = "Grammar"
    case rewrite = "Rewrite"
    case summarize = "Summarize"
    case translate = "Translate"
    case custom = "Custom"
}

// MARK: - Prompt Manager

@MainActor
class PromptManager: ObservableObject {
    static let shared = PromptManager()

    @Published var prompts: [PromptTemplate] = []
    @Published var selectedPromptId: String?

    private let promptsURL: URL

    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/brainphart")
        promptsURL = appSupport.appendingPathComponent("prompts.json")

        loadPrompts()

        // Add built-in prompts if none exist
        if prompts.isEmpty {
            addBuiltInPrompts()
            savePrompts()
        }
    }

    // MARK: - Built-in Prompts

    private func addBuiltInPrompts() {
        prompts = [
            // Cleanup prompts
            PromptTemplate(
                name: "Clean Transcript",
                systemPrompt: "You are a transcript editor. Clean up the text while preserving the original meaning and voice. Fix obvious errors but don't change the style.",
                userPromptTemplate: "Clean up this transcript. Fix punctuation, capitalisation, and obvious transcription errors. Keep the original voice and meaning:\n\n{{TEXT}}",
                category: .cleanup,
                isBuiltIn: true
            ),
            PromptTemplate(
                name: "Remove Filler Words",
                systemPrompt: "You are a transcript editor. Remove filler words and verbal tics while keeping the content intact.",
                userPromptTemplate: "Remove filler words (um, uh, like, you know, basically, actually, sort of, kind of) from this text while keeping the meaning intact:\n\n{{TEXT}}",
                category: .cleanup,
                isBuiltIn: true
            ),

            // Grammar prompts
            PromptTemplate(
                name: "Fix Grammar",
                systemPrompt: "You are a grammar checker. Fix grammatical errors while preserving the original style and voice.",
                userPromptTemplate: "Fix any grammar, spelling, and punctuation errors in this text. Keep the original style:\n\n{{TEXT}}",
                category: .grammar,
                isBuiltIn: true
            ),
            PromptTemplate(
                name: "British English",
                systemPrompt: "You are an editor who converts text to British English conventions.",
                userPromptTemplate: "Convert this text to British English spelling and conventions (colour, organisation, -ise endings, etc.):\n\n{{TEXT}}",
                category: .grammar,
                isBuiltIn: true
            ),

            // Rewrite prompts
            PromptTemplate(
                name: "Make Concise",
                systemPrompt: "You are an editor who makes text more concise without losing meaning.",
                userPromptTemplate: "Make this text more concise. Remove redundancy and wordiness while keeping all important information:\n\n{{TEXT}}",
                category: .rewrite,
                isBuiltIn: true
            ),
            PromptTemplate(
                name: "Professional Tone",
                systemPrompt: "You are an editor who adjusts text to have a professional tone.",
                userPromptTemplate: "Rewrite this in a professional tone suitable for business communication:\n\n{{TEXT}}",
                category: .rewrite,
                isBuiltIn: true
            ),
            PromptTemplate(
                name: "Casual Tone",
                systemPrompt: "You are an editor who makes text more casual and conversational.",
                userPromptTemplate: "Rewrite this in a casual, friendly tone:\n\n{{TEXT}}",
                category: .rewrite,
                isBuiltIn: true
            ),

            // Summarize prompts
            PromptTemplate(
                name: "Summarize",
                systemPrompt: "You are a summarizer. Create clear, concise summaries.",
                userPromptTemplate: "Summarize this text in 2-3 sentences:\n\n{{TEXT}}",
                category: .summarize,
                isBuiltIn: true
            ),
            PromptTemplate(
                name: "Key Points",
                systemPrompt: "You extract key points from text.",
                userPromptTemplate: "Extract the key points from this text as a bullet list:\n\n{{TEXT}}",
                category: .summarize,
                isBuiltIn: true
            ),
            PromptTemplate(
                name: "Action Items",
                systemPrompt: "You extract action items and tasks from text.",
                userPromptTemplate: "Extract any action items, tasks, or to-dos from this text:\n\n{{TEXT}}",
                category: .summarize,
                isBuiltIn: true
            ),
        ]
    }

    // MARK: - CRUD Operations

    func addPrompt(_ prompt: PromptTemplate) {
        prompts.append(prompt)
        savePrompts()
    }

    func updatePrompt(_ prompt: PromptTemplate) {
        if let index = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[index] = prompt
            savePrompts()
        }
    }

    func deletePrompt(id: String) {
        prompts.removeAll { $0.id == id && !$0.isBuiltIn }
        savePrompts()
    }

    func getPrompt(id: String) -> PromptTemplate? {
        return prompts.first { $0.id == id }
    }

    func promptsByCategory(_ category: PromptCategory) -> [PromptTemplate] {
        return prompts.filter { $0.category == category }
    }

    // MARK: - Persistence

    private func loadPrompts() {
        guard FileManager.default.fileExists(atPath: promptsURL.path) else { return }

        do {
            let data = try Data(contentsOf: promptsURL)
            prompts = try JSONDecoder().decode([PromptTemplate].self, from: data)
        } catch {
            print("[PromptManager] Failed to load prompts: \(error)")
        }
    }

    private func savePrompts() {
        do {
            let data = try JSONEncoder().encode(prompts)
            try data.write(to: promptsURL)
        } catch {
            print("[PromptManager] Failed to save prompts: \(error)")
        }
    }

    // MARK: - Quick Access

    var cleanupPrompt: PromptTemplate? {
        prompts.first { $0.name == "Clean Transcript" }
    }

    var grammarPrompt: PromptTemplate? {
        prompts.first { $0.name == "Fix Grammar" }
    }
}
