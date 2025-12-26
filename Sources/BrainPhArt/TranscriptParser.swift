import Foundation

/// Represents a single parsed sentence with position metadata
struct ParsedSentence {
    let text: String
    let startOffset: Int
    let endOffset: Int
    let wordCount: Int
}

/// Represents a paragraph containing one or more sentences
struct ParsedParagraph {
    let sentences: [ParsedSentence]
    let startOffset: Int
    let endOffset: Int

    var wordCount: Int {
        sentences.reduce(0) { $0 + $1.wordCount }
    }

    var text: String {
        sentences.map { $0.text }.joined(separator: " ")
    }
}

/// Parses raw transcript text into structured sentences and paragraphs
struct TranscriptParser {

    // MARK: - Sentence Boundary Characters

    private static let sentenceTerminators: CharacterSet = CharacterSet(charactersIn: ".!?")

    // MARK: - Public API

    /// Parse transcript text into structured paragraphs containing sentences
    /// - Parameter text: Raw transcript text
    /// - Returns: Array of parsed paragraphs
    static func parse(_ text: String) -> [ParsedParagraph] {
        guard !text.isEmpty else { return [] }

        // First split by paragraph boundaries (double newlines or significant whitespace)
        let paragraphTexts = splitIntoParagraphs(text)

        var paragraphs: [ParsedParagraph] = []
        var currentOffset = 0

        for paragraphText in paragraphTexts {
            // Find the actual start of this paragraph in the original text
            if let range = text.range(of: paragraphText, range: text.index(text.startIndex, offsetBy: currentOffset)..<text.endIndex) {
                let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
                let endOffset = text.distance(from: text.startIndex, to: range.upperBound)

                let sentences = parseSentences(from: paragraphText, baseOffset: startOffset)

                if !sentences.isEmpty {
                    let paragraph = ParsedParagraph(
                        sentences: sentences,
                        startOffset: startOffset,
                        endOffset: endOffset
                    )
                    paragraphs.append(paragraph)
                }

                currentOffset = endOffset
            }
        }

        return paragraphs
    }

    /// Extract atomic thoughts - standalone ideas that could be cards
    /// - Parameter text: Raw transcript text
    /// - Returns: Array of sentences that could stand alone as ideas
    static func extractAtomicThoughts(_ text: String) -> [String] {
        let sentences = extractAllSentences(text)

        // Filter out very short sentences (< 5 words)
        // These are typically fragments or filler phrases
        return sentences.filter { sentence in
            let words = countWords(in: sentence)
            return words >= 5
        }
    }

    /// Count the total number of sentences in the text
    /// - Parameter text: Raw transcript text
    /// - Returns: Number of sentences
    static func sentenceCount(_ text: String) -> Int {
        return extractAllSentences(text).count
    }

    /// Count the total number of words in the text
    /// - Parameter text: Raw transcript text
    /// - Returns: Number of words
    static func wordCount(_ text: String) -> Int {
        return countWords(in: text)
    }

    // MARK: - Private Helpers

    /// Split text into paragraph chunks by double newlines
    private static func splitIntoParagraphs(_ text: String) -> [String] {
        // Split by double newlines (paragraph breaks)
        let pattern = #"\n\s*\n"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [text.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        let range = NSRange(text.startIndex..., in: text)
        let results = regex.matches(in: text, options: [], range: range)

        if results.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }

        var paragraphs: [String] = []
        var lastEnd = text.startIndex

        for match in results {
            if let matchRange = Range(match.range, in: text) {
                let paragraphText = String(text[lastEnd..<matchRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !paragraphText.isEmpty {
                    paragraphs.append(paragraphText)
                }
                lastEnd = matchRange.upperBound
            }
        }

        // Add remaining text after last match
        let remaining = String(text[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            paragraphs.append(remaining)
        }

        return paragraphs
    }

    /// Parse sentences from a paragraph text
    private static func parseSentences(from text: String, baseOffset: Int) -> [ParsedSentence] {
        let sentenceTexts = splitIntoSentences(text)
        var sentences: [ParsedSentence] = []
        var searchStart = text.startIndex

        for sentenceText in sentenceTexts {
            let trimmed = sentenceText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Find position in original paragraph text
            if let range = text.range(of: trimmed, range: searchStart..<text.endIndex) {
                let relativeStart = text.distance(from: text.startIndex, to: range.lowerBound)
                let relativeEnd = text.distance(from: text.startIndex, to: range.upperBound)

                let sentence = ParsedSentence(
                    text: trimmed,
                    startOffset: baseOffset + relativeStart,
                    endOffset: baseOffset + relativeEnd,
                    wordCount: countWords(in: trimmed)
                )
                sentences.append(sentence)
                searchStart = range.upperBound
            }
        }

        return sentences
    }

    /// Split text into individual sentences
    private static func splitIntoSentences(_ text: String) -> [String] {
        // Use regex to split on sentence boundaries while preserving the terminator
        // Matches . ! ? followed by space or end of string
        let pattern = #"(?<=[.!?])\s+"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [text]
        }

        let range = NSRange(text.startIndex..., in: text)
        let results = regex.matches(in: text, options: [], range: range)

        if results.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }

        var sentences: [String] = []
        var lastEnd = text.startIndex

        for match in results {
            if let matchRange = Range(match.range, in: text) {
                let sentence = String(text[lastEnd..<matchRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                lastEnd = matchRange.upperBound
            }
        }

        // Add remaining text
        let remaining = String(text[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            sentences.append(remaining)
        }

        return sentences
    }

    /// Extract all sentences from text (flat list)
    private static func extractAllSentences(_ text: String) -> [String] {
        let paragraphs = splitIntoParagraphs(text)
        return paragraphs.flatMap { splitIntoSentences($0) }
    }

    /// Count words in a string
    private static func countWords(in text: String) -> Int {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return words.count
    }
}
