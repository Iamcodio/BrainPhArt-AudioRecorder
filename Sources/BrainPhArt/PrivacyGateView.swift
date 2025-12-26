import SwiftUI

/// User-controlled privacy gate with transparent toggles.
/// Shows all flagged content with explicit Private/Public toggles.
/// No hidden magic - the user controls everything.
struct PrivacyGateView: View {
    let sessionId: String
    @Binding var isPresented: Bool
    @State private var privacyItems: [PrivacyItem] = []
    @State private var sessionLevel: String = "public"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Privacy Gate")
                    .font(.headline)

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Session-level privacy toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session Privacy Level")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Controls whether this session can be published or use external APIs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("", selection: $sessionLevel) {
                    Text("Public").tag("public")
                    Text("Private").tag("private")
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .onChange(of: sessionLevel) { newValue in
                    DatabaseManager.shared.setSessionPrivacyLevel(sessionId: sessionId, level: newValue)
                }
            }
            .padding()
            .background(sessionLevel == "private"
                ? Color.red.opacity(0.1)
                : Color.green.opacity(0.1))

            Divider()

            // Info banner
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("Toggle items below to mark content as private (local only) or public (can be shared)")
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.05))

            // Privacy items list
            if privacyItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("No items flagged")
                        .font(.headline)
                    Text("Auto-detection found nothing. You can manually mark text as private by selecting it in the editor.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach($privacyItems) { $item in
                        PrivacyItemRow(item: $item, onStatusChange: { newStatus in
                            updateItemStatus(item: item, newStatus: newStatus)
                        })
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            // Footer with stats
            HStack {
                let privateCount = privacyItems.filter { $0.status == "private" }.count
                let publicCount = privacyItems.filter { $0.status == "safe" || $0.status == "public" }.count
                let unreviewedCount = privacyItems.filter { $0.status == "unreviewed" }.count

                if unreviewedCount > 0 {
                    Label("\(unreviewedCount) unreviewed", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                if privateCount > 0 {
                    Label("\(privateCount) private", systemImage: "lock.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                if publicCount > 0 {
                    Label("\(publicCount) public", systemImage: "globe")
                        .foregroundColor(.green)
                        .font(.caption)
                }

                Spacer()

                // Can publish indicator
                if unreviewedCount == 0 && sessionLevel == "public" {
                    Label("Ready to publish", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else if sessionLevel == "private" {
                    Label("Session is private", systemImage: "lock.shield")
                        .foregroundColor(.orange)
                        .font(.caption)
                } else {
                    Label("Review items first", systemImage: "hand.raised")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 500, height: 450)
        .onAppear {
            loadPrivacyItems()
            loadSessionLevel()
        }
    }

    private func loadPrivacyItems() {
        let tags = DatabaseManager.shared.getPrivacyTags(sessionId: sessionId)
        let transcript = DatabaseManager.shared.getTranscript(sessionId: sessionId)

        privacyItems = tags.map { tag in
            // Extract the matched text from transcript
            let matchedText: String
            if tag.startOffset >= 0 && tag.endOffset <= transcript.count {
                let startIndex = transcript.index(transcript.startIndex, offsetBy: tag.startOffset, limitedBy: transcript.endIndex) ?? transcript.startIndex
                let endIndex = transcript.index(transcript.startIndex, offsetBy: min(tag.endOffset, transcript.count), limitedBy: transcript.endIndex) ?? transcript.endIndex
                matchedText = String(transcript[startIndex..<endIndex])
            } else {
                matchedText = "[offset out of range]"
            }

            return PrivacyItem(
                id: tag.id,
                matchedText: matchedText,
                tagType: tag.tagType,
                status: tag.status,
                startOffset: tag.startOffset,
                endOffset: tag.endOffset
            )
        }
    }

    private func loadSessionLevel() {
        let sessions = DatabaseManager.shared.getAllSessions()
        if let session = sessions.first(where: { $0.id == sessionId }) {
            sessionLevel = session.privacyLevel
        }
    }

    private func updateItemStatus(item: PrivacyItem, newStatus: String) {
        DatabaseManager.shared.updatePrivacyTagStatus(tagId: item.id, status: newStatus)
        loadPrivacyItems()  // Refresh
    }
}

// MARK: - Privacy Item Model

struct PrivacyItem: Identifiable {
    let id: String
    let matchedText: String
    let tagType: String
    var status: String
    let startOffset: Int
    let endOffset: Int
}

// MARK: - Privacy Item Row

struct PrivacyItemRow: View {
    @Binding var item: PrivacyItem
    let onStatusChange: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                // Matched text (with some masking for display)
                Text(displayText)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(2)

                // Tag type
                Text(item.tagType)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }

            Spacer()

            // Toggle buttons - explicit and transparent
            HStack(spacing: 4) {
                Button(action: { onStatusChange("private") }) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("Private")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(item.status == "private" ? Color.red.opacity(0.2) : Color.clear)
                    .foregroundColor(item.status == "private" ? .red : .secondary)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(item.status == "private" ? Color.red : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button(action: { onStatusChange("safe") }) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text("Public")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(item.status == "safe" ? Color.green.opacity(0.2) : Color.clear)
                    .foregroundColor(item.status == "safe" ? .green : .secondary)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(item.status == "safe" ? Color.green : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            item.status == "unreviewed"
                ? Color.orange.opacity(0.05)
                : Color.clear
        )
        .cornerRadius(6)
    }

    private var statusColor: Color {
        switch item.status {
        case "private":
            return .red
        case "safe", "public":
            return .green
        case "unreviewed":
            return .orange
        default:
            return .gray
        }
    }

    private var displayText: String {
        // Show actual text - transparency is key
        // User decides what's private, not us hiding it
        return item.matchedText
    }
}

// MARK: - Privacy Gate Button (for toolbar)

struct PrivacyGateButton: View {
    let unreviewedCount: Int
    let sessionId: String
    @State private var showPrivacyGate = false

    var body: some View {
        Button(action: { showPrivacyGate = true }) {
            HStack(spacing: 4) {
                Image(systemName: unreviewedCount > 0 ? "exclamationmark.shield.fill" : "shield.checkered")
                    .foregroundColor(unreviewedCount > 0 ? .orange : .secondary)
                Text("Privacy")
                    .font(.system(size: 11))
                if unreviewedCount > 0 {
                    Text("\(unreviewedCount)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPrivacyGate) {
            PrivacyGateView(sessionId: sessionId, isPresented: $showPrivacyGate)
        }
    }
}
