import SwiftUI

// MARK: - Sentence Card Model

struct SentenceCard: Identifiable {
    let id: UUID
    let index: Int
    let text: String
    let piiMatches: [PIIMatch]
    var decision: PrivacyDecision

    enum PrivacyDecision {
        case pending
        case publicContent
        case privateContent
    }

    var isReviewed: Bool {
        decision != .pending
    }
}

// MARK: - Privacy Review View

struct PrivacyReviewView: View {
    let sessionId: String
    let transcript: String
    @Binding var isPresented: Bool

    @State private var sentenceCards: [SentenceCard] = []
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var showCompletionAlert: Bool = false

    // Swipe thresholds
    private let swipeThreshold: CGFloat = 100

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Progress bar
            progressView

            // Main card area
            if sentenceCards.isEmpty {
                emptyStateView
            } else if currentIndex >= sentenceCards.count {
                completionView
            } else {
                cardStackView
            }

            Divider()

            // Bulk actions footer
            footerView
        }
        .frame(width: 600, height: 550)
        .onAppear {
            parseSentences()
        }
        .alert("Review Complete", isPresented: $showCompletionAlert) {
            Button("Done") {
                saveDecisions()
                isPresented = false
            }
        } message: {
            let publicCount = sentenceCards.filter { $0.decision == .publicContent }.count
            let privateCount = sentenceCards.filter { $0.decision == .privateContent }.count
            Text("\(publicCount) sentences marked public\n\(privateCount) sentences marked private")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Privacy Review")
                    .font(.headline)
                Text("Swipe or tap to classify each sentence")
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

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(reviewedCount) of \(sentenceCards.count) reviewed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Quick stats
                HStack(spacing: 12) {
                    Label("\(publicCount)", systemImage: "globe")
                        .font(.caption)
                        .foregroundColor(.green)

                    Label("\(privateCount)", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * progressFraction, height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Card Stack View

    private var cardStackView: some View {
        ZStack {
            // Background cards (peek effect)
            if currentIndex + 2 < sentenceCards.count {
                SentenceCardView(card: sentenceCards[currentIndex + 2], piiHighlightColor: .orange)
                    .scaleEffect(0.9)
                    .offset(y: 20)
                    .opacity(0.3)
            }

            if currentIndex + 1 < sentenceCards.count {
                SentenceCardView(card: sentenceCards[currentIndex + 1], piiHighlightColor: .orange)
                    .scaleEffect(0.95)
                    .offset(y: 10)
                    .opacity(0.6)
            }

            // Current card with gesture
            if currentIndex < sentenceCards.count {
                SentenceCardView(card: sentenceCards[currentIndex], piiHighlightColor: .orange)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                handleSwipe(translation: value.translation)
                            }
                    )
                    .overlay(swipeIndicatorOverlay)
                    .onTapGesture {
                        toggleCurrentCard()
                    }
            }

            // Swipe hints
            swipeHintsView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Swipe Indicator Overlay

    private var swipeIndicatorOverlay: some View {
        ZStack {
            // Left swipe indicator (Private)
            if dragOffset.width < -30 {
                HStack {
                    Spacer()
                    VStack {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 40))
                        Text("VAULT")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.red)
                    .padding()
                }
                .opacity(min(1, abs(dragOffset.width) / swipeThreshold))
            }

            // Right swipe indicator (Public)
            if dragOffset.width > 30 {
                HStack {
                    VStack {
                        Image(systemName: "globe")
                            .font(.system(size: 40))
                        Text("PUBLIC")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.green)
                    .padding()
                    Spacer()
                }
                .opacity(min(1, dragOffset.width / swipeThreshold))
            }
        }
    }

    // MARK: - Swipe Hints

    private var swipeHintsView: some View {
        HStack {
            // Left hint
            VStack(spacing: 4) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20))
                Text("PRIVATE")
                    .font(.system(size: 10, weight: .medium))
                Text("Vault")
                    .font(.system(size: 9))
            }
            .foregroundColor(.red.opacity(0.6))
            .frame(width: 60)

            Spacer()

            // Right hint
            VStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 20))
                Text("PUBLIC")
                    .font(.system(size: 10, weight: .medium))
                Text("Keep")
                    .font(.system(size: 9))
            }
            .foregroundColor(.green.opacity(0.6))
            .frame(width: 60)
        }
        .padding(.horizontal, 20)
        .padding(.top, 200)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No sentences to review")
                .font(.headline)
            Text("The transcript appears to be empty or could not be parsed into sentences.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
        }
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Review Complete!")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                HStack(spacing: 20) {
                    Label("\(publicCount) Public", systemImage: "globe")
                        .foregroundColor(.green)
                    Label("\(privateCount) Private", systemImage: "lock.fill")
                        .foregroundColor(.red)
                }
                .font(.headline)
            }

            Button(action: {
                saveDecisions()
                isPresented = false
            }) {
                Text("Save & Close")
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            Spacer()
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 16) {
            // Mark All Private
            Button(action: markAllPrivate) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                    Text("Mark All Private")
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Navigation buttons
            if !sentenceCards.isEmpty && currentIndex < sentenceCards.count {
                HStack(spacing: 8) {
                    Button(action: goToPrevious) {
                        Image(systemName: "chevron.left")
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex == 0)

                    Text("\(currentIndex + 1) / \(sentenceCards.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(width: 60)

                    Button(action: goToNext) {
                        Image(systemName: "chevron.right")
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex >= sentenceCards.count - 1)
                }
            }

            Spacer()

            // Mark All Public
            Button(action: markAllPublic) {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                    Text("Mark All Public")
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .foregroundColor(.green)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Computed Properties

    private var reviewedCount: Int {
        sentenceCards.filter { $0.isReviewed }.count
    }

    private var publicCount: Int {
        sentenceCards.filter { $0.decision == .publicContent }.count
    }

    private var privateCount: Int {
        sentenceCards.filter { $0.decision == .privateContent }.count
    }

    private var progressFraction: CGFloat {
        guard !sentenceCards.isEmpty else { return 0 }
        return CGFloat(reviewedCount) / CGFloat(sentenceCards.count)
    }

    // MARK: - Actions

    private func parseSentences() {
        let paragraphs = TranscriptParser.parse(transcript)
        var cards: [SentenceCard] = []
        var index = 0

        for paragraph in paragraphs {
            for sentence in paragraph.sentences {
                // Scan for PII in this sentence
                let piiMatches = PrivacyScanner.fullScan(sentence.text)

                let card = SentenceCard(
                    id: UUID(),
                    index: index,
                    text: sentence.text,
                    piiMatches: piiMatches,
                    decision: .pending
                )
                cards.append(card)
                index += 1
            }
        }

        sentenceCards = cards
    }

    private func handleSwipe(translation: CGSize) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if translation.width < -swipeThreshold {
                // Swipe left - mark private
                markCurrentCard(as: .privateContent)
                advanceToNext()
            } else if translation.width > swipeThreshold {
                // Swipe right - mark public
                markCurrentCard(as: .publicContent)
                advanceToNext()
            }
            dragOffset = .zero
        }
    }

    private func toggleCurrentCard() {
        guard currentIndex < sentenceCards.count else { return }

        let current = sentenceCards[currentIndex].decision
        let newDecision: SentenceCard.PrivacyDecision

        switch current {
        case .pending, .publicContent:
            newDecision = .privateContent
        case .privateContent:
            newDecision = .publicContent
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            sentenceCards[currentIndex].decision = newDecision
        }
    }

    private func markCurrentCard(as decision: SentenceCard.PrivacyDecision) {
        guard currentIndex < sentenceCards.count else { return }
        sentenceCards[currentIndex].decision = decision
    }

    private func advanceToNext() {
        if currentIndex < sentenceCards.count - 1 {
            currentIndex += 1
        } else if reviewedCount == sentenceCards.count {
            showCompletionAlert = true
        }
    }

    private func goToPrevious() {
        if currentIndex > 0 {
            withAnimation {
                currentIndex -= 1
            }
        }
    }

    private func goToNext() {
        if currentIndex < sentenceCards.count - 1 {
            withAnimation {
                currentIndex += 1
            }
        }
    }

    private func markAllPublic() {
        withAnimation {
            for i in 0..<sentenceCards.count {
                sentenceCards[i].decision = .publicContent
            }
            currentIndex = sentenceCards.count
        }
    }

    private func markAllPrivate() {
        withAnimation {
            for i in 0..<sentenceCards.count {
                sentenceCards[i].decision = .privateContent
            }
            currentIndex = sentenceCards.count
        }
    }

    private func saveDecisions() {
        // Create cards from sentences based on privacy decisions
        for card in sentenceCards {
            let pile: String
            let isPrivate: Bool

            switch card.decision {
            case .privateContent:
                pile = CardPile.vault.rawValue
                isPrivate = true
            case .publicContent:
                pile = CardPile.inbox.rawValue
                isPrivate = false
            case .pending:
                // Skip unreviewed cards
                continue
            }

            // Create card in database
            let cardId = DatabaseManager.shared.createCard(
                sessionId: sessionId,
                content: card.text,
                pile: pile
            )

            // Update privacy flag if private
            if isPrivate {
                DatabaseManager.shared.updateCardPrivacy(cardId: cardId, isPrivate: true)
            }
        }

        print("Saved \(sentenceCards.filter { $0.isReviewed }.count) cards from privacy review")
    }
}

// MARK: - Sentence Card View

struct SentenceCardView: View {
    let card: SentenceCard
    let piiHighlightColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Card number badge
            HStack {
                Text("Sentence \(card.index + 1)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                // Decision indicator
                if card.decision != .pending {
                    HStack(spacing: 4) {
                        Image(systemName: card.decision == .privateContent ? "lock.fill" : "globe")
                        Text(card.decision == .privateContent ? "Private" : "Public")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(card.decision == .privateContent ? .red : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (card.decision == .privateContent ? Color.red : Color.green)
                            .opacity(0.15)
                    )
                    .cornerRadius(4)
                }
            }

            // Sentence text with PII highlighting
            highlightedText
                .font(.system(size: 16))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // PII warnings
            if !card.piiMatches.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Detected PII:")
                            .fontWeight(.medium)
                    }
                    .font(.caption)

                    FlowLayout(spacing: 6) {
                        ForEach(card.piiMatches.indices, id: \.self) { index in
                            let match = card.piiMatches[index]
                            HStack(spacing: 4) {
                                Text(match.patternName)
                                    .font(.system(size: 10))
                                Text("\"" + match.matchedText.prefix(20) + (match.matchedText.count > 20 ? "..." : "") + "\"")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // Tap hint
            Text("Tap to toggle, swipe to classify")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .frame(maxWidth: 450, minHeight: 250, maxHeight: 350)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: 2)
        )
    }

    private var borderColor: Color {
        switch card.decision {
        case .privateContent:
            return .red.opacity(0.5)
        case .publicContent:
            return .green.opacity(0.5)
        case .pending:
            return .clear
        }
    }

    private var highlightedText: Text {
        guard !card.piiMatches.isEmpty else {
            return Text(card.text)
        }

        // Build attributed text with highlights
        var result = Text("")
        var lastEnd = card.text.startIndex

        // Sort matches by offset
        let sortedMatches = card.piiMatches.sorted { $0.startOffset < $1.startOffset }

        for match in sortedMatches {
            // Bounds check
            guard match.startOffset >= 0,
                  match.endOffset <= card.text.count,
                  match.startOffset < match.endOffset else {
                continue
            }

            let startIndex = card.text.index(card.text.startIndex, offsetBy: match.startOffset)
            let endIndex = card.text.index(card.text.startIndex, offsetBy: match.endOffset)

            // Skip if this match starts before the last one ended (overlapping)
            guard startIndex >= lastEnd else { continue }

            // Add text before this match
            if startIndex > lastEnd {
                result = result + Text(String(card.text[lastEnd..<startIndex]))
            }

            // Add highlighted match
            result = result + Text(String(card.text[startIndex..<endIndex]))
                .foregroundColor(.orange)
                .fontWeight(.medium)

            lastEnd = endIndex
        }

        // Add remaining text
        if lastEnd < card.text.endIndex {
            result = result + Text(String(card.text[lastEnd...]))
        }

        return result
    }
}

// MARK: - Flow Layout (for PII tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing

                self.size.width = max(self.size.width, x)
            }

            self.size.height = y + lineHeight
        }
    }
}

// MARK: - Privacy Review Button

struct PrivacyReviewButton: View {
    let sessionId: String
    let transcript: String
    @State private var showPrivacyReview = false

    var body: some View {
        Button(action: { showPrivacyReview = true }) {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack.badge.person.crop")
                Text("Privacy Review")
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(transcript.isEmpty)
        .sheet(isPresented: $showPrivacyReview) {
            PrivacyReviewView(
                sessionId: sessionId,
                transcript: transcript,
                isPresented: $showPrivacyReview
            )
        }
    }
}
