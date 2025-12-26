import SwiftUI
import AppKit

/// Editor Module - Hemingway-style editing with readability analysis
/// Can be used standalone or integrated into the main app.
/// Provides: spell check, readability grades, sentence analysis

// MARK: - Editor View (Standalone)

struct StandaloneEditorView: View {
    @Binding var text: String
    var onSave: (() -> Void)?
    var showPrivacyTools: Bool = false
    var sessionId: String? = nil

    @StateObject private var analysis = ReadabilityAnalysis()

    var body: some View {
        HSplitView {
            // Left: Editor with inline spell check
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    if showPrivacyTools, let id = sessionId {
                        PrivacyGateButton(unreviewedCount: 0, sessionId: id)
                        ExtractCardsButton(sessionId: id, transcript: text)
                        PrivacyReviewButton(sessionId: id, transcript: text)
                    }

                    Spacer()

                    if let save = onSave {
                        Button(action: save) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Save")
                            }
                        }
                        .keyboardShortcut("s", modifiers: .command)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Editor with inline spell check
                InlineSpellTextView(
                    text: $text,
                    isSpellCheckEnabled: true,
                    onSave: onSave
                )
            }
            .frame(minWidth: 500)

            // Right: Stats sidebar (Hemingway style)
            ReadabilitySidebar(analysis: analysis)
                .frame(width: 220)
        }
        .onChange(of: text) { newValue in
            analysis.analyze(newValue)
        }
        .onAppear {
            analysis.analyze(text)
        }
    }
}

// MARK: - Edit Tab View (For use in tabbed app)

struct EditTabView: View {
    @Binding var transcript: String
    let selectedRecording: RecordingItem?
    let unreviewedPIICount: Int
    let onSave: () -> Void

    @StateObject private var readabilityAnalysis = ReadabilityAnalysis()
    @State private var isPrivateMode = false
    @State private var showAddToCard = false
    @State private var selectedText = ""

    var body: some View {
        HSplitView {
            // Left: Editor with highlighting
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    if let selected = selectedRecording {
                        Text(selected.dateString)
                            .font(.headline)
                    }

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

                    // Add to Card button
                    Button(action: { addSelectionToCard() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.stack.badge.plus")
                            Text("Add to Card")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                    .help("Add selected text to a new card")

                    if let selected = selectedRecording {
                        ExtractCardsButton(
                            sessionId: selected.id,
                            transcript: transcript
                        )

                        PrivacyReviewButton(
                            sessionId: selected.id,
                            transcript: transcript
                        )
                    }

                    Spacer()

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

                // Editor - using simple TextEditor for now
                ZStack(alignment: .topLeading) {
                    Color(NSColor.textBackgroundColor)

                    if transcript.isEmpty {
                        Text("Select a recording in DICTATE tab, or start typing here...")
                            .foregroundColor(.secondary)
                            .padding(20)
                    }

                    TextEditor(text: $transcript)
                        .font(.system(size: 16))
                        .scrollContentBackground(.hidden)
                        .padding(16)
                }
                .id(selectedRecording?.id ?? "editor")
            }
            .frame(minWidth: 500)

            // Right: Stats sidebar
            ReadabilitySidebar(analysis: readabilityAnalysis)
                .frame(width: 220)
        }
        .onChange(of: transcript) { newValue in
            readabilityAnalysis.analyze(newValue)
        }
        .onAppear {
            readabilityAnalysis.analyze(transcript)
        }
    }

    private func addSelectionToCard() {
        // Get selected text from clipboard (user would copy first)
        // For now, create a card from the whole transcript if nothing selected
        let textToAdd = NSPasteboard.general.string(forType: .string) ?? ""

        if textToAdd.isEmpty {
            // Show prompt to select text first
            return
        }

        // Create card with selected text
        _ = DatabaseManager.shared.createCard(
            sessionId: selectedRecording?.id,
            content: textToAdd,
            pile: isPrivateMode ? "VAULT" : "INBOX"
        )
    }
}

// MARK: - Readability Sidebar

struct ReadabilitySidebar: View {
    @ObservedObject var analysis: ReadabilityAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Readability header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Readability")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }

                Text("Grade \(analysis.gradeLevel)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(analysis.gradeColor)

                Text(analysis.gradeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Stats
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Words:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(analysis.wordCount)")
                }
                .font(.system(size: 12))

                HStack {
                    Text("Sentences:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(analysis.sentenceCount)")
                }
                .font(.system(size: 12))
            }
            .padding()

            Divider()

            // Issue counts (Hemingway style)
            VStack(alignment: .leading, spacing: 8) {
                IssueCountRow(
                    count: analysis.hardSentences,
                    label: "hard to read.",
                    color: .yellow
                )

                IssueCountRow(
                    count: analysis.veryHardSentences,
                    label: "very hard to read.",
                    color: .red
                )

                IssueCountRow(
                    count: 0,
                    label: "spelling or grammar issues.",
                    color: .green
                )

                IssueCountRow(
                    count: analysis.adverbs,
                    label: "adverbs.",
                    color: .blue
                )

                IssueCountRow(
                    count: analysis.passiveVoice,
                    label: "passive voice.",
                    color: .purple
                )
            }
            .padding()

            Spacer()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Issue Count Row (Hemingway style)

struct IssueCountRow: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text("\(count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(color)
                .cornerRadius(4)

            Text("\(count == 1 ? "sentence is" : "sentences are") \(label)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Readability Analysis

@MainActor
class ReadabilityAnalysis: ObservableObject {
    @Published var gradeLevel: Int = 0
    @Published var wordCount: Int = 0
    @Published var sentenceCount: Int = 0
    @Published var hardSentences: Int = 0
    @Published var veryHardSentences: Int = 0
    @Published var adverbs: Int = 0
    @Published var passiveVoice: Int = 0

    var gradeColor: Color {
        if gradeLevel <= 6 { return .green }
        if gradeLevel <= 10 { return .yellow }
        return .red
    }

    var gradeDescription: String {
        if gradeLevel <= 6 { return "Good" }
        if gradeLevel <= 10 { return "OK" }
        return "Poor"
    }

    func analyze(_ text: String) {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        wordCount = words.count

        // Simple sentence detection
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        sentenceCount = max(1, sentences.count)

        // Flesch-Kincaid Grade Level (simplified)
        let avgWordsPerSentence = Double(wordCount) / Double(sentenceCount)
        let syllables = words.reduce(0) { $0 + countSyllables(String($1)) }
        let avgSyllablesPerWord = Double(syllables) / max(1, Double(wordCount))

        let fkGrade = 0.39 * avgWordsPerSentence + 11.8 * avgSyllablesPerWord - 15.59
        gradeLevel = max(1, min(20, Int(round(fkGrade))))

        // Count hard sentences (> 20 words)
        hardSentences = sentences.filter { sentence in
            sentence.split(whereSeparator: { $0.isWhitespace }).count > 20
        }.count

        // Count very hard sentences (> 30 words)
        veryHardSentences = sentences.filter { sentence in
            sentence.split(whereSeparator: { $0.isWhitespace }).count > 30
        }.count

        // Count adverbs (words ending in -ly)
        adverbs = words.filter { $0.lowercased().hasSuffix("ly") }.count

        // Count passive voice indicators
        let passivePatterns = ["was ", "were ", "been ", "being ", "is being", "are being"]
        passiveVoice = passivePatterns.reduce(0) { count, pattern in
            count + text.lowercased().components(separatedBy: pattern).count - 1
        }
    }

    private func countSyllables(_ word: String) -> Int {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        let word = word.lowercased()
        var count = 0
        var prevWasVowel = false

        for char in word {
            let isVowel = vowels.contains(char)
            if isVowel && !prevWasVowel {
                count += 1
            }
            prevWasVowel = isVowel
        }

        // Adjust for silent e
        if word.hasSuffix("e") && count > 1 {
            count -= 1
        }

        return max(1, count)
    }
}
