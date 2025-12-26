import SwiftUI

// MARK: - Version Browser View

struct VersionBrowser: View {
    let sessionId: String
    let onRestore: (String) -> Void
    let onClose: () -> Void

    @State private var versions: [TranscriptVersion] = []
    @State private var selectedVersion: TranscriptVersion?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("VERSION HISTORY")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onClose) {
                    Text("Close")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08))
                .cornerRadius(4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Version list
            if versions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No version history")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Edits will be saved as versions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(versions) { version in
                            VersionCard(
                                version: version,
                                isSelected: selectedVersion?.id == version.id,
                                onSelect: { selectedVersion = version },
                                onRestore: {
                                    DatabaseManager.shared.restoreVersion(
                                        sessionId: sessionId,
                                        versionNum: version.versionNum
                                    )
                                    onRestore(version.content)
                                    loadVersions() // Refresh to show new restored version
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadVersions()
        }
    }

    private func loadVersions() {
        let rawVersions = DatabaseManager.shared.getVersions(sessionId: sessionId)
        versions = rawVersions.map { version in
            TranscriptVersion(
                id: "\(sessionId)-v\(version.versionNum)",
                versionNum: version.versionNum,
                versionType: version.versionType,
                content: version.content,
                createdAt: version.createdAt
            )
        }
    }
}

// MARK: - Version Card

struct VersionCard: View {
    let version: TranscriptVersion
    let isSelected: Bool
    let onSelect: () -> Void
    let onRestore: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                // Version badge
                Text("v\(version.versionNum)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)

                // Type badge
                Text(version.versionType)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(typeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.15))
                    .cornerRadius(3)

                // Relative timestamp
                Text(version.relativeTime)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                // Restore button
                Button(action: onRestore) {
                    Text("Restore")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(isHovering ? 0.2 : 0.1))
                .cornerRadius(4)
            }

            // Content preview
            Text(version.preview)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Character count indicator
            if version.content.count > 0 {
                Text("\(version.content.count) characters")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var typeColor: Color {
        switch version.versionType.lowercased() {
        case "raw":
            return .gray
        case "edited":
            return .blue
        case "polished":
            return .purple
        case "restored":
            return .orange
        default:
            return .secondary
        }
    }
}

// MARK: - Transcript Version Model

struct TranscriptVersion: Identifiable {
    let id: String
    let versionNum: Int
    let versionType: String
    let content: String
    let createdAt: Int

    var preview: String {
        let cleaned = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count <= 100 {
            return "\"\(cleaned)\""
        }
        return "\"\(String(cleaned.prefix(100)))...\""
    }

    var relativeTime: String {
        let now = Int(Date().timeIntervalSince1970)
        let diff = now - createdAt

        if diff < 60 {
            return "just now"
        } else if diff < 3600 {
            let mins = diff / 60
            return "\(mins) min\(mins == 1 ? "" : "s") ago"
        } else if diff < 86400 {
            let hours = diff / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if diff < 604800 {
            let days = diff / 86400
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAt)))
        }
    }
}

// MARK: - Preview
// #Preview macros require Xcode - commented out for SPM builds
// #Preview {
//     VersionBrowser(
//         sessionId: "test-session",
//         onRestore: { _ in },
//         onClose: {}
//     )
//     .frame(width: 500, height: 450)
// }
