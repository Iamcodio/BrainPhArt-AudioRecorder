import SwiftUI

/// Pirsig-style card system - atomic thoughts organized into piles.
/// Based on Robert Pirsig's index card method from Lila.

// MARK: - Card Piles

enum CardPile: String, CaseIterable {
    case inbox = "INBOX"
    case vault = "VAULT"      // Private cards - never leave device
    case shaping = "SHAPING"
    case active = "ACTIVE"
    case shipped = "SHIPPED"
    case hold = "HOLD"
    case kill = "KILL"

    var displayName: String {
        rawValue
    }

    var description: String {
        switch self {
        case .inbox: return "Unsorted raw ideas"
        case .vault: return "Private - never shared"
        case .shaping: return "Being refined"
        case .active: return "In progress now"
        case .shipped: return "Published/complete"
        case .hold: return "On hold for later"
        case .kill: return "Not pursuing"
        }
    }

    var color: Color {
        switch self {
        case .inbox: return .gray
        case .vault: return .red      // Red = private
        case .shaping: return .blue
        case .active: return .orange
        case .shipped: return .green
        case .hold: return .purple
        case .kill: return .secondary
        }
    }

    /// Is this a "public" pile (can be exported/shared)?
    var isPublic: Bool {
        switch self {
        case .vault, .kill: return false
        default: return true
        }
    }
}

// MARK: - Card Model

struct CardModel: Identifiable {
    let id: String
    let sessionId: String?
    let content: String
    var pile: String
    let isPrivate: Bool
    let createdAt: Int
    let movedAt: Int?

    var pileEnum: CardPile {
        CardPile(rawValue: pile) ?? .inbox
    }
}

// MARK: - Cards Panel (Sidebar)

struct CardsPanel: View {
    let sessionId: String?
    @State private var cards: [CardModel] = []
    @State private var selectedPile: CardPile = .inbox
    @State private var showCreateCard = false
    @State private var newCardContent = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("CARDS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                // Export button
                ExportCardsButton()

                Button(action: { showCreateCard = true }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Create new card")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Pile selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CardPile.allCases, id: \.self) { pile in
                        PileTab(
                            pile: pile,
                            isSelected: selectedPile == pile,
                            count: cards.filter { $0.pile == pile.rawValue }.count,
                            onSelect: { selectedPile = pile }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)

            Divider()

            // Cards list
            if filteredCards.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No cards in \(selectedPile.displayName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if selectedPile == .inbox {
                        Text("Extract thoughts from transcripts or create new cards")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCards) { card in
                            CardRow(card: card, onMove: { newPile in
                                moveCard(card, to: newPile)
                            })
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear { loadCards() }
        .sheet(isPresented: $showCreateCard) {
            CreateCardSheet(
                isPresented: $showCreateCard,
                sessionId: sessionId,
                onCreate: { content in
                    createCard(content: content)
                }
            )
        }
    }

    private var filteredCards: [CardModel] {
        cards.filter { $0.pile == selectedPile.rawValue }
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

    private func createCard(content: String) {
        _ = DatabaseManager.shared.createCard(
            sessionId: sessionId,
            content: content,
            pile: CardPile.inbox.rawValue
        )
        loadCards()
    }

    private func moveCard(_ card: CardModel, to pile: CardPile) {
        DatabaseManager.shared.moveCard(cardId: card.id, toPile: pile.rawValue)
        loadCards()
    }
}

// MARK: - Pile Tab

struct PileTab: View {
    let pile: CardPile
    let isSelected: Bool
    let count: Int
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                Circle()
                    .fill(pile.color)
                    .frame(width: 6, height: 6)
                Text(pile.displayName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(pile.color.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? pile.color.opacity(0.15) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card Row

struct CardRow: View {
    let card: CardModel
    let onMove: (CardPile) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            // Main card content
            VStack(alignment: .leading, spacing: 6) {
                // Content
                Text(card.content)
                    .font(.system(size: 12))
                    .lineLimit(4)

                // Footer
                HStack {
                    // Privacy indicator
                    if card.isPrivate || card.pile == CardPile.vault.rawValue {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    }

                    // Source indicator
                    if card.sessionId != nil {
                        Image(systemName: "waveform")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Date
                    Text(formatDate(card.createdAt))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)

            // Quick action buttons (visible on hover)
            if isHovering {
                VStack(spacing: 4) {
                    // Mark Private (vault)
                    if card.pile != CardPile.vault.rawValue {
                        Button(action: { onMove(.vault) }) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.red)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Mark Private")
                    } else {
                        // Make Public (back to inbox)
                        Button(action: { onMove(.inbox) }) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Make Public")
                    }
                }
                .padding(.trailing, 6)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(card.pileEnum.color.opacity(0.3), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .contextMenu {
            // Quick privacy toggle at top
            if card.pile != CardPile.vault.rawValue {
                Button(action: { onMove(.vault) }) {
                    Label("Mark Private (Vault)", systemImage: "lock.fill")
                }
            } else {
                Button(action: { onMove(.inbox) }) {
                    Label("Make Public (Inbox)", systemImage: "globe")
                }
            }

            Divider()

            ForEach(CardPile.allCases, id: \.self) { pile in
                if pile.rawValue != card.pile && pile != .vault {
                    Button(action: { onMove(pile) }) {
                        Label("Move to \(pile.displayName)", systemImage: pileIcon(pile))
                    }
                }
            }
            Divider()
            Button(role: .destructive, action: {
                onMove(.kill)
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func formatDate(_ timestamp: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private func pileIcon(_ pile: CardPile) -> String {
        switch pile {
        case .inbox: return "tray"
        case .vault: return "lock.fill"
        case .shaping: return "hammer"
        case .active: return "bolt"
        case .shipped: return "checkmark.circle"
        case .hold: return "pause.circle"
        case .kill: return "trash"
        }
    }
}

// MARK: - Create Card Sheet

struct CreateCardSheet: View {
    @Binding var isPresented: Bool
    let sessionId: String?
    let onCreate: (String) -> Void

    @State private var content = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Card")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Content editor
            TextEditor(text: $content)
                .font(.system(size: 14))
                .focused($isFocused)
                .padding()

            Divider()

            // Footer
            HStack {
                Text("Cards go to INBOX")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Create") {
                    if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onCreate(content)
                        isPresented = false
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Extract Cards Button

struct ExtractCardsButton: View {
    let sessionId: String
    let transcript: String
    @State private var isExtracting = false
    @State private var showResult = false
    @State private var extractedCount = 0

    var body: some View {
        Button(action: extractCards) {
            HStack(spacing: 4) {
                if isExtracting {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "rectangle.stack.badge.plus")
                }
                Text("Extract Cards")
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(isExtracting || transcript.isEmpty)
        .popover(isPresented: $showResult) {
            Text("Extracted \(extractedCount) cards to INBOX")
                .padding()
        }
    }

    private func extractCards() {
        isExtracting = true

        Task {
            // Use TranscriptParser to get atomic thoughts
            let thoughts = TranscriptParser.extractAtomicThoughts(transcript)

            var count = 0
            for thought in thoughts {
                _ = DatabaseManager.shared.createCard(
                    sessionId: sessionId,
                    content: thought,
                    pile: "INBOX"
                )
                count += 1
            }

            await MainActor.run {
                isExtracting = false
                extractedCount = count
                showResult = true

                // Auto-hide popover
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showResult = false
                }
            }
        }
    }
}

// MARK: - CARDS Tab (Full card management)

struct CardsTabView: View {
    let sessionId: String?

    @State private var cards: [CardModel] = []
    @State private var selectedPile: CardPile = .inbox
    @State private var showCreateCard = false
    @State private var newCardContent = ""

    var body: some View {
        HSplitView {
            // Left: Pile list
            VStack(alignment: .leading, spacing: 0) {
                Text("PILES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ForEach(CardPile.allCases, id: \.self) { pile in
                    Button(action: { selectedPile = pile }) {
                        HStack {
                            Circle()
                                .fill(pile.color)
                                .frame(width: 8, height: 8)

                            Text(pile.displayName)
                                .font(.system(size: 13))

                            Spacer()

                            let count = cards.filter { $0.pile == pile.rawValue }.count
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedPile == pile ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Export button
                ExportCardsButton()
                    .padding()
            }
            .frame(width: 180)
            .background(Color(NSColor.controlBackgroundColor))

            // Right: Cards in selected pile
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(selectedPile.displayName)
                        .font(.headline)

                    Text("- \(selectedPile.description)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: { showCreateCard = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("New Card")
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(4)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Cards grid
                let filteredCards = cards.filter { $0.pile == selectedPile.rawValue }

                if filteredCards.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No cards in \(selectedPile.displayName)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(selectedPile.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ], spacing: 16) {
                            ForEach(filteredCards) { card in
                                CardGridItem(card: card, onMove: { newPile in
                                    moveCard(card, to: newPile)
                                })
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .onAppear { loadCards() }
        .sheet(isPresented: $showCreateCard) {
            CreateCardSheet(
                isPresented: $showCreateCard,
                sessionId: sessionId,
                onCreate: { content in
                    createCard(content: content)
                }
            )
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

    private func createCard(content: String) {
        _ = DatabaseManager.shared.createCard(
            sessionId: sessionId,
            content: content,
            pile: CardPile.inbox.rawValue
        )
        loadCards()
    }

    private func moveCard(_ card: CardModel, to pile: CardPile) {
        DatabaseManager.shared.moveCard(cardId: card.id, toPile: pile.rawValue)
        loadCards()
    }
}

// MARK: - Card Grid Item

struct CardGridItem: View {
    let card: CardModel
    let onMove: (CardPile) -> Void

    @State private var isHovering = false

    var isPrivate: Bool {
        card.isPrivate || card.pile == CardPile.vault.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with lock button
            HStack {
                Spacer()

                // Lock toggle button - always visible
                Button(action: {
                    if isPrivate {
                        onMove(.inbox)  // Make public
                    } else {
                        onMove(.vault)  // Make private
                    }
                }) {
                    Image(systemName: isPrivate ? "lock.fill" : "lock.open")
                        .font(.system(size: 11))
                        .foregroundColor(isPrivate ? .red : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(isPrivate ? "Private - click to make normal" : "Normal - click to make private")
            }

            // Content
            Text(card.content)
                .font(.system(size: 13))
                .lineLimit(5)

            Spacer()

            // Footer
            HStack {
                if card.sessionId != nil {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(formatDate(card.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(height: 150)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPrivate ? Color.red.opacity(0.5) : card.pileEnum.color.opacity(0.3), lineWidth: isPrivate ? 2 : 1)
        )
        .onHover { isHovering = $0 }
        .contextMenu {
            if card.pile != CardPile.vault.rawValue {
                Button(action: { onMove(.vault) }) {
                    Label("Mark Private (Vault)", systemImage: "lock.fill")
                }
            } else {
                Button(action: { onMove(.inbox) }) {
                    Label("Make Public (Inbox)", systemImage: "globe")
                }
            }

            Divider()

            ForEach(CardPile.allCases, id: \.self) { pile in
                if pile.rawValue != card.pile && pile != .vault {
                    Button(action: { onMove(pile) }) {
                        Label("Move to \(pile.displayName)", systemImage: pileIcon(pile))
                    }
                }
            }

            Divider()

            Button(role: .destructive, action: { onMove(.kill) }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func formatDate(_ timestamp: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private func pileIcon(_ pile: CardPile) -> String {
        switch pile {
        case .inbox: return "tray"
        case .vault: return "lock.fill"
        case .shaping: return "hammer"
        case .active: return "bolt"
        case .shipped: return "checkmark.circle"
        case .hold: return "pause.circle"
        case .kill: return "trash"
        }
    }
}
