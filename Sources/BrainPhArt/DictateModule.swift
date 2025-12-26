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

                    // Transcript (read-only in DICTATE mode)
                    ScrollView {
                        Text(editedTranscript.isEmpty ? "Start recording to see transcript here..." : editedTranscript)
                            .font(.system(size: 16))
                            .foregroundColor(editedTranscript.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .textSelection(.enabled)
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
