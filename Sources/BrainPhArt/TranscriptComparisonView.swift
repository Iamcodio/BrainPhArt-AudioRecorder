import SwiftUI
import AppKit

/// TranscriptComparisonView - Side-by-side comparison for non-destructive editing
/// Shows original Whisper output vs LLM-suggested improvements
/// User controls what gets accepted - NEVER auto-replace

struct TranscriptComparisonView: View {
    @Binding var originalText: String
    @Binding var suggestedText: String
    @State private var showDiff = true
    @State private var isProcessing = false
    @State private var selectedPromptId: String = "cleanup"
    @State private var wasRedirectedToLocal = false

    var isPrivateSession: Bool = false

    let onAcceptAll: () -> Void
    let onRejectAll: () -> Void
    let onAddToVocabulary: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            HStack {
                Text("Review Suggestions")
                    .font(.headline)

                // Privacy indicator
                if isPrivateSession {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("LOCAL ONLY")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
                }

                Spacer()

                // Prompt picker
                Menu {
                    ForEach(PromptCategory.allCases, id: \.self) { category in
                        Section(category.rawValue) {
                            ForEach(PromptManager.shared.promptsByCategory(category)) { prompt in
                                Button(action: { selectedPromptId = prompt.id }) {
                                    HStack {
                                        Text(prompt.name)
                                        if selectedPromptId == prompt.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.bubble")
                        Text(selectedPromptName)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 150)

                Toggle("Show Diff", isOn: $showDiff)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Button(action: { requestLLMSuggestions() }) {
                    HStack(spacing: 4) {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text("Suggest")
                    }
                }
                .disabled(isProcessing || originalText.isEmpty)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            // Show redirect warning if content was sent to local
            if wasRedirectedToLocal {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                    Text("Private content detected - processed locally with Ollama")
                }
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
            }

            Divider()

            // Always show split view with diff highlighting
            HSplitView {
                // Left: Original with RED on removed words
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ORIGINAL")
                            .font(.caption)
                            .foregroundColor(.red)
                        Spacer()
                        if showDiff && !suggestedText.isEmpty {
                            HStack(spacing: 4) {
                                Circle().fill(Color.red.opacity(0.3)).frame(width: 10, height: 10)
                                Text("Removed")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        } else {
                            Text("Raw Whisper output")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    ScrollView {
                        if showDiff && !suggestedText.isEmpty {
                            // Show original with RED highlighting on removed words
                            OriginalDiffView(original: originalText, modified: suggestedText)
                                .padding()
                        } else {
                            Text(originalText)
                                .font(.system(size: 14))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .textSelection(.enabled)
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                }
                .frame(minWidth: 300)

                // Right: Suggested with GREEN on added words - EDITABLE
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("SUGGESTED")
                            .font(.caption)
                            .foregroundColor(.green)
                        Spacer()
                        if showDiff && !suggestedText.isEmpty {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green.opacity(0.3)).frame(width: 10, height: 10)
                                Text("Added")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        } else {
                            Text("Editable - fix manually or use LLM")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if isProcessing {
                        VStack {
                            ProgressView()
                            Text("Analyzing with local LLM...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.95))
                    } else if suggestedText.isEmpty {
                        VStack {
                            Text("Click 'Suggest' for LLM analysis")
                                .foregroundColor(.secondary)
                                .italic()
                            Text("or click here to start editing manually")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.95))
                        .onTapGesture {
                            // Copy original to start editing
                            suggestedText = originalText
                        }
                    } else {
                        // EDITABLE view with diff highlighting + spell check
                        DiffEditableTextView(
                            originalText: originalText,
                            editedText: $suggestedText,
                            showDiff: showDiff,
                            isSpellCheckEnabled: true
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 300)
            }

            Divider()

            // Footer with accept/reject
            HStack {
                // Word suggestion (for vocabulary)
                HStack {
                    Image(systemName: "book.closed")
                    Text("Add word to vocabulary:")
                        .font(.caption)
                    TextField("word", text: .constant(""))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    Button("Add") {
                        // Will be connected to vocabulary system
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                // Reject all changes
                Button(action: onRejectAll) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("Discard")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(suggestedText.isEmpty)

                // Save and accept changes
                Button(action: onAcceptAll) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Changes")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(suggestedText.isEmpty)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    // MARK: - Helpers

    private var selectedPromptName: String {
        if let prompt = PromptManager.shared.getPrompt(id: selectedPromptId) {
            return prompt.name
        }
        // Default to first cleanup prompt
        return PromptManager.shared.cleanupPrompt?.name ?? "Clean Transcript"
    }

    private func requestLLMSuggestions() {
        isProcessing = true
        wasRedirectedToLocal = false

        Task {
            // Get the selected prompt or use default
            let prompt: PromptTemplate
            if let selected = PromptManager.shared.getPrompt(id: selectedPromptId) {
                prompt = selected
            } else if let cleanup = PromptManager.shared.cleanupPrompt {
                prompt = cleanup
            } else {
                // Hardcoded fallback
                prompt = PromptTemplate(
                    name: "Clean Transcript",
                    systemPrompt: "You are a transcript editor. Clean up the text while preserving the original meaning.",
                    userPromptTemplate: "Clean up this transcript:\n\n{{TEXT}}",
                    category: .cleanup,
                    isBuiltIn: true
                )
            }

            let response = await LLMService.shared.send(
                prompt: prompt.buildUserPrompt(with: originalText),
                systemPrompt: prompt.systemPrompt,
                isPrivateSession: isPrivateSession
            )

            await MainActor.run {
                wasRedirectedToLocal = response.wasRedirectedToLocal

                if response.isSuccess {
                    suggestedText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    print("❌ LLM suggestion failed: \(response.error ?? "Unknown error")")
                    suggestedText = originalText
                }
                isProcessing = false
            }
        }
    }
}

// MARK: - Diff Editable Text View (NSTextView with diff highlighting + spell check)

class DiffTextView: NSTextView {
    var originalText: String = ""
    var showDiff: Bool = true
    var misspelledWords: [(range: NSRange, word: String, suggestions: [String])] = []

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        window?.makeKey()
        return result
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        // Get click location
        let point = convert(event.locationInWindow, from: nil)
        let characterIndex = characterIndexForInsertion(at: point)

        // Check if clicked on a misspelled word
        if let misspelled = misspelledWords.first(where: { NSLocationInRange(characterIndex, $0.range) }) {
            // Add suggestions
            if !misspelled.suggestions.isEmpty {
                for suggestion in misspelled.suggestions.prefix(5) {
                    let item = NSMenuItem(title: suggestion, action: #selector(replaceMisspelling(_:)), keyEquivalent: "")
                    item.representedObject = (misspelled.range, suggestion)
                    item.target = self
                    menu.addItem(item)
                }
                menu.addItem(NSMenuItem.separator())
            }

            // Add to dictionary option
            let addItem = NSMenuItem(title: "Add \"\(misspelled.word)\" to Dictionary", action: #selector(addToDictionary(_:)), keyEquivalent: "")
            addItem.representedObject = misspelled.word
            addItem.target = self
            menu.addItem(addItem)

            menu.addItem(NSMenuItem.separator())
        }

        // Standard edit menu items
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a"))

        return menu
    }

    @objc func replaceMisspelling(_ sender: NSMenuItem) {
        guard let (range, replacement) = sender.representedObject as? (NSRange, String) else { return }
        guard let textStorage = textStorage else { return }
        guard range.location + range.length <= textStorage.length else { return }

        if shouldChangeText(in: range, replacementString: replacement) {
            textStorage.replaceCharacters(in: range, with: replacement)
            didChangeText()
        }
    }

    @objc func addToDictionary(_ sender: NSMenuItem) {
        guard let word = sender.representedObject as? String else { return }

        Task {
            await SpellEngine.shared.addToCustomDictionary(word: word)
            await MainActor.run {
                misspelledWords.removeAll { $0.word.lowercased() == word.lowercased() }
            }
        }
    }
}

struct DiffEditableTextView: NSViewRepresentable {
    let originalText: String
    @Binding var editedText: String
    var showDiff: Bool = true
    var isSpellCheckEnabled: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = DiffTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.originalText = originalText
        textView.showDiff = showDiff
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.95)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.95)

        // Store reference
        context.coordinator.textView = textView
        context.coordinator.originalText = originalText

        // Set initial text and apply highlighting
        textView.string = editedText
        context.coordinator.applyHighlighting()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? DiffTextView else { return }

        // Update settings
        textView.originalText = originalText
        textView.showDiff = showDiff
        context.coordinator.originalText = originalText
        context.coordinator.showDiff = showDiff
        context.coordinator.isSpellCheckEnabled = isSpellCheckEnabled

        // Only update text if changed externally (not during editing)
        if textView.string != editedText && !context.coordinator.isEditing {
            textView.string = editedText
            context.coordinator.applyHighlighting()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DiffEditableTextView
        weak var textView: DiffTextView?
        var isEditing = false
        var originalText: String = ""
        var showDiff: Bool = true
        var isSpellCheckEnabled: Bool = true
        private var highlightTask: Task<Void, Never>?

        init(_ parent: DiffEditableTextView) {
            self.parent = parent
            self.originalText = parent.originalText
            self.showDiff = parent.showDiff
            self.isSpellCheckEnabled = parent.isSpellCheckEnabled
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.editedText = textView.string

            // Schedule highlighting with debounce
            scheduleHighlighting()
        }

        func scheduleHighlighting() {
            highlightTask?.cancel()
            highlightTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms debounce
                guard !Task.isCancelled else { return }
                applyHighlighting()
            }
        }

        func applyHighlighting() {
            guard let textView = textView, let textStorage = textView.textStorage else { return }

            let editedText = textView.string
            let cursorPosition = textView.selectedRange()

            // Clear existing attributes
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.removeAttribute(.backgroundColor, range: fullRange)
            textStorage.removeAttribute(.underlineStyle, range: fullRange)
            textStorage.removeAttribute(.underlineColor, range: fullRange)

            // Reset font and color
            textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

            // Apply diff highlighting if enabled
            if showDiff && !originalText.isEmpty {
                applyDiffHighlighting(textStorage: textStorage, original: originalText, edited: editedText)
            }

            // Apply spell check highlighting
            if isSpellCheckEnabled {
                Task {
                    await applySpellCheckHighlighting()
                }
            }

            // Restore cursor position
            textView.setSelectedRange(cursorPosition)
        }

        func applyDiffHighlighting(textStorage: NSTextStorage, original: String, edited: String) {
            // Get word positions in edited text
            let editedWords = edited.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            let originalWords = original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

            // Build set of original words (lowercase for comparison)
            let originalWordSet = Set(originalWords.map { $0.lowercased() })

            // Find ranges of words in edited text that are NOT in original
            var searchStart = edited.startIndex
            for word in editedWords {
                guard let range = edited.range(of: word, range: searchStart..<edited.endIndex) else { continue }

                let isNew = !originalWordSet.contains(word.lowercased())

                if isNew {
                    let nsRange = NSRange(range, in: edited)
                    // Green background for added/changed words
                    textStorage.addAttribute(.backgroundColor, value: NSColor.systemGreen.withAlphaComponent(0.25), range: nsRange)
                }

                searchStart = range.upperBound
            }
        }

        func applySpellCheckHighlighting() async {
            guard let textView = textView, isSpellCheckEnabled else {
                print("🔤 Spell check skipped - textView: \(textView != nil), enabled: \(isSpellCheckEnabled)")
                return
            }

            let text = textView.string
            let spellEngine = SpellEngine.shared

            // Ensure dictionary is loaded
            if await !spellEngine.isDictionaryLoaded() {
                print("🔤 Loading dictionary...")
                await spellEngine.loadDictionary()
            }

            let wordCount = await spellEngine.wordCount()
            print("🔤 Spell check running, dictionary has \(wordCount) words")

            // Find misspelled words
            var misspelled: [(range: NSRange, word: String, suggestions: [String])] = []

            let wordPattern = try? NSRegularExpression(pattern: "\\b[a-zA-Z']+\\b", options: [])
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            guard let matches = wordPattern?.matches(in: text, options: [], range: fullRange) else {
                print("🔤 No word matches found")
                return
            }

            print("🔤 Found \(matches.count) words to check")

            for match in matches {
                let wordRange = match.range
                let word = nsText.substring(with: wordRange)

                if word.count < 2 { continue }

                let isCorrect = await spellEngine.isCorrect(word: word)
                if !isCorrect {
                    let suggestions = await spellEngine.suggest(word: word, limit: 5)
                    misspelled.append((range: wordRange, word: word, suggestions: suggestions))
                }
            }

            print("🔤 Found \(misspelled.count) misspelled words: \(misspelled.map { $0.word })")

            // Apply purple underlines on main thread
            await MainActor.run {
                guard let textStorage = textView.textStorage else { return }

                textView.misspelledWords = misspelled

                for item in misspelled {
                    guard item.range.location + item.range.length <= textStorage.length else { continue }
                    textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: item.range)
                    textStorage.addAttribute(.underlineColor, value: NSColor.systemPurple.withAlphaComponent(0.6), range: item.range)
                }
                print("🔤 Applied underlines to \(misspelled.count) words")
            }
        }
    }
}

// MARK: - Legacy Editable Text View (kept for compatibility)

class FocusableTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        window?.makeKey()
        return result
    }
}

struct EditableTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = FocusableTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.95)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.95)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditableTextView

        init(_ parent: EditableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - Original Diff View (RED on removed words)

struct OriginalDiffView: View {
    let original: String
    let modified: String

    var body: some View {
        Text(buildAttributedOriginal())
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func buildAttributedOriginal() -> AttributedString {
        let diffResult = computeWordDiff(original: original, modified: modified)

        var result = AttributedString()

        for (index, item) in diffResult.enumerated() {
            // Only show original and removed words (skip added)
            if item.status == .added { continue }

            var wordAttr = AttributedString(item.text)

            if item.status == .removed {
                // RED background and strikethrough for removed words
                wordAttr.foregroundColor = Color(red: 0.8, green: 0.0, blue: 0.0)
                wordAttr.backgroundColor = Color.red.opacity(0.3)
                wordAttr.strikethroughStyle = .single
            } else {
                wordAttr.foregroundColor = .primary
            }

            result.append(wordAttr)
            result.append(AttributedString(" "))
        }

        return result
    }

    private func computeWordDiff(original: String, modified: String) -> [DiffWord] {
        DiffEngine.computeWordDiff(original: original, modified: modified)
    }
}

// MARK: - Suggested Diff View (GREEN on added words)

struct SuggestedDiffView: View {
    let original: String
    let modified: String

    var body: some View {
        Text(buildAttributedSuggested())
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func buildAttributedSuggested() -> AttributedString {
        let diffResult = DiffEngine.computeWordDiff(original: original, modified: modified)

        var result = AttributedString()

        for item in diffResult {
            // Only show modified and added words (skip removed)
            if item.status == .removed { continue }

            var wordAttr = AttributedString(item.text)

            if item.status == .added {
                // GREEN background for added words
                wordAttr.foregroundColor = Color(red: 0.0, green: 0.5, blue: 0.0)
                wordAttr.backgroundColor = Color.green.opacity(0.3)
            } else {
                wordAttr.foregroundColor = .primary
            }

            result.append(wordAttr)
            result.append(AttributedString(" "))
        }

        return result
    }
}

// MARK: - Diff Engine (shared logic)

struct DiffEngine {
    /// Compute word-level diff between original and modified text
    static func computeWordDiff(original: String, modified: String) -> [DiffWord] {
        let originalWords = original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let modifiedWords = modified.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        var result: [DiffWord] = []
        var i = 0
        var j = 0

        while i < originalWords.count || j < modifiedWords.count {
            if i >= originalWords.count {
                result.append(DiffWord(text: modifiedWords[j], status: .added))
                j += 1
            } else if j >= modifiedWords.count {
                result.append(DiffWord(text: originalWords[i], status: .removed))
                i += 1
            } else if originalWords[i].lowercased() == modifiedWords[j].lowercased() {
                result.append(DiffWord(text: modifiedWords[j], status: .unchanged))
                i += 1
                j += 1
            } else {
                // Look ahead for matches
                let lookAhead = 5
                var foundInModified = false

                for k in (j+1)..<min(j+lookAhead+1, modifiedWords.count) {
                    if originalWords[i].lowercased() == modifiedWords[k].lowercased() {
                        for m in j..<k {
                            result.append(DiffWord(text: modifiedWords[m], status: .added))
                        }
                        j = k
                        foundInModified = true
                        break
                    }
                }

                if !foundInModified {
                    var foundInOriginal = false
                    for k in (i+1)..<min(i+lookAhead+1, originalWords.count) {
                        if modifiedWords[j].lowercased() == originalWords[k].lowercased() {
                            for m in i..<k {
                                result.append(DiffWord(text: originalWords[m], status: .removed))
                            }
                            i = k
                            foundInOriginal = true
                            break
                        }
                    }

                    if !foundInOriginal {
                        result.append(DiffWord(text: originalWords[i], status: .removed))
                        result.append(DiffWord(text: modifiedWords[j], status: .added))
                        i += 1
                        j += 1
                    }
                }
            }
        }

        return result
    }
}

// MARK: - Diff Data Types

struct DiffWord: Identifiable {
    let id = UUID()
    let text: String
    let status: DiffStatus
}

enum DiffStatus {
    case unchanged
    case added
    case removed
    case modified
}

