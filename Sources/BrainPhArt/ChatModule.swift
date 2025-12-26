import SwiftUI
import Foundation
import UniformTypeIdentifiers

// MARK: - Chat Models

struct ChatMessage: Identifiable, Codable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(role: MessageRole, content: String) {
        self.id = UUID().uuidString
        self.role = role
        self.content = content
        self.timestamp = Date()
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

    init(title: String = "New Chat") {
        self.id = UUID().uuidString
        self.title = title
        self.messages = []
        self.createdAt = Date()
        self.updatedAt = Date()
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

    func createConversation() -> ChatConversation {
        let conv = ChatConversation()
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
    @State private var showSettings = false
    @State private var temperature: Double = 0.7
    @State private var isDropTargeted = false

    var body: some View {
        HSplitView {
            // Left: Conversation History
            ConversationSidebar(
                conversations: chatManager.conversations,
                selectedId: chatManager.currentConversationId,
                onSelect: { chatManager.currentConversationId = $0 },
                onNew: { _ = chatManager.createConversation() },
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
                        _ = chatManager.createConversation()
                    })
                }

                Divider()

                // Input Area with drag-drop support
                ChatInputBar(
                    text: $inputText,
                    isLoading: isLoading,
                    isDropTargeted: $isDropTargeted,
                    onSend: sendMessage,
                    onShowSettings: { showSettings.toggle() }
                )
            }
            .onDrop(of: [.fileURL, .text], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }

            // Right: Settings Panel (optional)
            if showSettings {
                ChatSettingsPanel(
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
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            // Handle file URLs (.txt, .md)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil),
                          ["txt", "md", "text"].contains(url.pathExtension.lowercased()) else { return }

                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        DispatchQueue.main.async {
                            inputText += (inputText.isEmpty ? "" : "\n\n") + content
                        }
                    }
                }
                return true
            }

            // Handle plain text
            if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, error in
                    if let text = data as? String {
                        DispatchQueue.main.async {
                            inputText += (inputText.isEmpty ? "" : "\n\n") + text
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: inputText)
        let conversationId: String

        if let currentId = chatManager.currentConversationId {
            conversationId = currentId
        } else {
            let newConv = chatManager.createConversation()
            conversationId = newConv.id
        }

        chatManager.addMessage(userMessage, to: conversationId)
        let prompt = inputText
        inputText = ""
        isLoading = true

        Task {
            let conversation = chatManager.conversations.first { $0.id == conversationId }
            let systemPrompt = conversation?.systemPrompt

            let response = await LLMService.shared.send(
                prompt: prompt,
                systemPrompt: systemPrompt
            )

            await MainActor.run {
                let assistantMessage = ChatMessage(
                    role: .assistant,
                    content: response.isSuccess ? response.text : "Error: \(response.error ?? "Unknown")"
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
                            Text("Claude is thinking...")
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
                // Claude Avatar
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "brain")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                    )
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .padding(12)
                    .background(message.role == .user ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
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

            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Chat with Claude")
                .font(.title2)

            Text("Powered by Max Plan via CLI")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Drag & drop .txt/.md files to include in your message")
                .font(.caption)
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
    @Binding var isDropTargeted: Bool
    let onSend: () -> Void
    let onShowSettings: () -> Void

    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Text input
                TextField("Send a message to Claude...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        if !text.isEmpty && !isLoading {
                            onSend()
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .focusChatInput)) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isInputFocused = true
                        }
                    }

                // Claude badge
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                    Text("Claude")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .foregroundColor(.orange)
                .cornerRadius(6)

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
        .background(isDropTargeted ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Chat Settings Panel

struct ChatSettingsPanel: View {
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
                    // Info
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("Using Claude CLI (Max Plan)")
                            .font(.system(size: 12))
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

                        Text("Instructions for Claude")
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
