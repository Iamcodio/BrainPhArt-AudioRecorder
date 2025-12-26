import SwiftUI
import AVFoundation
import AppKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var audioRecorder = AudioRecorder()
    @State private var recordingState: RecordingState = .idle
    @State private var recordings: [RecordingItem] = []
    @State private var selectedRecording: RecordingItem?
    @State private var editedTranscript: String = ""
    @State private var showPreview: Bool = true
    @State private var showSettings: Bool = false
    @State private var unreviewedPIICount: Int = 0

    // Auto-refresh timer for transcript updates
    let transcriptRefreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    // Global hotkey notifications
    let toggleRecordingPublisher = NotificationCenter.default.publisher(for: .toggleRecording)
    let cancelRecordingPublisher = NotificationCenter.default.publisher(for: .cancelRecording)
    let openSettingsPublisher = NotificationCenter.default.publisher(for: .openSettings)

    var body: some View {
        Group {
            switch appState.windowMode {
            case .micro:
                UltraCompactRecorderView(
                    audioRecorder: audioRecorder,
                    recordingState: $recordingState,
                    onStartStop: handleStartStop,
                    onCancel: handleCancel
                )
                .padding(8)

            case .medium:
                FloatingRecorderView(
                    audioRecorder: audioRecorder,
                    recordingState: $recordingState,
                    isFloatingMode: .constant(true),
                    onStartStop: handleStartStop,
                    onCancel: handleCancel
                )

            case .full:
                MainView(
                    audioRecorder: audioRecorder,
                    recordingState: $recordingState,
                    recordings: $recordings,
                    selectedRecording: $selectedRecording,
                    editedTranscript: $editedTranscript,
                    showPreview: $showPreview,
                    isFloatingMode: $appState.isFloatingMode,
                    showSettings: $showSettings,
                    unreviewedPIICount: unreviewedPIICount,
                    onStartStop: handleStartStop,
                    onCancel: handleCancel,
                    onSelect: selectRecording,
                    onSave: saveTranscript,
                    onRefresh: loadRecordings,
                    onDelete: handleDelete,
                    onRetryTranscription: handleRetryTranscription
                )
            }
        }
        .onAppear {
            loadRecordings()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings)
        }
        // Auto-refresh transcript every 2 seconds
        .onReceive(transcriptRefreshTimer) { _ in
            refreshSelectedTranscript()
        }
        // Global hotkey: Toggle recording
        .onReceive(toggleRecordingPublisher) { _ in
            handleStartStop()
        }
        // Global hotkey: Cancel recording
        .onReceive(cancelRecordingPublisher) { _ in
            if recordingState == .recording {
                handleCancel()
            }
        }
        .onReceive(openSettingsPublisher) { _ in
            showSettings = true
        }
    }

    private func refreshSelectedTranscript() {
        guard let selected = selectedRecording else { return }

        // Get latest transcript from DB
        let latestTranscript = DatabaseManager.shared.getTranscript(sessionId: selected.id)
        let progress = DatabaseManager.shared.getTranscriptionProgress(sessionId: selected.id)
        let chunkPaths = DatabaseManager.shared.getChunkPaths(sessionId: selected.id)

        // Only update if transcript changed and user hasn't edited it
        if latestTranscript != selected.transcript && !latestTranscript.isEmpty {
            // Update the recording item
            if let index = recordings.firstIndex(where: { $0.id == selected.id }) {
                recordings[index] = RecordingItem(
                    id: selected.id,
                    createdAt: selected.createdAt,
                    transcript: latestTranscript,
                    status: selected.status,
                    transcriptionProgress: progress,
                    hasAudioChunks: !chunkPaths.isEmpty
                )
                selectedRecording = recordings[index]
                editedTranscript = latestTranscript
                print("📝 Transcript updated: \(latestTranscript.prefix(50))...")

                // Auto-copy to clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(latestTranscript, forType: .string)
                print("📋 Auto-copied to clipboard!")

                // Auto-paste into focused text field (after small delay for clipboard)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    simulatePaste()
                }

                // Scan for PII after transcription completes
                scanTranscriptForPII(sessionId: selected.id, transcript: latestTranscript)
            }
        }
    }

    /// Scans transcript for PII and saves tags to database
    private func scanTranscriptForPII(sessionId: String, transcript: String) {
        print("🔍 scanTranscriptForPII called for session \(sessionId.prefix(8)), transcript length: \(transcript.count)")

        // Skip if transcript is empty
        guard !transcript.isEmpty else {
            unreviewedPIICount = 0
            print("🔍 Skipping - empty transcript")
            return
        }

        // Check if tags already exist for this session (avoid duplicates)
        let existingTags = DatabaseManager.shared.getPrivacyTags(sessionId: sessionId)
        if !existingTags.isEmpty {
            // Just update the count
            unreviewedPIICount = DatabaseManager.shared.getUnreviewedCount(sessionId: sessionId)
            print("🔍 Tags already exist: \(existingTags.count), unreviewed: \(unreviewedPIICount)")
            return
        }

        // Scan for PII matches (regex + topic keywords)
        let matches = PrivacyScanner.fullScan(transcript)
        print("🔍 Scanner found \(matches.count) matches (regex + topics)")

        // Save each match as a privacy tag
        for match in matches {
            DatabaseManager.shared.savePrivacyTag(
                sessionId: sessionId,
                startOffset: match.startOffset,
                endOffset: match.endOffset,
                tagType: match.patternName
            )
        }

        // Update the unreviewed count
        unreviewedPIICount = DatabaseManager.shared.getUnreviewedCount(sessionId: sessionId)

        if matches.count > 0 {
            print("🔒 Found \(matches.count) PII matches in transcript")
        }
    }

    private func handleStartStop() {
        if recordingState == .idle {
            let sessionId = UUID().uuidString

            print("🔴 ========== RECORDING STARTED ==========")
            print("🔴 Session ID: \(sessionId)")

            DatabaseManager.shared.createSession(id: sessionId)
            recordingState = .recording

            Task {
                await audioRecorder.startRecording(sessionId: sessionId)
            }
        } else {
            print("⏹️ ========== RECORDING STOPPED ==========")

            audioRecorder.stopRecording()
            recordingState = .idle

            print("💾 ========== AUDIO SAVED TO DATABASE ==========")

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

        loadRecordings()
    }

    private func loadRecordings() {
        let sessions = DatabaseManager.shared.getAllSessions()
        debugLog("📋 Loading \(sessions.count) sessions")
        recordings = sessions.map { session in
            let transcript = DatabaseManager.shared.getTranscript(sessionId: session.id)
            let progress = DatabaseManager.shared.getTranscriptionProgress(sessionId: session.id)
            let chunkPaths = DatabaseManager.shared.getChunkPaths(sessionId: session.id)
            debugLog("📝 Session \(session.id.prefix(8)): transcript length = \(transcript.count)")
            return RecordingItem(
                id: session.id,
                createdAt: session.createdAt,
                transcript: transcript,
                status: session.status,
                transcriptionProgress: progress,
                hasAudioChunks: !chunkPaths.isEmpty
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

        // Scan for PII when loading transcript
        scanTranscriptForPII(sessionId: recording.id, transcript: recording.transcript)
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

    private func handleDelete(_ recording: RecordingItem) {
        // Clear selection if deleting selected item
        if selectedRecording?.id == recording.id {
            selectedRecording = nil
            editedTranscript = ""
        }

        DatabaseManager.shared.deleteSession(id: recording.id)
        loadRecordings()

        // Select first available if we deleted the selected one
        if selectedRecording == nil, let first = recordings.first {
            selectRecording(first)
        }
    }

    private func handleRetryTranscription(_ recording: RecordingItem) {
        DatabaseManager.shared.resetTranscriptionStatus(sessionId: recording.id)
        loadRecordings()

        // Update selection if this is the selected recording
        if let updated = recordings.first(where: { $0.id == recording.id }) {
            selectedRecording = updated
            editedTranscript = updated.transcript
        }
    }
}

// MARK: - Main View (Full Window with Tabs)

enum MainTab: String, CaseIterable {
    case dictate = "DICTATE"
    case write = "WRITE"
    case edit = "EDIT"
    case cards = "CARDS"

    var icon: String {
        switch self {
        case .dictate: return "mic.fill"
        case .write: return "pencil"
        case .edit: return "textformat"
        case .cards: return "rectangle.stack"
        }
    }
}

struct MainView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var recordingState: RecordingState
    @Binding var recordings: [RecordingItem]
    @Binding var selectedRecording: RecordingItem?
    @Binding var editedTranscript: String
    @Binding var showPreview: Bool
    @Binding var isFloatingMode: Bool
    @Binding var showSettings: Bool
    let unreviewedPIICount: Int
    let onStartStop: () -> Void
    let onCancel: () -> Void
    let onSelect: (RecordingItem) -> Void
    let onSave: () -> Void
    let onRefresh: () -> Void
    let onDelete: (RecordingItem) -> Void
    let onRetryTranscription: (RecordingItem) -> Void

    @State private var selectedTab: MainTab = .dictate

    var body: some View {
        VStack(spacing: 0) {
            // Minimal top bar - Hemingway style
            HStack(spacing: 0) {
                // Settings button (left)
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)

                Spacer()

                // Tab selector (center) - Hemingway Write/Edit style
                HStack(spacing: 0) {
                    ForEach(MainTab.allCases, id: \.self) { tab in
                        Button(action: { selectedTab = tab }) {
                            Text(tab.rawValue)
                                .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)

                Spacer()

                // Window controls (right)
                HStack(spacing: 12) {
                    Button(action: { AppState.shared.windowMode = .medium }) {
                        Image(systemName: "pip.swap")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Floating Recorder")

                    Button(action: { AppState.shared.windowMode = .micro }) {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Minimize to Pill")
                }
                .padding(.trailing, 16)
            }
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tab content
            switch selectedTab {
            case .dictate:
                DictateTabView(
                    audioRecorder: audioRecorder,
                    recordingState: $recordingState,
                    recordings: $recordings,
                    selectedRecording: $selectedRecording,
                    editedTranscript: $editedTranscript,
                    onStartStop: onStartStop,
                    onCancel: onCancel,
                    onSelect: onSelect,
                    onRefresh: onRefresh,
                    onDelete: onDelete,
                    onRetryTranscription: onRetryTranscription
                )

            case .write:
                WriteTabView(
                    transcript: $editedTranscript,
                    selectedRecording: selectedRecording,
                    onSave: onSave
                )

            case .edit:
                EditTabView(
                    transcript: $editedTranscript,
                    selectedRecording: selectedRecording,
                    unreviewedPIICount: unreviewedPIICount,
                    onSave: onSave
                )

            case .cards:
                CardsTabView(sessionId: selectedRecording?.id)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// Tab views are now in separate module files:
// - DictateModule.swift (DictateTabView)
// - WriterModule.swift (WriteTabView)
// - EditorModule.swift (EditTabView)
// - CardView.swift (CardsTabView)

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

            // Logo and title
            HStack(spacing: 8) {
                if let iconPath = Bundle.main.resourcePath.map({ $0 + "/AppIcon.icns" }),
                   let iconImage = NSImage(contentsOfFile: iconPath) {
                    Image(nsImage: iconImage)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text("BrainPhArt")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Medium mode button
            Button(action: { AppState.shared.windowMode = .medium }) {
                Image(systemName: "pip.swap")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Floating Recorder")

            // Micro mode button
            Button(action: { AppState.shared.windowMode = .micro }) {
                Image(systemName: "pip.enter")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Minimize to Pill")
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

            // Waveform - centerpiece
            RecorderWaveform(audioRecorder: audioRecorder, isRecording: recordingState == .recording)
                .frame(maxWidth: .infinity, maxHeight: 56)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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

// MARK: - Recorder Waveform (Smooth speech-paced frequency meter)

struct RecorderWaveform: View {
    @ObservedObject var audioRecorder: AudioRecorder
    let isRecording: Bool

    // Clean, readable bar count
    private let barCount = 40
    @State private var bandLevels: [Float] = Array(repeating: 0, count: 40)

    // Smoother updates - speech pace (~110 wpm feel)
    let timer = Timer.publish(every: 0.06, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Subtle glow when recording
                if isRecording {
                    Rectangle()
                        .fill(Color.white.opacity(0.02))
                        .blur(radius: 15)
                }

                // Clean thin white bars
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(
                                isRecording
                                    ? Color.white.opacity(0.85)
                                    : Color.white.opacity(0.1)
                            )
                            .frame(
                                width: 2,
                                height: max(2, CGFloat(bandLevels[index]) * geo.size.height * 0.85)
                            )
                            .shadow(color: isRecording ? .white.opacity(0.3) : .clear, radius: 1, x: 0, y: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .onReceive(timer) { _ in
            if isRecording {
                let baseLevel = audioRecorder.audioLevel

                for i in 0..<barCount {
                    // Frequency response - center bars boosted for voice
                    let centerDistance = abs(Float(i) - Float(barCount) / 2.0) / Float(barCount)
                    let voiceBoost = 1.0 - (centerDistance * 0.2)

                    // Punchy variation
                    let variation = Float.random(in: 0.25...1.9)

                    // More spikes, bigger pops
                    let spike: Float = Float.random(in: 0...1) < 0.2 ? Float.random(in: 1.4...2.2) : 1.0

                    // More jitter
                    let jitter = Float.random(in: -0.12...0.12)

                    // Snappy response
                    let targetLevel = baseLevel * voiceBoost * variation * spike + jitter
                    let smoothing: Float = 0.6  // Even snappier
                    bandLevels[i] = bandLevels[i] * (1 - smoothing) + targetLevel * smoothing

                    // Good visible minimum
                    if baseLevel > 0.01 {
                        bandLevels[i] = max(0.08, bandLevels[i])
                    }
                }
            }
        }
        .onChange(of: isRecording) { recording in
            if !recording {
                withAnimation(.easeOut(duration: 0.3)) {
                    bandLevels = Array(repeating: 0, count: barCount)
                }
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
                .help("Float (Ctrl+Shift+Space)")
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

// MARK: - Floating Recorder View (Compact SuperWhisper-style)

enum TranscriptionStatus {
    case idle
    case recording
    case processing
    case complete
}

struct FloatingRecorderView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var recordingState: RecordingState
    @Binding var isFloatingMode: Bool
    let onStartStop: () -> Void
    let onCancel: () -> Void

    @State private var transcriptionStatus: TranscriptionStatus = .idle
    @State private var lastSessionId: String = ""
    @State private var hideTimer: Timer?

    // Check for transcription completion
    let transcriptCheckTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            // Waveform - the star
            RecorderWaveform(audioRecorder: audioRecorder, isRecording: recordingState == .recording)
                .frame(height: 44)

            // Timer and controls
            HStack(spacing: 12) {
                // Fish logo
                if let iconPath = Bundle.main.resourcePath.map({ $0 + "/AppIcon.icns" }),
                   let iconImage = NSImage(contentsOfFile: iconPath) {
                    Image(nsImage: iconImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                // Record/Stop button
                Button(action: {
                    // Always allow start/stop regardless of status
                    if transcriptionStatus == .complete || transcriptionStatus == .processing {
                        transcriptionStatus = .idle
                        hideTimer?.invalidate()
                        hideTimer = nil
                    }
                    onStartStop()
                }) {
                    Circle()
                        .fill(recordingState == .recording ? Color.gray : Color.red)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: recordingState == .recording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        )
                }
                .buttonStyle(.plain)

                // Status display - simplified, always show key elements
                if recordingState == .recording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)

                    Text(formatDuration(audioRecorder.recordingDuration))
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)

                    // Cancel button during recording
                    Button(action: {
                        onCancel()
                        transcriptionStatus = .idle
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel (Esc)")
                } else if transcriptionStatus == .processing {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Transcribing...")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                } else if transcriptionStatus == .complete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Done!")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                } else {
                    Text("Ctrl+Shift+Space")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Always show expand button
                Button(action: { AppState.shared.windowMode = .full }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("Minimize") {
                AppState.shared.windowMode = .micro
            }
            Divider()
            Button("Open History") {
                AppState.shared.windowMode = .full
            }
            Button("Open Settings") {
                AppState.shared.windowMode = .full
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
            }
            Divider()
            Button("Hide") {
                NSApp.windows.first { $0 is FloatingPanel }?.orderOut(nil)
            }
            Button("Quit BrainPhArt") {
                NSApp.terminate(nil)
            }
        }
        .onChange(of: recordingState) { newState in
            if newState == .recording {
                transcriptionStatus = .recording
                hideTimer?.invalidate()
                hideTimer = nil
            } else if transcriptionStatus == .recording {
                // Just stopped recording - start processing
                transcriptionStatus = .processing
                // Capture session ID from most recent recording
                if let latest = DatabaseManager.shared.getAllSessions().first {
                    lastSessionId = latest.id
                }
            }
        }
        .onReceive(transcriptCheckTimer) { _ in
            checkTranscriptionStatus()
        }
    }

    private func checkTranscriptionStatus() {
        guard transcriptionStatus == .processing, !lastSessionId.isEmpty else { return }

        // Check if transcript exists for this session
        let transcript = DatabaseManager.shared.getTranscript(sessionId: lastSessionId)

        if !transcript.isEmpty {
            transcriptionStatus = .complete
            print("✅ Transcript ready: \(transcript.prefix(50))...")

            // Auto-copy to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
            print("📋 Copied to clipboard!")

            // Auto-paste after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                simulatePaste()
            }

            // Auto-hide panel after 3 seconds (not the whole app)
            hideTimer?.invalidate()
            hideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                Task { @MainActor in
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.floatingPanel?.orderOut(nil)
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Ultra Compact Recorder (Waveform only, hover to expand)

struct UltraCompactRecorderView: View {
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var recordingState: RecordingState
    @EnvironmentObject var appState: AppState
    let onStartStop: () -> Void
    let onCancel: () -> Void

    @State private var isHovering = false
    @State private var transcriptionStatus: TranscriptionStatus = .idle
    @State private var lastSessionId: String = ""

    let transcriptCheckTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            // Fish logo
            if let iconPath = Bundle.main.resourcePath.map({ $0 + "/AppIcon.icns" }),
               let iconImage = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: iconImage)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.leading, 6)
            }

            // Red dot indicator when recording
            if recordingState == .recording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            }

            // Main tap area - mini waveform
            Button(action: onStartStop) {
                ZStack {
                    MiniWaveform(audioRecorder: audioRecorder, isRecording: recordingState == .recording)
                        .frame(height: 28)

                    // Status overlay
                    if transcriptionStatus == .processing {
                        ProgressView()
                            .scaleEffect(0.4)
                    } else if transcriptionStatus == .complete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            // Close button (Esc)
            Button(action: closeOrCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("Close (Esc)")
        }
        .frame(height: 40)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Expand Window") {
                appState.windowMode = .medium
            }
            Divider()
            Button("Open History") {
                appState.windowMode = .full
            }
            Button("Open Settings") {
                appState.windowMode = .full
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
            }
            Divider()
            Button("Hide") {
                hidePanel()
            }
            Button("Quit BrainPhArt") {
                NSApp.terminate(nil)
            }
        }
        .onChange(of: recordingState) { newState in
            if newState == .recording {
                transcriptionStatus = .recording
            } else if transcriptionStatus == .recording {
                transcriptionStatus = .processing
                if let latest = DatabaseManager.shared.getAllSessions().first {
                    lastSessionId = latest.id
                }
            }
        }
        .onReceive(transcriptCheckTimer) { _ in
            checkTranscription()
        }
    }

    private func checkTranscription() {
        guard transcriptionStatus == .processing, !lastSessionId.isEmpty else { return }
        let transcript = DatabaseManager.shared.getTranscript(sessionId: lastSessionId)
        if !transcript.isEmpty {
            transcriptionStatus = .complete
            print("✅ Got transcript, copying and pasting...")

            // Copy to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
            print("📋 Copied: \(transcript.prefix(30))...")

            // Auto-paste after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                simulatePaste()
                print("⌨️ Paste triggered")
            }

            // Auto-hide after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                hidePanel()
                transcriptionStatus = .idle
                lastSessionId = ""
            }
        }
    }

    private func closeOrCancel() {
        if recordingState == .recording {
            onCancel()
            transcriptionStatus = .idle
        } else {
            hidePanel()
        }
    }

    private func hidePanel() {
        NSApp.windows.first { $0 is FloatingPanel }?.orderOut(nil)
    }
}

// MARK: - Mini Waveform (half the bars for compact pill)

struct MiniWaveform: View {
    @ObservedObject var audioRecorder: AudioRecorder
    let isRecording: Bool

    private let barCount = 20  // Half of original
    @State private var bandLevels: [Float] = Array(repeating: 0, count: 20)

    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isRecording ? Color.white.opacity(0.9) : Color.white.opacity(0.15))
                        .frame(width: 2, height: max(2, CGFloat(bandLevels[index]) * geo.size.height * 0.9))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onReceive(timer) { _ in
            if isRecording {
                let baseLevel = audioRecorder.audioLevel
                for i in 0..<barCount {
                    let centerDistance = abs(Float(i) - Float(barCount) / 2.0) / Float(barCount)
                    let voiceBoost = 1.0 - (centerDistance * 0.2)
                    let variation = Float.random(in: 0.25...1.9)
                    let spike: Float = Float.random(in: 0...1) < 0.15 ? Float.random(in: 1.3...1.9) : 1.0
                    let jitter = Float.random(in: -0.12...0.12)
                    let targetLevel = baseLevel * voiceBoost * variation * spike + jitter
                    let smoothing: Float = 0.6
                    bandLevels[i] = bandLevels[i] * (1 - smoothing) + targetLevel * smoothing
                    if baseLevel > 0.01 {
                        bandLevels[i] = max(0.08, bandLevels[i])
                    }
                }
            }
        }
        .onChange(of: isRecording) { recording in
            if !recording {
                withAnimation(.easeOut(duration: 0.2)) {
                    bandLevels = Array(repeating: 0, count: barCount)
                }
            }
        }
    }
}

// MARK: - Recording Item Model

struct RecordingItem: Identifiable, Equatable {
    let id: String
    let createdAt: Int
    let transcript: String
    let status: String
    let transcriptionProgress: Double
    let hasAudioChunks: Bool

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

    var hasTranscript: Bool {
        !transcript.isEmpty
    }

    // Show processing when: session complete, has audio, but no transcript yet
    var isProcessing: Bool {
        status == "complete" && hasAudioChunks && !hasTranscript
    }
}

// MARK: - History Panel

struct HistoryPanel: View {
    let recordings: [RecordingItem]
    let selectedId: String?
    let onSelect: (RecordingItem) -> Void
    let onRefresh: () -> Void
    let onDelete: (RecordingItem) -> Void
    let onRetryTranscription: (RecordingItem) -> Void

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
                                onSelect: { onSelect(recording) },
                                onDelete: { onDelete(recording) },
                                onRetryTranscription: { onRetryTranscription(recording) }
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

// MARK: - History Card

struct HistoryCard: View {
    let recording: RecordingItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onRetryTranscription: () -> Void

    @State private var spinAngle: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Status indicator (green dot top left)
                if recording.hasTranscript {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                } else if recording.isProcessing {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 6, height: 6)
                }

                Text(recording.dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Spinning pie chart while processing
                if recording.isProcessing {
                    SpinningPieView()
                        .frame(width: 16, height: 16)
                }
            }

            Text(recording.title)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundColor(.primary)

            // Status label
            if recording.hasTranscript {
                Text("Transcription Complete")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            } else if recording.isProcessing {
                Text("Transcribing...")
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
            }
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
        .contextMenu {
            Button(action: onRetryTranscription) {
                Label("Retry Transcription", systemImage: "arrow.clockwise")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

}

// MARK: - Spinning Pie View (animated processing indicator)

struct SpinningPieView: View {
    @State private var rotation: Double = 0
    @State private var trimEnd: Double = 0.3

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.red.opacity(0.2), lineWidth: 2)

            // Spinning arc
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                trimEnd = 0.7
            }
        }
    }
}

// MARK: - Editor View

struct EditorView: View {
    let recording: RecordingItem
    @Binding var transcript: String
    @Binding var showPreview: Bool
    let unreviewedPIICount: Int
    let isRecording: Bool
    let onSave: () -> Void

    @State private var showCopied = false
    @State private var versionNumber: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(recording.dateString)
                    .font(.headline)

                // Privacy Gate button - transparent user control
                PrivacyGateButton(
                    unreviewedCount: unreviewedPIICount,
                    sessionId: recording.id
                )

                // Extract Cards button
                ExtractCardsButton(
                    sessionId: recording.id,
                    transcript: transcript
                )

                Spacer()

                // Copy to clipboard
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        Text(showCopied ? "Copied" : "Copy")
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)

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
                .font(.system(size: 16, weight: .regular, design: .default))
                .padding(16)
                .id(recording.id)

            // Stats bar at bottom
            StatsBar(
                wordCount: wordCount(transcript),
                versionNumber: versionNumber,
                unreviewedCount: unreviewedPIICount,
                isRecording: isRecording
            )
        }
        .onAppear {
            versionNumber = DatabaseManager.shared.getLatestVersion(sessionId: recording.id)?.versionNum ?? 1
        }
        .onChange(of: transcript) { _ in
            versionNumber = DatabaseManager.shared.getLatestVersion(sessionId: recording.id)?.versionNum ?? 1
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
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
    let privacyLevel: String
}
