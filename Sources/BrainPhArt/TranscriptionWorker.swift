import Foundation

actor TranscriptionWorker {
    static let shared = TranscriptionWorker()

    private var isRunning = false
    private var workerTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        print("🔄 TranscriptionWorker started")

        workerTask = Task.detached { [weak self] in
            while await self?.isRunning == true {
                await self?.processPendingChunks()
                try? await Task.sleep(for: .seconds(3))
            }

            print("⏹️ TranscriptionWorker stopped")
        }
    }

    /// Process pending chunks immediately (call after retry)
    func processNow() {
        Task {
            await processPendingChunks()
        }
    }

    private func processPendingChunks() async {
        let pending = DatabaseManager.shared.getPendingChunks()

        if !pending.isEmpty {
            print("📋 Processing \(pending.count) pending chunks...")
        }

        for chunk in pending {
            do {
                let url = URL(fileURLWithPath: chunk.filePath)

                // Check file exists
                guard FileManager.default.fileExists(atPath: chunk.filePath) else {
                    print("⚠️ Audio file not found: \(chunk.filePath)")
                    DatabaseManager.shared.updateChunkTranscriptionStatus(chunkId: chunk.id, status: "missing_file")
                    continue
                }

                let transcript = try await TranscriptionManager.shared.transcribe(audioURL: url)
                DatabaseManager.shared.saveTranscript(
                    sessionId: chunk.sessionId,
                    chunkNumber: chunk.chunkNumber,
                    transcript: transcript
                )
                DatabaseManager.shared.updateChunkTranscriptionStatus(chunkId: chunk.id, status: "complete")

                // Save RAW transcript to file
                let sessionDate = DatabaseManager.shared.getSessionDate(sessionId: chunk.sessionId)
                _ = DatabaseManager.shared.saveRawTranscriptFile(
                    sessionId: chunk.sessionId,
                    content: transcript,
                    date: sessionDate
                )

                print("✅ Transcribed chunk \(chunk.chunkNumber)")

                // Notify UI to refresh
                await MainActor.run {
                    NotificationCenter.default.post(name: .transcriptionComplete, object: chunk.sessionId)
                }
            } catch {
                DatabaseManager.shared.updateChunkTranscriptionStatus(chunkId: chunk.id, status: "failed")
                print("❌ Transcription failed: \(error)")
            }
        }
    }

    func stop() {
        isRunning = false
        workerTask?.cancel()
        workerTask = nil
    }
}

// Notifications for transcription events
extension Notification.Name {
    static let transcriptionComplete = Notification.Name("transcriptionComplete")
    static let transcriptSaved = Notification.Name("transcriptSaved")
}
