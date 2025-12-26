import SwiftUI
import AppKit

/// NSTextView wrapper with custom inline spell checking
/// - Uses OUR SpellEngine (not Apple's NSSpellChecker)
/// - Red underline for misspellings
/// - Right-click context menu with suggestions + "Add to Dictionary"
struct InlineSpellTextView: NSViewRepresentable {
    @Binding var text: String
    var isSpellCheckEnabled: Bool = true
    var onSave: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = SpellCheckTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor.textColor  // Explicit text color
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticSpellingCorrectionEnabled = false  // We do our own
        textView.isContinuousSpellCheckingEnabled = false  // We do our own
        textView.isGrammarCheckingEnabled = false  // We do our own
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.insertionPointColor = NSColor.textColor  // Cursor color

        // Set up text container
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        // Store reference for coordinator
        context.coordinator.textView = textView
        context.coordinator.isSpellCheckEnabled = isSpellCheckEnabled

        // Set initial text
        textView.string = text

        // Run initial spell check
        if isSpellCheckEnabled && !text.isEmpty {
            context.coordinator.scheduleSpellCheck()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SpellCheckTextView else { return }

        // Update spell check state
        context.coordinator.isSpellCheckEnabled = isSpellCheckEnabled

        // Only update text if it changed externally
        if textView.string != text && !context.coordinator.isEditing {
            let selectedRange = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selectedRange)

            // Run spell check after text update
            if isSpellCheckEnabled {
                context.coordinator.scheduleSpellCheck()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineSpellTextView
        weak var textView: SpellCheckTextView?
        var isEditing = false
        var isSpellCheckEnabled = true
        private var spellCheckTask: Task<Void, Never>?

        init(_ parent: InlineSpellTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string

            // Schedule spell check with debounce
            if isSpellCheckEnabled {
                scheduleSpellCheck()
            }
        }

        func scheduleSpellCheck() {
            // Cancel previous task
            spellCheckTask?.cancel()

            // Schedule new work with 300ms debounce
            spellCheckTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms
                guard !Task.isCancelled else { return }
                await runSpellCheck()
            }
        }

        func runSpellCheck() async {
            guard let textView = textView, isSpellCheckEnabled else { return }

            // Capture text on main thread
            let text = textView.string

            // Find misspelled words (async)
            let misspelledRanges = await findMisspelledWords(in: text)

            // Apply highlighting (we're already on MainActor)
            applySpellCheckHighlighting(textView: textView, misspelledRanges: misspelledRanges)
        }

        func findMisspelledWords(in text: String) async -> [(range: NSRange, word: String, suggestions: [String])] {
            var results: [(range: NSRange, word: String, suggestions: [String])] = []

            let spellEngine = SpellEngine.shared

            // Ensure dictionary is loaded
            if await !spellEngine.isDictionaryLoaded() {
                await spellEngine.loadDictionary()
            }

            // Extract words with their ranges
            let wordPattern = try? NSRegularExpression(pattern: "\\b[a-zA-Z']+\\b", options: [])
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            guard let matches = wordPattern?.matches(in: text, options: [], range: fullRange) else {
                return results
            }

            for match in matches {
                let wordRange = match.range
                let word = nsText.substring(with: wordRange)

                // Skip very short words and words with apostrophes that are contractions
                if word.count < 2 { continue }

                let isCorrect = await spellEngine.isCorrect(word: word)
                if !isCorrect {
                    let suggestions = await spellEngine.suggest(word: word, limit: 5)
                    results.append((range: wordRange, word: word, suggestions: suggestions))
                }
            }

            return results
        }

        func applySpellCheckHighlighting(textView: SpellCheckTextView, misspelledRanges: [(range: NSRange, word: String, suggestions: [String])]) {
            guard let textStorage = textView.textStorage else { return }

            // Remove existing spell check attributes
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.removeAttribute(.underlineStyle, range: fullRange)
            textStorage.removeAttribute(.underlineColor, range: fullRange)
            textStorage.removeAttribute(.toolTip, range: fullRange)

            // Store misspelled info for right-click menu
            textView.misspelledWords = misspelledRanges

            // Apply red underline to misspelled words
            for item in misspelledRanges {
                // Ensure range is valid
                guard item.range.location + item.range.length <= textStorage.length else { continue }

                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: item.range)
                textStorage.addAttribute(.underlineColor, value: NSColor.systemPurple.withAlphaComponent(0.6), range: item.range)

                // Add tooltip with suggestions
                if !item.suggestions.isEmpty {
                    let tooltip = "Did you mean: \(item.suggestions.prefix(3).joined(separator: ", "))?"
                    textStorage.addAttribute(.toolTip, value: tooltip, range: item.range)
                }
            }
        }
    }
}

// MARK: - Custom NSTextView with Right-Click Menu

class SpellCheckTextView: NSTextView {
    var misspelledWords: [(range: NSRange, word: String, suggestions: [String])] = []

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

            // Ignore option (just removes highlight for this session)
            let ignoreItem = NSMenuItem(title: "Ignore", action: #selector(ignoreMisspelling(_:)), keyEquivalent: "")
            ignoreItem.representedObject = misspelled.range
            ignoreItem.target = self
            menu.addItem(ignoreItem)

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

        // Ensure range is valid
        guard range.location + range.length <= textStorage.length else { return }

        // Replace the misspelled word
        if shouldChangeText(in: range, replacementString: replacement) {
            textStorage.replaceCharacters(in: range, with: replacement)
            didChangeText()
        }
    }

    @objc func addToDictionary(_ sender: NSMenuItem) {
        guard let word = sender.representedObject as? String else { return }

        Task {
            await SpellEngine.shared.addToCustomDictionary(word: word)

            // Trigger re-check
            await MainActor.run {
                // Remove this word from misspelled list
                misspelledWords.removeAll { $0.word.lowercased() == word.lowercased() }

                // Remove highlighting for this word
                if let textStorage = self.textStorage {
                    let fullRange = NSRange(location: 0, length: textStorage.length)
                    let pattern = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: [.caseInsensitive])
                    pattern?.enumerateMatches(in: textStorage.string, options: [], range: fullRange) { match, _, _ in
                        if let matchRange = match?.range {
                            textStorage.removeAttribute(.underlineStyle, range: matchRange)
                            textStorage.removeAttribute(.underlineColor, range: matchRange)
                        }
                    }
                }
            }
        }
    }

    @objc func ignoreMisspelling(_ sender: NSMenuItem) {
        guard let range = sender.representedObject as? NSRange else { return }

        // Remove from misspelled list
        misspelledWords.removeAll { $0.range == range }

        // Remove highlighting
        textStorage?.removeAttribute(.underlineStyle, range: range)
        textStorage?.removeAttribute(.underlineColor, range: range)
    }
}

