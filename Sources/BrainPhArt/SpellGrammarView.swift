import SwiftUI

// MARK: - Issue Types

struct SpellingIssue: Identifiable {
    let id = UUID()
    let word: String
    let startOffset: Int
    let endOffset: Int
    var suggestions: [String]
}

struct TextIssue: Identifiable, Equatable {
    let id = UUID()
    let type: IssueType
    let text: String
    let message: String
    let suggestion: String?
    let startOffset: Int
    let endOffset: Int

    enum IssueType: String {
        case spelling = "Spelling"
        case grammar = "Grammar"
    }

    static func == (lhs: TextIssue, rhs: TextIssue) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Issues Panel View

struct IssuesPanel: View {
    let issues: [TextIssue]
    let onApplySuggestion: (TextIssue, String) -> Void
    let onAddToDictionary: (String) -> Void
    let onDismiss: (TextIssue) -> Void

    @State private var expandedIssueId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "textformat.abc.dottedunderline")
                    .foregroundColor(.secondary)
                Text("ISSUES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                // Issue counts
                if !issues.isEmpty {
                    HStack(spacing: 8) {
                        let spellingCount = issues.filter { $0.type == .spelling }.count
                        let grammarCount = issues.filter { $0.type == .grammar }.count

                        if spellingCount > 0 {
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("\(spellingCount)")
                                    .font(.caption2)
                            }
                        }

                        if grammarCount > 0 {
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                Text("\(grammarCount)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if issues.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 20))
                        Text("No issues found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(issues) { issue in
                            IssueRow(
                                issue: issue,
                                isExpanded: expandedIssueId == issue.id,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedIssueId == issue.id {
                                            expandedIssueId = nil
                                        } else {
                                            expandedIssueId = issue.id
                                        }
                                    }
                                },
                                onApplySuggestion: { suggestion in
                                    onApplySuggestion(issue, suggestion)
                                },
                                onAddToDictionary: {
                                    onAddToDictionary(issue.text)
                                },
                                onDismiss: {
                                    onDismiss(issue)
                                }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Issue Row

struct IssueRow: View {
    let issue: TextIssue
    let isExpanded: Bool
    let onTap: () -> Void
    let onApplySuggestion: (String) -> Void
    let onAddToDictionary: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Main row
            HStack(spacing: 8) {
                // Issue type indicator
                Circle()
                    .fill(issue.type == .spelling ? Color.red : Color.blue)
                    .frame(width: 10, height: 10)

                // Issue text
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text(issue.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Expand/collapse indicator
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    // Suggestions
                    if let suggestion = issue.suggestion {
                        HStack(spacing: 8) {
                            Text("Suggestion:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button(action: { onApplySuggestion(suggestion) }) {
                                Text(suggestion)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Actions
                    HStack(spacing: 12) {
                        if issue.type == .spelling {
                            Button(action: onAddToDictionary) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle")
                                    Text("Add to Dictionary")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }

                        Button(action: onDismiss) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle")
                                Text("Dismiss")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isExpanded ? Color.primary.opacity(0.05) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    issue.type == .spelling ? Color.red.opacity(0.3) : Color.blue.opacity(0.3),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Spell/Grammar Checker Controller

@MainActor
class SpellGrammarChecker: ObservableObject {
    @Published var issues: [TextIssue] = []
    @Published var isChecking = false
    @Published var lastCheckedText = ""

    private var dismissedIssueIds: Set<UUID> = []

    func checkText(_ text: String) async {
        guard !text.isEmpty, text != lastCheckedText else { return }

        isChecking = true
        lastCheckedText = text

        var foundIssues: [TextIssue] = []

        // Check spelling
        let spellEngine = SpellEngine.shared

        // Load dictionary if not loaded
        if await !spellEngine.isDictionaryLoaded() {
            await spellEngine.loadDictionary()
        }

        // Extract words and check each one
        let words = extractWords(from: text)
        for wordInfo in words {
            let isCorrect = await spellEngine.isCorrect(word: wordInfo.word)
            if !isCorrect {
                let suggestions = await spellEngine.suggest(word: wordInfo.word, limit: 3)
                let issue = TextIssue(
                    type: .spelling,
                    text: wordInfo.word,
                    message: "Misspelled word",
                    suggestion: suggestions.first,
                    startOffset: wordInfo.startOffset,
                    endOffset: wordInfo.endOffset
                )
                foundIssues.append(issue)
            }
        }

        // Check grammar
        let grammarEngine = GrammarEngine.shared
        let grammarIssues = await grammarEngine.checkRules(text)

        for grammarIssue in grammarIssues {
            let issueText = extractText(from: text, start: grammarIssue.startOffset, end: grammarIssue.endOffset)
            let issue = TextIssue(
                type: .grammar,
                text: issueText,
                message: grammarIssue.message,
                suggestion: grammarIssue.suggestion,
                startOffset: grammarIssue.startOffset,
                endOffset: grammarIssue.endOffset
            )
            foundIssues.append(issue)
        }

        // Sort by position and filter out dismissed
        issues = foundIssues
            .sorted { $0.startOffset < $1.startOffset }
            .filter { !dismissedIssueIds.contains($0.id) }

        isChecking = false
    }

    func dismissIssue(_ issue: TextIssue) {
        dismissedIssueIds.insert(issue.id)
        issues.removeAll { $0.id == issue.id }
    }

    func clearDismissed() {
        dismissedIssueIds.removeAll()
    }

    private func extractWords(from text: String) -> [(word: String, startOffset: Int, endOffset: Int)] {
        var result: [(word: String, startOffset: Int, endOffset: Int)] = []

        var currentWord = ""
        var wordStart = 0

        for (index, char) in text.enumerated() {
            if char.isLetter || char == "'" {
                if currentWord.isEmpty {
                    wordStart = index
                }
                currentWord.append(char)
            } else {
                if !currentWord.isEmpty && currentWord.count >= 2 {
                    result.append((word: currentWord, startOffset: wordStart, endOffset: index))
                }
                currentWord = ""
            }
        }

        // Handle last word
        if !currentWord.isEmpty && currentWord.count >= 2 {
            result.append((word: currentWord, startOffset: wordStart, endOffset: text.count))
        }

        return result
    }

    private func extractText(from text: String, start: Int, end: Int) -> String {
        let startIndex = text.index(text.startIndex, offsetBy: min(start, text.count))
        let endIndex = text.index(text.startIndex, offsetBy: min(end, text.count))
        return String(text[startIndex..<endIndex])
    }
}

// MARK: - Editor with Inline Spell Check

struct EditorWithSpellCheck: View {
    let recording: RecordingItem
    @Binding var transcript: String
    @Binding var showPreview: Bool
    let unreviewedPIICount: Int
    let isRecording: Bool
    let onSave: () -> Void

    @State private var showCopied = false
    @State private var versionNumber: Int = 1
    @State private var isSpellCheckEnabled = true

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(recording.dateString)
                    .font(.headline)

                // Privacy Gate button
                PrivacyGateButton(
                    unreviewedCount: unreviewedPIICount,
                    sessionId: recording.id
                )

                // Extract Cards button
                ExtractCardsButton(
                    sessionId: recording.id,
                    transcript: transcript
                )

                // Privacy Review button (swipe-based card UI)
                PrivacyReviewButton(
                    sessionId: recording.id,
                    transcript: transcript
                )

                Spacer()

                // Spell check toggle
                Button(action: { isSpellCheckEnabled.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat.abc.dottedunderline")
                        Text(isSpellCheckEnabled ? "Spell: ON" : "Spell: OFF")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSpellCheckEnabled ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                .cornerRadius(4)
                .help("Toggle inline spell check (right-click misspelled words for suggestions)")

                // Copy to clipboard
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        Text(showCopied ? "Copied" : "Copy")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)

                Button(action: onSave) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save")
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main content - Inline spell check text view
            // Uses NSTextView with red underline for misspellings
            // Right-click for suggestions, "Add to Dictionary", or "Ignore"
            InlineSpellTextView(
                text: $transcript,
                isSpellCheckEnabled: isSpellCheckEnabled,
                onSave: onSave
            )
            .id(recording.id)

            // Stats bar at bottom
            StatsBar(
                wordCount: wordCount(transcript),
                versionNumber: versionNumber,
                unreviewedCount: unreviewedPIICount,
                isRecording: isRecording
            )
        }
        .onAppear {
            versionNumber = DatabaseManager.shared.getLatestVersion(sessionId: recording.id)?.versionNum ?? 1
        }
        .onChange(of: transcript) { _ in
            versionNumber = DatabaseManager.shared.getLatestVersion(sessionId: recording.id)?.versionNum ?? 1
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }
}
