import SwiftUI
import AppKit

/// Writer Module - Distraction-free writing (Hemingway Write mode)
/// Can be used standalone or integrated into the main app.
/// No spell check, no highlighting - pure stream of consciousness.

// MARK: - Writer View (Standalone)

struct WriterView: View {
    @Binding var text: String
    var onSave: (() -> Void)?

    @State private var wordCount: Int = 0
    @State private var isFullscreen = false

    var body: some View {
        VStack(spacing: 0) {
            // Pure text area - distraction-free
            ZStack {
                Color(NSColor.textBackgroundColor)

                TextEditor(text: $text)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .scrollContentBackground(.hidden)
                    .padding(40)
            }

            // Minimal footer - just word count and save
            HStack {
                Text("Words: \(wordCount)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                if let save = onSave {
                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onChange(of: text) { newValue in
            wordCount = countWords(newValue)
        }
        .onAppear {
            wordCount = countWords(text)
        }
    }

    private func countWords(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

// MARK: - Writer Tab View (For use in tabbed app)

struct WriteTabView: View {
    @Binding var transcript: String
    let selectedRecording: RecordingItem?
    let onSave: () -> Void

    var body: some View {
        WriterView(
            text: $transcript,
            onSave: onSave
        )
        .id(selectedRecording?.id ?? "empty")
    }
}

// MARK: - Standalone Writer Window

struct StandaloneWriterView: View {
    @State private var text: String = ""
    @State private var documentURL: URL?

    var body: some View {
        WriterView(text: $text, onSave: saveDocument)
            .frame(minWidth: 600, minHeight: 400)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: newDocument) {
                        Image(systemName: "doc.badge.plus")
                    }
                    .help("New Document")
                }

                ToolbarItem(placement: .automatic) {
                    Button(action: openDocument) {
                        Image(systemName: "folder")
                    }
                    .help("Open Document")
                }
            }
    }

    private func newDocument() {
        text = ""
        documentURL = nil
    }

    private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                text = try String(contentsOf: url, encoding: .utf8)
                documentURL = url
            } catch {
                print("Failed to open document: \(error)")
            }
        }
    }

    private func saveDocument() {
        if let url = documentURL {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to save document: \(error)")
            }
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "Untitled.txt"

            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    documentURL = url
                } catch {
                    print("Failed to save document: \(error)")
                }
            }
        }
    }
}
