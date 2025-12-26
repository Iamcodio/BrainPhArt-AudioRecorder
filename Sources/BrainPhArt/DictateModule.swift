import SwiftUI
import AppKit
import AVFoundation

/// Dictate Module - Voice recording and transcription
/// Can be used standalone or integrated into the main app.
/// Provides: audio recording, Whisper transcription, history

// MARK: - Dictate Tab View (For use in tabbed app)

struct DictateTabView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var recordingState: RecordingState
    @Binding var recordings: [RecordingItem]
    @Binding var selectedRecording: RecordingItem?
    @Binding var editedTranscript: String
    let onStartStop: () -> Void
    let onCancel: () -> Void
    let onSelect: (RecordingItem) -> Void
    let onRefresh: () -> Void
    let onDelete: (RecordingItem) -> Void
    let onRetryTranscription: (RecordingItem) -> Void

    @State private var isPrivateMode = false
    @State private var showComparison = false
    @State private var isSpellCheckEnabled = false
    @State private var suggestedText = ""
    @State private var vocabularyWord = ""

    var body: some View {
        HSplitView {
            // Left: History
            HistoryPanel(
                recordings: recordings,
                selectedId: selectedRecording?.id,
                onSelect: onSelect,
                onRefresh: onRefresh,
                onDelete: onDelete,
                onRetryTranscription: onRetryTranscription
            )
            .frame(minWidth: 250, maxWidth: 300)

            // Center: Transcript display (read-only during dictation)
            VStack(spacing: 0) {
                if let selected = selectedRecording {
                    // Header
                    HStack {
                        Text(selected.dateString)
                            .font(.headline)

                        // Privacy toggle
                        Button(action: { isPrivateMode.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: isPrivateMode ? "lock.fill" : "lock.open")
                                Text(isPrivateMode ? "PRIVATE" : "Normal")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(isPrivateMode ? .red : .secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isPrivateMode ? Color.red.opacity(0.15) : Color.primary.opacity(0.06))
                        .cornerRadius(4)
                        .help(isPrivateMode ? "Private: Never leaves this machine" : "Normal: Safe for APIs")

                        Spacer()

                        // Add to vocabulary
                        HStack(spacing: 4) {
                            TextField("Add word", text: $vocabularyWord)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            Button(action: addToVocabulary) {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                            .disabled(vocabularyWord.isEmpty)
                            .help("Add word to vocabulary for better transcription")
                        }

                        // Spell Check toggle
                        Button(action: { isSpellCheckEnabled.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: isSpellCheckEnabled ? "checkmark.circle.fill" : "textformat.abc")
                                Text(isSpellCheckEnabled ? "Spell ✓" : "Spell")
                                    .font(.system(size: 11))
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(editedTranscript.isEmpty)
                        .help(isSpellCheckEnabled ? "Spell check ON" : "Enable spell check")

                        // AI Review button
                        Button(action: { showComparison.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: showComparison ? "doc.text" : "wand.and.stars")
                                Text(showComparison ? "Original" : "AI Review")
                                    .font(.system(size: 11))
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(editedTranscript.isEmpty)
                        .help("Review transcript with AI suggestions")

                        if selected.isProcessing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Transcribing...")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Transcript area - toggle between views
                    if showComparison {
                        TranscriptComparisonView(
                            originalText: $editedTranscript,
                            suggestedText: $suggestedText,
                            isPrivateSession: isPrivateMode,
                            onAcceptAll: acceptSuggestions,
                            onRejectAll: rejectSuggestions,
                            onAddToVocabulary: { word in
                                Task {
                                    await TranscriptionManager.shared.addToVocabulary(word)
                                }
                            }
                        )
                    } else if isSpellCheckEnabled && !editedTranscript.isEmpty {
                        // Editable with Apple spell check (only when text exists)
                        SimpleSpellCheckEditor(text: $editedTranscript)
                            .id("spell-\(selectedRecording?.id ?? "editor")")
                    } else {
                        // Transcript (read-only in DICTATE mode)
                        ScrollView {
                            Text(editedTranscript.isEmpty ? "Start recording to see transcript here..." : editedTranscript)
                                .font(.system(size: 16))
                                .foregroundColor(editedTranscript.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    EmptyDictateView()
                }

                Divider()

                // Recorder at bottom
                RecorderModule(
                    audioRecorder: audioRecorder,
                    recordingState: $recordingState,
                    onRecord: onStartStop,
                    onStop: onStartStop,
                    onCancel: onCancel
                )

                // Playback
                PlaybackModule(selectedRecording: selectedRecording)
            }
        }
    }

    // MARK: - Actions

    private func addToVocabulary() {
        guard !vocabularyWord.isEmpty else { return }
        Task {
            await TranscriptionManager.shared.addToVocabulary(vocabularyWord)
            await MainActor.run {
                vocabularyWord = ""
            }
        }
    }

    private func acceptSuggestions() {
        // Accept and save changes
        guard !suggestedText.isEmpty else { return }

        if let sessionId = selectedRecording?.id {
            let sessionDate = DatabaseManager.shared.getSessionDate(sessionId: sessionId)

            // Save RAW transcript (original Whisper output)
            _ = DatabaseManager.shared.saveRawTranscriptFile(
                sessionId: sessionId,
                content: editedTranscript,
                date: sessionDate
            )

            // Save CLEANUP transcript (edited version)
            _ = DatabaseManager.shared.saveCleanupTranscriptFile(
                sessionId: sessionId,
                content: suggestedText,
                date: sessionDate
            )

            // Save to database with version number
            // updateFullTranscript calls saveVersion internally
            DatabaseManager.shared.updateFullTranscript(sessionId: sessionId, transcript: suggestedText)

            // Get version number for feedback
            let versionNum = DatabaseManager.shared.getNextVersionNumber(sessionId: sessionId) - 1
            print("✅ Saved as v\(versionNum) for session: \(sessionId)")

            // Notify all screens to refresh
            NotificationCenter.default.post(name: .transcriptSaved, object: sessionId)
        }

        editedTranscript = suggestedText
        showComparison = false
    }

    private func rejectSuggestions() {
        // Reject suggestions - keep original, close comparison
        suggestedText = ""
        showComparison = false
    }
}

// MARK: - Empty Dictate View

struct EmptyDictateView: View {
    var body: some View {
        VStack {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Ready to record")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top)

            Text("Press REC to start dictating")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Standalone Dictate View

struct StandaloneDictateView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var recordingState: RecordingState = .idle
    @State private var transcript: String = ""
    @State private var sessionId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Transcript area
            ScrollView {
                Text(transcript.isEmpty ? "Start recording to see transcript here..." : transcript)
                    .font(.system(size: 16))
                    .foregroundColor(transcript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .textSelection(.enabled)
            }

            Divider()

            // Recorder
            HStack(spacing: 16) {
                // REC Button
                Button(action: handleStartStop) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(recordingState == .idle ? Color.red : Color.gray)
                            .frame(width: 10, height: 10)
                        Text(recordingState == .idle ? "REC" : "STOP")
                            .fontWeight(.medium)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                // Timer
                Text(formatDuration(audioRecorder.recordingDuration))
                    .font(.system(size: 20, weight: .regular, design: .monospaced))
                    .foregroundColor(recordingState == .recording ? .primary : .secondary)

                Spacer()

                // Copy button
                if !transcript.isEmpty {
                    Button(action: copyToClipboard) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func handleStartStop() {
        if recordingState == .idle {
            sessionId = UUID().uuidString
            DatabaseManager.shared.createSession(id: sessionId!)
            recordingState = .recording

            Task {
                await audioRecorder.startRecording(sessionId: sessionId!)
            }
        } else {
            audioRecorder.stopRecording()
            recordingState = .idle

            // Poll for transcript
            if let id = sessionId {
                pollForTranscript(sessionId: id)
            }
        }
    }

    private func pollForTranscript(sessionId: String) {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] timer in
            let result = DatabaseManager.shared.getTranscript(sessionId: sessionId)
            if !result.isEmpty {
                Task { @MainActor in
                    transcript = result
                }
                timer.invalidate()
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Simple Spell Check Editor

/// Simple NSTextView with Apple's built-in spell check enabled
struct SimpleSpellCheckEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        // Proper NSTextView setup with text system components
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // Disable Apple's spell check - we use custom SpellEngine
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        context.coordinator.textView = textView

        // Set initial text
        textView.string = text

        // Run custom spell check
        context.coordinator.scheduleSpellCheck()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Sync text when not editing
        if !context.coordinator.isEditing && textView.string != text {
            textView.string = text
            context.coordinator.scheduleSpellCheck()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SimpleSpellCheckEditor
        weak var textView: NSTextView?
        var isEditing = false
        private var spellCheckTask: Task<Void, Never>?
        var misspelledWords: [(range: NSRange, word: String, suggestions: [String])] = []

        init(_ parent: SimpleSpellCheckEditor) {
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
            scheduleSpellCheck()
        }

        func scheduleSpellCheck() {
            spellCheckTask?.cancel()
            spellCheckTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms debounce
                guard !Task.isCancelled else { return }
                await runSpellCheck()
            }
        }

        func runSpellCheck() async {
            guard let textView = textView else { return }

            let text = textView.string
            let misspelledRanges = await findMisspelledWords(in: text)

            applySpellCheckHighlighting(textView: textView, misspelledRanges: misspelledRanges)
        }

        func findMisspelledWords(in text: String) async -> [(range: NSRange, word: String, suggestions: [String])] {
            var results: [(range: NSRange, word: String, suggestions: [String])] = []
            let spellEngine = SpellEngine.shared

            if await !spellEngine.isDictionaryLoaded() {
                await spellEngine.loadDictionary()
            }

            let wordPattern = try? NSRegularExpression(pattern: "\\b[a-zA-Z']+\\b", options: [])
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            guard let matches = wordPattern?.matches(in: text, options: [], range: fullRange) else {
                return results
            }

            for match in matches {
                let wordRange = match.range
                let word = nsText.substring(with: wordRange)
                if word.count < 2 { continue }

                let isCorrect = await spellEngine.isCorrect(word: word)
                if !isCorrect {
                    let suggestions = await spellEngine.suggest(word: word, limit: 5)
                    results.append((range: wordRange, word: word, suggestions: suggestions))
                }
            }

            return results
        }

        func applySpellCheckHighlighting(textView: NSTextView, misspelledRanges: [(range: NSRange, word: String, suggestions: [String])]) {
            guard let textStorage = textView.textStorage else { return }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.removeAttribute(.underlineStyle, range: fullRange)
            textStorage.removeAttribute(.underlineColor, range: fullRange)

            misspelledWords = misspelledRanges

            for item in misspelledRanges {
                guard item.range.location + item.range.length <= textStorage.length else { continue }
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: item.range)
                textStorage.addAttribute(.underlineColor, value: NSColor.systemRed, range: item.range)
            }

            textView.needsDisplay = true
        }
    }
}
