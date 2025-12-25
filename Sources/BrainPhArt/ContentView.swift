import SwiftUI
import AVFoundation
import AppKit

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var recordingState: RecordingState = .idle
    @State private var recordings: [RecordingItem] = []
    @State private var selectedRecording: RecordingItem?
    @State private var editedTranscript: String = ""
    @State private var showPreview: Bool = true
    @State private var isFloatingMode: Bool = false
    @State private var showSettings: Bool = false
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false

    // Auto-refresh timer for transcript updates
    let transcriptRefreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if isFloatingMode {
                FloatingRecorderView(
                    audioRecorder: audioRecorder,
                    recordingState: $recordingState,
                    isFloatingMode: $isFloatingMode,
                    onStartStop: handleStartStop
                )
            } else {
                MainView(
                    audioRecorder: audioRecorder,
                    recordingState: $recordingState,
                    recordings: $recordings,
                    selectedRecording: $selectedRecording,
                    editedTranscript: $editedTranscript,
                    showPreview: $showPreview,
                    isFloatingMode: $isFloatingMode,
                    showSettings: $showSettings,
                    onStartStop: handleStartStop,
                    onCancel: handleCancel,
                    onSelect: selectRecording,
                    onSave: saveTranscript,
                    onRefresh: loadRecordings
                )
            }
        }
        .onAppear {
            loadRecordings()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings)
        }
        .alert("BrainPhArt", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        // Auto-refresh transcript every 2 seconds
        .onReceive(transcriptRefreshTimer) { _ in
            refreshSelectedTranscript()
        }
        // Global hotkey: Cmd+Shift+R toggles floating mode
        .keyboardShortcut("r", modifiers: [.command, .shift])
    }

    private func refreshSelectedTranscript() {
        guard let selected = selectedRecording else { return }

        // Get latest transcript from DB
        let latestTranscript = DatabaseManager.shared.getTranscript(sessionId: selected.id)

        // Only update if transcript changed and user hasn't edited it
        if latestTranscript != selected.transcript && !latestTranscript.isEmpty {
            // Update the recording item
            if let index = recordings.firstIndex(where: { $0.id == selected.id }) {
                recordings[index] = RecordingItem(
                    id: selected.id,
                    createdAt: selected.createdAt,
                    transcript: latestTranscript,
                    status: selected.status
                )
                selectedRecording = recordings[index]
                editedTranscript = latestTranscript
                print("📝 Transcript updated: \(latestTranscript.prefix(50))...")
            }
        }
    }

    private func handleStartStop() {
        if recordingState == .idle {
            let sessionId = UUID().uuidString

            print("🔴 ========== RECORDING STARTED ==========")
            print("🔴 Session ID: \(sessionId)")

            DatabaseManager.shared.createSession(id: sessionId)
            recordingState = .recording

            alertMessage = "Recording Started!"
            showAlert = true

            Task {
                await audioRecorder.startRecording(sessionId: sessionId)
            }
        } else {
            print("⏹️ ========== RECORDING STOPPED ==========")

            audioRecorder.stopRecording()
            recordingState = .idle

            print("💾 ========== AUDIO SAVED TO DATABASE ==========")

            alertMessage = "Recording Stopped - Audio Saved to Database!"
            showAlert = true

            loadRecordings()

            // Select the newly created recording (first in list since sorted by date DESC)
            if let newRecording = recordings.first {
                selectRecording(newRecording)
            }
        }
    }

    private func handleCancel() {
        print("❌ ========== RECORDING CANCELLED ==========")

        audioRecorder.cancelRecording()
        recordingState = .idle

        alertMessage = "Recording Cancelled"
        showAlert = true

        loadRecordings()
    }

    private func loadRecordings() {
        let sessions = DatabaseManager.shared.getAllSessions()
        debugLog("📋 Loading \(sessions.count) sessions")
        recordings = sessions.map { session in
            let transcript = DatabaseManager.shared.getTranscript(sessionId: session.id)
            debugLog("📝 Session \(session.id.prefix(8)): transcript length = \(transcript.count)")
            return RecordingItem(
                id: session.id,
                createdAt: session.createdAt,
                transcript: transcript,
                status: session.status
            )
        }
        // Auto-select first if none selected
        if selectedRecording == nil, let first = recordings.first {
            selectRecording(first)
        }
    }

    private func debugLog(_ message: String) {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("brainphart/debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath.path) {
                if let handle = try? FileHandle(forWritingTo: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logPath)
            }
        }
    }

    private func selectRecording(_ recording: RecordingItem) {
        debugLog("🔍 selectRecording: id=\(recording.id.prefix(8)) transcript.count=\(recording.transcript.count)")
        debugLog("🔍 Transcript preview: \(recording.transcript.prefix(100))")
        selectedRecording = recording
        editedTranscript = recording.transcript
        debugLog("🔍 editedTranscript set to: \(editedTranscript.prefix(100))")
    }

    private func saveTranscript() {
        guard let selected = selectedRecording else { return }
        DatabaseManager.shared.updateFullTranscript(sessionId: selected.id, transcript: editedTranscript)
        loadRecordings()
        if let updated = recordings.first(where: { $0.id == selected.id }) {
            selectedRecording = updated
            editedTranscript = updated.transcript
        }
    }
}

// MARK: - Main View (Full Window)

struct MainView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var recordingState: RecordingState
    @Binding var recordings: [RecordingItem]
    @Binding var selectedRecording: RecordingItem?
    @Binding var editedTranscript: String
    @Binding var showPreview: Bool
    @Binding var isFloatingMode: Bool
    @Binding var showSettings: Bool
    let onStartStop: () -> Void
    let onCancel: () -> Void
    let onSelect: (RecordingItem) -> Void
    let onSave: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            TopBar(showSettings: $showSettings, isFloatingMode: $isFloatingMode)

            Divider()

            // Main content area
            HSplitView {
                // Left: History Panel
                HistoryPanel(
                    recordings: recordings,
                    selectedId: selectedRecording?.id,
                    onSelect: onSelect,
                    onRefresh: onRefresh
                )
                .frame(minWidth: 280, maxWidth: 350)

                // Right: Editor
                if let selected = selectedRecording {
                    EditorView(
                        recording: selected,
                        transcript: $editedTranscript,
                        showPreview: $showPreview,
                        onSave: onSave
                    )
                    .id(selected.id)
                } else {
                    EmptyEditorView()
                }
            }

            Divider()

            // Bottom: Recorder Module (standalone)
            RecorderModule(
                audioRecorder: audioRecorder,
                recordingState: $recordingState,
                onRecord: onStartStop,
                onStop: onStartStop,
                onCancel: onCancel
            )

            Divider()

            // Bottom: Playback Module
            PlaybackModule(selectedRecording: selectedRecording)
        }
        .frame(minWidth: 1000, minHeight: 700)
    }
}

// MARK: - Top Bar

struct TopBar: View {
    @Binding var showSettings: Bool
    @Binding var isFloatingMode: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Settings button
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Settings")

            // Folder button
            Button(action: openAudioFolder) {
                Image(systemName: "folder")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Open Audio Folder")

            // Help button
            Button(action: {}) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Help")

            Spacer()

            Text("BrainPhArt")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            // Float mode button
            Button(action: { isFloatingMode = true }) {
                Image(systemName: "pip.enter")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Float Mode")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func openAudioFolder() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("brainphart/audio")
        NSWorkspace.shared.open(path)
    }
}

// MARK: - Recorder Module (Standalone)

struct RecorderModule: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var recordingState: RecordingState
    let onRecord: () -> Void
    let onStop: () -> Void
    let onCancel: () -> Void

    @State private var showFinalTime: Bool = false
    @State private var finalDuration: TimeInterval = 0

    var body: some View {
        HStack(spacing: 16) {
            // REC Button
            Button(action: onRecord) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(recordingState == .idle ? Color.primary : Color.primary.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text("REC")
                        .fontWeight(.medium)
                        .font(.system(size: 12, design: .default))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(recordingState == .idle ? 0.08 : 0.04))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .disabled(recordingState == .recording)

            // Timer
            Text(timerText)
                .font(.system(size: 20, weight: .regular, design: .monospaced))
                .foregroundColor(timerColor)
                .frame(width: 70)

            // STOP Button
            Button(action: {
                if recordingState == .recording {
                    finalDuration = audioRecorder.recordingDuration
                    onStop()
                    showFinalTime = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showFinalTime = false
                    }
                }
            }) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(recordingState == .recording ? Color.primary : Color.primary.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text("STOP")
                        .fontWeight(.medium)
                        .font(.system(size: 12, design: .default))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(recordingState == .recording ? 0.08 : 0.04))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .disabled(recordingState != .recording)

            // CANCEL Button (only visible during recording)
            if recordingState == .recording {
                Button(action: onCancel) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                        Text("CANCEL")
                            .fontWeight(.medium)
                            .font(.system(size: 12, design: .default))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }

            // Waveform - full width
            RecorderWaveform(audioRecorder: audioRecorder, isRecording: recordingState == .recording)
                .frame(maxWidth: .infinity, maxHeight: 32)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var timerText: String {
        if showFinalTime {
            return formatDuration(finalDuration)
        }
        return formatDuration(audioRecorder.recordingDuration)
    }

    private var timerColor: Color {
        if showFinalTime {
            return .primary
        }
        if recordingState == .recording {
            return .primary
        }
        return .secondary
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Recorder Waveform (full width, thin bars, energetic)

struct RecorderWaveform: View {
    @ObservedObject var audioRecorder: AudioRecorder
    let isRecording: Bool

    private let barCount = 80
    @State private var levelHistory: [Float] = Array(repeating: 0, count: 80)

    let timer = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(isRecording ? Color.primary.opacity(0.7) : Color.primary.opacity(0.2))
                        .frame(width: max(1, (geo.size.width - CGFloat(barCount - 1)) / CGFloat(barCount)),
                               height: max(2, CGFloat(levelHistory[index]) * geo.size.height))
                }
            }
        }
        .onReceive(timer) { _ in
            if isRecording {
                levelHistory.removeFirst()
                let level = audioRecorder.audioLevel * 1.8 + Float.random(in: 0...0.06)
                levelHistory.append(min(1.0, level))
            }
        }
        .onChange(of: isRecording) { recording in
            if !recording {
                levelHistory = Array(repeating: 0, count: barCount)
            }
        }
    }
}

// MARK: - Record Control Panel (with live waveform)

struct RecordControlPanel: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var recordingState: RecordingState
    @Binding var isFloatingMode: Bool
    let onStartStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // Record/Stop button
                Button(action: onStartStop) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(recordingState == .idle ? Color.red : Color.gray)
                            .frame(width: 14, height: 14)

                        Text(recordingState == .idle ? "RECORD" : "STOP")
                            .fontWeight(.semibold)
                            .font(.system(size: 13))

                        if recordingState == .recording {
                            Text(formatDuration(audioRecorder.recordingDuration))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(recordingState == .idle ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Spacer()

                // Float button
                Button(action: { isFloatingMode = true }) {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Float (Cmd+Shift+R)")
            }

            // Live waveform
            LiveWaveformView(audioRecorder: audioRecorder, isRecording: recordingState == .recording)
                .frame(height: 30)
        }
        .padding()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Live Waveform View

struct LiveWaveformView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    let isRecording: Bool

    @State private var levelHistory: [Float] = Array(repeating: 0, count: 30)

    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<levelHistory.count, id: \.self) { index in
                Rectangle()
                    .fill(isRecording ? Color.red.opacity(0.7) : Color.gray.opacity(0.3))
                    .frame(width: 4, height: max(2, CGFloat(levelHistory[index]) * 28))
                    .cornerRadius(1)
            }
        }
        .frame(maxWidth: .infinity)
        .onReceive(timer) { _ in
            if isRecording {
                levelHistory.removeFirst()
                levelHistory.append(audioRecorder.audioLevel)
            }
        }
        .onChange(of: isRecording) { recording in
            if !recording {
                levelHistory = Array(repeating: 0, count: 30)
            }
        }
    }
}

// MARK: - Floating Recorder View

struct FloatingRecorderView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var recordingState: RecordingState
    @Binding var isFloatingMode: Bool
    let onStartStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("BrainPhArt")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { isFloatingMode = false }) {
                    Image(systemName: "pip.exit")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                // Record/Stop
                Button(action: onStartStop) {
                    Circle()
                        .fill(recordingState == .idle ? Color.red : Color.gray)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: recordingState == .idle ? "mic.fill" : "stop.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 16))
                        )
                }
                .buttonStyle(.plain)

                // Live waveform
                LiveWaveformView(audioRecorder: audioRecorder, isRecording: recordingState == .recording)
                    .frame(width: 120, height: 24)

                // Cancel (if recording)
                if recordingState == .recording {
                    Button(action: onStartStop) {
                        Text("Stop")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(width: 280, height: 100)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Recording Item Model

struct RecordingItem: Identifiable, Equatable {
    let id: String
    let createdAt: Int
    let transcript: String
    let status: String

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAt)))
    }

    var title: String {
        if transcript.isEmpty {
            return "Recording \(dateString)"
        }
        let preview = transcript.prefix(40).replacingOccurrences(of: "\n", with: " ")
        return String(preview) + (transcript.count > 40 ? "..." : "")
    }
}

// MARK: - History Panel

struct HistoryPanel: View {
    let recordings: [RecordingItem]
    let selectedId: String?
    let onSelect: (RecordingItem) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HISTORY")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if recordings.isEmpty {
                Spacer()
                Text("No recordings yet")
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(recordings) { recording in
                            HistoryCard(
                                recording: recording,
                                isSelected: recording.id == selectedId,
                                onSelect: { onSelect(recording) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - History Card (with playback)

struct HistoryCard: View {
    let recording: RecordingItem
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(recording.dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Play button
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(isPlaying ? .red : .blue)
                }
                .buttonStyle(.plain)

                if recording.status == "recording" {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
            }

            Text(recording.title)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundColor(.primary)
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private func togglePlayback() {
        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
        } else {
            playRecording()
        }
    }

    private func playRecording() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(recording.createdAt)))

        let audioDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("brainphart/audio/\(dateString)")

        let chunkPath = audioDir.appendingPathComponent("session_\(recording.id)_chunk_0.wav")

        guard FileManager.default.fileExists(atPath: chunkPath.path) else {
            print("No audio file for this recording")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: chunkPath)
            audioPlayer?.play()
            isPlaying = true
        } catch {
            print("Playback error: \(error)")
        }
    }
}

// MARK: - Editor View

struct EditorView: View {
    let recording: RecordingItem
    @Binding var transcript: String
    @Binding var showPreview: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(recording.dateString)
                    .font(.headline)
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

            // Simple text canvas
            TextEditor(text: $transcript)
                .font(.system(.body, design: .default))
                .padding(12)
                .id(recording.id)
        }
    }
}

// MARK: - Editor Toolbar

struct EditorToolbar: View {
    let recording: RecordingItem
    @Binding var showPreview: Bool
    let onSave: () -> Void

    var body: some View {
        HStack {
            Text(recording.dateString)
                .font(.headline)

            Spacer()

            // Split toggle
            Button(action: { showPreview.toggle() }) {
                Image(systemName: showPreview ? "rectangle.split.2x1.fill" : "rectangle")
            }
            .help(showPreview ? "Hide Preview" : "Show Preview")

            Divider().frame(height: 20)

            // Save button
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
    }
}

// MARK: - Markdown Editor

struct MarkdownEditor: View {
    @Binding var text: String
    let recordingId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("EDIT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .id(recordingId)  // Force TextEditor refresh on recording change
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Markdown Preview

struct MarkdownPreview: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PREVIEW")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView {
                Text(attributedMarkdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var attributedMarkdown: AttributedString {
        do {
            return try AttributedString(markdown: text)
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Empty Editor View

struct EmptyEditorView: View {
    var body: some View {
        VStack {
            Spacer()

            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Select a recording to edit")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.top)

            Text("Or press Record to create a new one")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Supporting Types

enum RecordingState {
    case idle
    case recording
}

struct Recording: Identifiable {
    let id: String
    let createdAt: Int
    let completedAt: Int?
    let status: String
    let chunkCount: Int
}
