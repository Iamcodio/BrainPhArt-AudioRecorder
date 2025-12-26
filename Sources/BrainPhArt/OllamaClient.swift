import Foundation

/// Client for interacting with local Ollama LLM for text classification and analysis.
actor OllamaClient {
    static let shared = OllamaClient()

    let baseURL: String = "http://localhost:11434"
    let defaultModel: String = "qwen2.5:3b"  // Small, fast model

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Error Types

    enum OllamaError: Error, LocalizedError {
        case serverNotRunning
        case invalidURL
        case invalidResponse
        case httpError(statusCode: Int)
        case decodingError(String)
        case modelNotFound(String)
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .serverNotRunning:
                return "Ollama server is not running. Start it with 'ollama serve'"
            case .invalidURL:
                return "Invalid Ollama API URL"
            case .invalidResponse:
                return "Invalid response from Ollama server"
            case .httpError(let statusCode):
                return "HTTP error from Ollama: \(statusCode)"
            case .decodingError(let message):
                return "Failed to decode Ollama response: \(message)"
            case .modelNotFound(let model):
                return "Model '\(model)' not found. Pull it with 'ollama pull \(model)'"
            case .generationFailed(let message):
                return "Generation failed: \(message)"
            }
        }
    }

    // MARK: - API Request/Response Types

    private struct GenerateRequest: Codable {
        let model: String
        let prompt: String
        let stream: Bool
        let options: GenerateOptions?
    }

    private struct GenerateOptions: Codable {
        let temperature: Float?
        let num_predict: Int?
    }

    private struct GenerateResponse: Codable {
        let model: String
        let response: String
        let done: Bool
        let context: [Int]?
        let total_duration: Int64?
        let load_duration: Int64?
        let prompt_eval_count: Int?
        let eval_count: Int?
    }

    private struct ModelsResponse: Codable {
        let models: [ModelInfo]
    }

    private struct ModelInfo: Codable {
        let name: String
        let modified_at: String?
        let size: Int64?
    }

    // MARK: - Core API Methods

    /// Generate a response from the LLM
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - model: Optional model name (defaults to qwen2.5:3b)
    /// - Returns: The generated text response
    func generate(prompt: String, model: String? = nil) async throws -> String {
        let targetModel = model ?? defaultModel

        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.invalidURL
        }

        let requestBody = GenerateRequest(
            model: targetModel,
            prompt: prompt,
            stream: false,
            options: GenerateOptions(temperature: 0.3, num_predict: 500)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw OllamaError.modelNotFound(targetModel)
        }

        guard httpResponse.statusCode == 200 else {
            throw OllamaError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            let generateResponse = try decoder.decode(GenerateResponse.self, from: data)
            return generateResponse.response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw OllamaError.decodingError(error.localizedDescription)
        }
    }

    /// Check if Ollama server is running and accessible
    /// - Returns: true if server responds, false otherwise
    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    /// List all available models on the Ollama server
    /// - Returns: Array of model names
    func listModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw OllamaError.invalidURL
        }

        let request = URLRequest(url: url)
        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw OllamaError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            let modelsResponse = try decoder.decode(ModelsResponse.self, from: data)
            return modelsResponse.models.map { $0.name }
        } catch {
            throw OllamaError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Classification Helpers

    /// Classify whether text contains private/sensitive information
    /// - Parameter text: The text to analyze
    /// - Returns: Tuple with isPrivate flag, confidence score (0-1), and reason
    func classifyPrivacy(text: String) async throws -> (isPrivate: Bool, confidence: Float, reason: String) {
        let prompt = """
        Analyze the following text and determine if it contains private or sensitive information.

        Private information includes:
        - Personal identifiable information (names, addresses, phone numbers, SSN, etc.)
        - Financial information (bank accounts, credit cards, income)
        - Health/medical information
        - Passwords, credentials, or security codes
        - Private conversations meant to be confidential
        - Location data or movement patterns
        - Personal relationships or intimate details

        Text to analyze:
        ---
        \(text)
        ---

        Respond in exactly this format:
        PRIVATE: [YES or NO]
        CONFIDENCE: [0.0 to 1.0]
        REASON: [Brief explanation in one sentence]
        """

        let response = try await generate(prompt: prompt)
        return parsePrivacyResponse(response)
    }

    /// Suggest a category for the given text
    /// - Parameter text: The text to categorize
    /// - Returns: Suggested category name
    func suggestCategory(text: String) async throws -> String {
        let prompt = """
        Categorize the following text into ONE of these categories:
        - Work: Professional tasks, meetings, projects, deadlines
        - Personal: Personal life, family, friends, hobbies
        - Ideas: Creative thoughts, brainstorming, future plans
        - Tasks: To-do items, reminders, action items
        - Notes: General observations, learning, references
        - Journal: Reflections, emotions, daily entries
        - Health: Medical, fitness, wellness related
        - Finance: Money, budgets, purchases, investments
        - Other: Doesn't fit other categories

        Text:
        ---
        \(text)
        ---

        Respond with ONLY the category name, nothing else.
        """

        let response = try await generate(prompt: prompt)
        let category = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate against known categories
        let validCategories = ["Work", "Personal", "Ideas", "Tasks", "Notes", "Journal", "Health", "Finance", "Other"]
        let normalizedCategory = category.capitalized

        if validCategories.contains(normalizedCategory) {
            return normalizedCategory
        }

        // Try to find a match if response was slightly different
        for valid in validCategories {
            if category.lowercased().contains(valid.lowercased()) {
                return valid
            }
        }

        return "Other"
    }

    /// Summarize text to a specified maximum word count
    /// - Parameters:
    ///   - text: The text to summarize
    ///   - maxWords: Maximum words in summary (default 50)
    /// - Returns: Summarized text
    func summarize(text: String, maxWords: Int = 50) async throws -> String {
        let prompt = """
        Summarize the following text in \(maxWords) words or fewer.
        Focus on the key points and main ideas.
        Write in a concise, clear style.

        Text:
        ---
        \(text)
        ---

        Summary:
        """

        let response = try await generate(prompt: prompt)
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Helpers

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cannotConnectToHost || error.code == .timedOut {
                throw OllamaError.serverNotRunning
            }
            throw error
        }
    }

    private func parsePrivacyResponse(_ response: String) -> (isPrivate: Bool, confidence: Float, reason: String) {
        var isPrivate = false
        var confidence: Float = 0.5
        var reason = "Unable to determine"

        let lines = response.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.uppercased().hasPrefix("PRIVATE:") {
                let value = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces).uppercased()
                isPrivate = value.contains("YES")
            } else if trimmed.uppercased().hasPrefix("CONFIDENCE:") {
                let value = trimmed.dropFirst(11).trimmingCharacters(in: .whitespaces)
                if let parsed = Float(value) {
                    confidence = max(0, min(1, parsed))
                }
            } else if trimmed.uppercased().hasPrefix("REASON:") {
                reason = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            }
        }

        return (isPrivate, confidence, reason)
    }
}
