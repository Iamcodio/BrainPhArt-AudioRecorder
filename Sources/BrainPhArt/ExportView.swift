import SwiftUI
import AppKit

// MARK: - Export Format

enum ExportFormat: String, CaseIterable {
    case markdown = "Markdown (.md)"
    case plainText = "Plain Text (.txt)"
    case json = "JSON (.json)"
    case blogHTML = "Blog HTML"
    case twitterThread = "Twitter Thread"

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .plainText: return "txt"
        case .json: return "json"
        case .blogHTML: return "html"
        case .twitterThread: return "txt"
        }
    }

    var icon: String {
        switch self {
        case .markdown: return "doc.text"
        case .plainText: return "doc.plaintext"
        case .json: return "curlybraces"
        case .blogHTML: return "globe"
        case .twitterThread: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - Export Options

struct ExportOptions {
    var includeMetadata: Bool = true
    var includeTimestamps: Bool = true
    var groupByDomain: Bool = true
    var include4DScores: Bool = false
    var maxTweetLength: Int = 280
}

// MARK: - Export View

struct ExportView: View {
    @Binding var isPresented: Bool
    let cards: [CardModel]

    @State private var selectedFormat: ExportFormat = .markdown
    @State private var options = ExportOptions()
    @State private var previewContent: String = ""
    @State private var isExporting = false
    @State private var exportSuccess = false
    @State private var exportPath: String = ""

    // Filter to public cards only
    private var publicCards: [CardModel] {
        cards.filter { $0.pileEnum.isPublic && $0.pile != CardPile.kill.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Main content
            HSplitView {
                // Options panel
                optionsPanel
                    .frame(minWidth: 250, maxWidth: 300)

                // Preview panel
                previewPanel
            }

            Divider()

            // Footer with export button
            footerView
        }
        .frame(width: 800, height: 600)
        .onAppear {
            generatePreview()
        }
        .onChange(of: selectedFormat) { _ in
            generatePreview()
        }
        .onChange(of: options.includeMetadata) { _ in
            generatePreview()
        }
        .onChange(of: options.includeTimestamps) { _ in
            generatePreview()
        }
        .onChange(of: options.groupByDomain) { _ in
            generatePreview()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Public Cards")
                    .font(.headline)
                Text("\(publicCards.count) cards ready to export (private cards excluded)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.escape)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Options Panel

    private var optionsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Format Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("FORMAT")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button(action: { selectedFormat = format }) {
                            HStack(spacing: 12) {
                                Image(systemName: format.icon)
                                    .frame(width: 20)
                                Text(format.rawValue)
                                    .font(.system(size: 13))
                                Spacer()
                                if selectedFormat == format {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedFormat == format ? Color.accentColor.opacity(0.1) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // Options
                VStack(alignment: .leading, spacing: 12) {
                    Text("OPTIONS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Toggle("Include metadata", isOn: $options.includeMetadata)
                        .font(.system(size: 13))

                    Toggle("Include timestamps", isOn: $options.includeTimestamps)
                        .font(.system(size: 13))

                    if selectedFormat == .markdown || selectedFormat == .blogHTML {
                        Toggle("Group by domain", isOn: $options.groupByDomain)
                            .font(.system(size: 13))

                        Toggle("Include 4D scores", isOn: $options.include4DScores)
                            .font(.system(size: 13))
                    }

                    if selectedFormat == .twitterThread {
                        Stepper("Max tweet length: \(options.maxTweetLength)", value: $options.maxTweetLength, in: 100...280)
                            .font(.system(size: 13))
                    }
                }

                Divider()

                // Stats
                VStack(alignment: .leading, spacing: 8) {
                    Text("SUMMARY")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    statsRow("Total cards:", "\(publicCards.count)")
                    statsRow("From INBOX:", "\(publicCards.filter { $0.pile == CardPile.inbox.rawValue }.count)")
                    statsRow("From SHAPING:", "\(publicCards.filter { $0.pile == CardPile.shaping.rawValue }.count)")
                    statsRow("From ACTIVE:", "\(publicCards.filter { $0.pile == CardPile.active.rawValue }.count)")
                    statsRow("From SHIPPED:", "\(publicCards.filter { $0.pile == CardPile.shipped.rawValue }.count)")
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func statsRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }

    // MARK: - Preview Panel

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PREVIEW")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                Text(previewContent)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if exportSuccess {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Exported to: \(exportPath)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button(action: exportToFile) {
                HStack(spacing: 6) {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text("Export")
                }
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(isExporting || publicCards.isEmpty)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Export Logic

    private func generatePreview() {
        switch selectedFormat {
        case .markdown:
            previewContent = generateMarkdown()
        case .plainText:
            previewContent = generatePlainText()
        case .json:
            previewContent = generateJSON()
        case .blogHTML:
            previewContent = generateBlogHTML()
        case .twitterThread:
            previewContent = generateTwitterThread()
        }
    }

    private func generateMarkdown() -> String {
        var output = ""

        if options.includeMetadata {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            output += "# Exported Cards\n\n"
            output += "*Exported on \(formatter.string(from: Date()))*\n\n"
            output += "---\n\n"
        }

        if options.groupByDomain {
            // Group cards by domain classification
            let grouped = groupCardsByDomain()
            for (domain, domainCards) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                output += "## \(domain.emoji) \(domain.displayName)\n\n"
                for card in domainCards {
                    output += formatCardMarkdown(card)
                }
                output += "\n"
            }
        } else {
            for card in publicCards {
                output += formatCardMarkdown(card)
            }
        }

        return output
    }

    private func formatCardMarkdown(_ card: CardModel) -> String {
        var line = "- \(card.content)"

        if options.includeTimestamps {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let date = Date(timeIntervalSince1970: TimeInterval(card.createdAt))
            line += " *(\(formatter.string(from: date)))*"
        }

        if options.include4DScores {
            // Calculate estimated 4D scores using heuristics
            let wordCount = card.content.split(separator: " ").count
            let clarity = min(10, max(3, wordCount / 3))
            let impact = 6
            let actionable = card.content.contains("should") || card.content.contains("need") ? 8 : 5
            let universal = wordCount < 20 ? 7 : 5
            line += " `[C:\(clarity) I:\(impact) A:\(actionable) U:\(universal)]`"
        }

        return line + "\n"
    }

    private func generatePlainText() -> String {
        var output = ""

        for (index, card) in publicCards.enumerated() {
            output += "\(index + 1). \(card.content)\n"
            if options.includeTimestamps {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, yyyy"
                let date = Date(timeIntervalSince1970: TimeInterval(card.createdAt))
                output += "   [\(formatter.string(from: date))]\n"
            }
            output += "\n"
        }

        return output
    }

    private func generateJSON() -> String {
        var cards: [[String: Any]] = []

        for card in publicCards {
            var cardDict: [String: Any] = [
                "id": card.id,
                "content": card.content,
                "pile": card.pile
            ]

            if options.includeTimestamps {
                cardDict["createdAt"] = card.createdAt
            }

            if options.includeMetadata {
                cardDict["sessionId"] = card.sessionId ?? NSNull()
            }

            cards.append(cardDict)
        }

        let wrapper: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "cardCount": cards.count,
            "cards": cards
        ]

        if let data = try? JSONSerialization.data(withJSONObject: wrapper, options: .prettyPrinted),
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        return "{}"
    }

    private func generateBlogHTML() -> String {
        var output = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Exported Cards</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 800px; margin: 0 auto; padding: 2rem; line-height: 1.6; }
                .card { background: #f9f9f9; border-left: 4px solid #007AFF; padding: 1rem; margin: 1rem 0; border-radius: 4px; }
                .meta { font-size: 0.8rem; color: #666; margin-top: 0.5rem; }
                h2 { border-bottom: 2px solid #eee; padding-bottom: 0.5rem; }
            </style>
        </head>
        <body>
        """

        if options.groupByDomain {
            let grouped = groupCardsByDomain()
            for (domain, domainCards) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                output += "<h2>\(domain.emoji) \(domain.displayName)</h2>\n"
                for card in domainCards {
                    output += "<div class=\"card\">\n"
                    output += "  <p>\(escapeHTML(card.content))</p>\n"
                    if options.includeTimestamps {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MMM d, yyyy"
                        let date = Date(timeIntervalSince1970: TimeInterval(card.createdAt))
                        output += "  <div class=\"meta\">\(formatter.string(from: date))</div>\n"
                    }
                    output += "</div>\n"
                }
            }
        } else {
            for card in publicCards {
                output += "<div class=\"card\">\n"
                output += "  <p>\(escapeHTML(card.content))</p>\n"
                output += "</div>\n"
            }
        }

        output += """
        </body>
        </html>
        """

        return output
    }

    private func generateTwitterThread() -> String {
        var tweets: [String] = []
        var currentTweet = ""
        var tweetNumber = 1

        for card in publicCards {
            let content = card.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // If content fits in one tweet
            if content.count <= options.maxTweetLength - 10 {
                tweets.append("\(tweetNumber)/\n\n\(content)")
                tweetNumber += 1
            } else {
                // Split into multiple tweets
                let words = content.split(separator: " ")
                currentTweet = "\(tweetNumber)/\n\n"

                for word in words {
                    let testTweet = currentTweet + word + " "
                    if testTweet.count > options.maxTweetLength {
                        tweets.append(currentTweet.trimmingCharacters(in: .whitespaces) + "...")
                        tweetNumber += 1
                        currentTweet = "\(tweetNumber)/\n\n..." + word + " "
                    } else {
                        currentTweet = testTweet
                    }
                }

                if !currentTweet.trimmingCharacters(in: .whitespaces).isEmpty {
                    tweets.append(currentTweet.trimmingCharacters(in: .whitespaces))
                    tweetNumber += 1
                }
            }
        }

        return tweets.joined(separator: "\n\n---\n\n")
    }

    private func groupCardsByDomain() -> [BrainDumpProcessor.Domain: [CardModel]] {
        var grouped: [BrainDumpProcessor.Domain: [CardModel]] = [:]

        for card in publicCards {
            // Use BrainDumpProcessor to classify domain
            let domain = classifyDomainSync(card.content)
            if grouped[domain] == nil {
                grouped[domain] = []
            }
            grouped[domain]?.append(card)
        }

        return grouped
    }

    private func classifyDomainSync(_ text: String) -> BrainDumpProcessor.Domain {
        // Quick keyword-based classification (same logic as BrainDumpProcessor)
        let lower = text.lowercased()
        var scores: [BrainDumpProcessor.Domain: Int] = [:]

        for domain in BrainDumpProcessor.Domain.allCases {
            let count = domain.keywords.filter { lower.contains($0) }.count
            scores[domain] = count
        }

        if let best = scores.max(by: { $0.value < $1.value }), best.value > 0 {
            return best.key
        }
        return .creativeIdeas
    }

    private func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(previewContent, forType: .string)
    }

    private func exportToFile() {
        isExporting = true

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "exported_cards.\(selectedFormat.fileExtension)"
        panel.title = "Export Cards"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try previewContent.write(to: url, atomically: true, encoding: .utf8)
                exportPath = url.path
                exportSuccess = true
            } catch {
                print("Export failed: \(error)")
            }
        }

        isExporting = false
    }
}

// MARK: - Export Button (for toolbar)

struct ExportCardsButton: View {
    @State private var showExport = false
    @State private var cards: [CardModel] = []

    var body: some View {
        Button(action: {
            loadCards()
            showExport = true
        }) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                Text("Export")
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showExport) {
            ExportView(isPresented: $showExport, cards: cards)
        }
    }

    private func loadCards() {
        let dbCards = DatabaseManager.shared.getCards(pile: nil)
        cards = dbCards.map { tuple in
            CardModel(
                id: tuple.id,
                sessionId: tuple.sessionId,
                content: tuple.content,
                pile: tuple.pile,
                isPrivate: tuple.isPrivate,
                createdAt: tuple.createdAt,
                movedAt: tuple.movedAt
            )
        }
    }
}
