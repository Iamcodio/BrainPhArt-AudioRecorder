import SwiftUI
import Foundation

// MARK: - Chat Models

struct ChatMessage: Identifiable, Codable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    var model: String?

    init(role: MessageRole, content: String, model: String? = nil) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.model = model
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

struct ChatConversation: Identifiable, Codable {
    let id: String
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
    var systemPrompt: String?
    var model: String

    init(title: String = "New Chat", model: String = "llama3.2") {
        self.id = UUID().uuidString
        self.title = title
        self.messages = []
        self.createdAt = Date()
        self.updatedAt = Date()
        self.model = model
    }

    var preview: String {
        messages.first(where: { $0.role == .user })?.content.prefix(50).description ?? "New conversation"
    }
}

// MARK: - Chat Manager

@MainActor
class ChatManager: ObservableObject {
    static let shared = ChatManager()

    @Published var conversations: [ChatConversation] = []
    @Published var currentConversationId: String?

    private let storageURL: URL

    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/brainphart")
        storageURL = appSupport.appendingPathComponent("conversations.json")
        loadConversations()
    }

    var currentConversation: ChatConversation? {
        get { conversations.first { $0.id == currentConversationId } }
        set {
            if let newValue = newValue, let index = conversations.firstIndex(where: { $0.id == newValue.id }) {
                conversations[index] = newValue
                saveConversations()
            }
        }
    }

    func createConversation(model: String) -> ChatConversation {
        let conv = ChatConversation(model: model)
        conversations.insert(conv, at: 0)
        currentConversationId = conv.id
        saveConversations()
        return conv
    }

    func deleteConversation(id: String) {
        conversations.removeAll { $0.id == id }
        if currentConversationId == id {
            currentConversationId = conversations.first?.id
        }
        saveConversations()
    }

    func addMessage(_ message: ChatMessage, to conversationId: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()

        // Update title from first user message
        if conversations[index].title == "New Chat",
           message.role == .user {
            conversations[index].title = String(message.content.prefix(40))
        }

        saveConversations()
    }

    func updateSystemPrompt(_ prompt: String?, for conversationId: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].systemPrompt = prompt
        saveConversations()
    }

    private func loadConversations() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            conversations = try JSONDecoder().decode([ChatConversation].self, from: data)
            currentConversationId = conversations.first?.id
        } catch {
            print("[ChatManager] Failed to load: \(error)")
        }
    }

    private func saveConversations() {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: storageURL)
        } catch {
            print("[ChatManager] Failed to save: \(error)")
        }
    }
}

// MARK: - Chat Tab View

struct ChatTabView: View {
    @StateObject private var chatManager = ChatManager.shared
    @State private var inputText = ""
    @State private var isLoading = false
    // Chat has its own provider/model selection, separate from global settings
    @State private var selectedProvider: LLMProvider = {
        let raw = UserDefaults.standard.string(forKey: "chat_provider") ?? "claude"
        return LLMProvider(rawValue: raw) ?? .claude
    }()
    @State private var selectedModel: String = UserDefaults.standard.string(forKey: "chat_model") ?? "claude-sonnet-4-5-20250929"
    @State private var showSettings = false
    @State private var temperature: Double = 0.7

    var body: some View {
        HSplitView {
            // Left: Conversation History
            ConversationSidebar(
                conversations: chatManager.conversations,
                selectedId: chatManager.currentConversationId,
                onSelect: { chatManager.currentConversationId = $0 },
                onNew: { _ = chatManager.createConversation(model: selectedModel) },
                onDelete: { chatManager.deleteConversation(id: $0) }
            )
            .frame(minWidth: 200, maxWidth: 280)

            // Center: Chat Area
            VStack(spacing: 0) {
                // Messages
                if let conversation = chatManager.currentConversation {
                    ChatMessagesView(messages: conversation.messages, isLoading: isLoading)
                } else {
                    EmptyChatView(onNewChat: {
                        _ = chatManager.createConversation(model: selectedModel)
                    })
                }

                Divider()

                // Input Area
                ChatInputBar(
                    text: $inputText,
                    isLoading: isLoading,
                    selectedModel: $selectedModel,
                    selectedProvider: $selectedProvider,
                    onSend: sendMessage,
                    onShowSettings: { showSettings.toggle() }
                )
            }

            // Right: Settings Panel (optional)
            if showSettings {
                ChatSettingsPanel(
                    selectedProvider: $selectedProvider,
                    selectedModel: $selectedModel,
                    temperature: $temperature,
                    systemPrompt: Binding(
                        get: { chatManager.currentConversation?.systemPrompt ?? "" },
                        set: { chatManager.updateSystemPrompt($0.isEmpty ? nil : $0, for: chatManager.currentConversationId ?? "") }
                    ),
                    onClose: { showSettings = false }
                )
                .frame(width: 280)
            }
        }
        // Persist provider selection and update model when provider changes
        .onChange(of: selectedProvider) { newProvider in
            UserDefaults.standard.set(newProvider.rawValue, forKey: "chat_provider")
            // Reset to default model for new provider if current model doesn't belong
            let validModels = newProvider.availableModels.map { $0.id }
            if !validModels.contains(selectedModel) {
                selectedModel = newProvider.defaultModel
            }
        }
        .onChange(of: selectedModel) { newModel in
            UserDefaults.standard.set(newModel, forKey: "chat_model")
        }
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: inputText)
        let conversationId: String

        if let currentId = chatManager.currentConversationId {
            conversationId = currentId
        } else {
            let newConv = chatManager.createConversation(model: selectedModel)
            conversationId = newConv.id
        }

        chatManager.addMessage(userMessage, to: conversationId)
        let prompt = inputText
        inputText = ""
        isLoading = true

        Task {
            // Build messages for context
            let conversation = chatManager.conversations.first { $0.id == conversationId }
            let systemPrompt = conversation?.systemPrompt

            let response = await LLMService.shared.send(
                prompt: prompt,
                systemPrompt: systemPrompt,
                provider: selectedProvider,
                model: selectedModel
            )

            await MainActor.run {
                let assistantMessage = ChatMessage(
                    role: .assistant,
                    content: response.isSuccess ? response.text : "Error: \(response.error ?? "Unknown")",
                    model: response.model
                )
                chatManager.addMessage(assistantMessage, to: conversationId)
                isLoading = false
            }
        }
    }
}

// MARK: - Conversation Sidebar

struct ConversationSidebar: View {
    let conversations: [ChatConversation]
    let selectedId: String?
    let onSelect: (String) -> Void
    let onNew: () -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Chats")
                    .font(.headline)
                Spacer()
                Button(action: onNew) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help("New Chat")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Conversation List
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(conversations) { conv in
                        ConversationRow(
                            conversation: conv,
                            isSelected: conv.id == selectedId,
                            onSelect: { onSelect(conv.id) },
                            onDelete: { onDelete(conv.id) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ConversationRow: View {
    let conversation: ChatConversation
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)

                Text(conversation.updatedAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        .cornerRadius(6)
        .padding(.horizontal, 4)
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Chat Messages View

struct ChatMessagesView: View {
    let messages: [ChatMessage]
    let isLoading: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .id("loading")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _ in
                withAnimation {
                    proxy.scrollTo(messages.last?.id ?? "loading", anchor: .bottom)
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                // AI Avatar
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 14))
                            .foregroundColor(.purple)
                    )
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .padding(12)
                    .background(message.role == .user ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                if let model = message.model {
                    Text(model)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            if message.role == .user {
                // User Avatar
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Empty Chat View

struct EmptyChatView: View {
    let onNewChat: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Start a conversation")
                .font(.title2)
                .foregroundColor(.secondary)

            Button(action: onNewChat) {
                Label("New Chat", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }
}

// MARK: - Chat Input Bar

struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    @Binding var selectedModel: String
    @Binding var selectedProvider: LLMProvider
    let onSend: () -> Void
    let onShowSettings: () -> Void

    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Text input
                TextField("Send a message", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        if !text.isEmpty && !isLoading {
                            onSend()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .focusChatInput)) { _ in
                        // Delay to ensure window is active first
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isInputFocused = true
                            print("📍 Chat input focused for internal dictation")
                        }
                    }

                // Provider picker
                Menu {
                    ForEach(LLMProvider.allCases) { provider in
                        Button(action: { selectedProvider = provider }) {
                            HStack {
                                Text(provider.displayName)
                                if selectedProvider == provider {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: providerIcon)
                        Text(selectedProvider.rawValue)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)

                // Model picker - uses availableModels from LLMProvider
                Menu {
                    ForEach(selectedProvider.availableModels, id: \.id) { model in
                        Button(action: { selectedModel = model.id }) {
                            HStack {
                                Text(model.name)
                                if selectedModel == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(currentModelName)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)

                // Settings button
                Button(action: onShowSettings) {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)

                // Send button
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(text.isEmpty || isLoading ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty || isLoading)
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var providerIcon: String {
        switch selectedProvider {
        case .claude: return "brain"
        case .openai: return "sparkles"
        case .gemini: return "globe"
        case .openrouter: return "network"
        case .ollama: return "desktopcomputer"
        }
    }

    private var currentModelName: String {
        // Find friendly name for current model ID
        if let model = selectedProvider.availableModels.first(where: { $0.id == selectedModel }) {
            return model.name
        }
        // Fallback to model ID if not found
        return selectedModel
    }
}

// MARK: - Chat Settings Panel

struct ChatSettingsPanel: View {
    @Binding var selectedProvider: LLMProvider
    @Binding var selectedModel: String
    @Binding var temperature: Double
    @Binding var systemPrompt: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Temperature
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperature")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(String(format: "%.1f", temperature))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $temperature, in: 0...2, step: 0.1)
                        Text("Lower = more focused, Higher = more creative")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // System Prompt
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt")
                            .font(.system(size: 11, weight: .medium))

                        TextEditor(text: $systemPrompt)
                            .font(.system(size: 12))
                            .frame(height: 120)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )

                        Text("Instructions for the AI assistant")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Quick System Prompts
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick Prompts")
                            .font(.system(size: 11, weight: .medium))

                        ForEach(quickPrompts, id: \.0) { name, prompt in
                            Button(action: { systemPrompt = prompt }) {
                                Text(name)
                                    .font(.system(size: 11))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var quickPrompts: [(String, String)] {
        [
            ("Writing Assistant", "You are a helpful writing assistant. Help improve clarity, grammar, and flow while maintaining the original voice."),
            ("Code Helper", "You are a coding assistant. Provide clear, concise code examples and explanations."),
            ("Brainstorm", "You are a creative brainstorming partner. Generate ideas, ask probing questions, and help explore possibilities."),
            ("Summarizer", "You are a summarization expert. Provide clear, concise summaries of content."),
            ("British English", "You are a British English editor. Use British spelling, grammar, and expressions.")
        ]
    }
}
