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
                let pending = DatabaseManager.shared.getPendingChunks()

                for chunk in pending {
                    do {
                        let url = URL(fileURLWithPath: chunk.filePath)
                        let transcript = try await TranscriptionManager.shared.transcribe(audioURL: url)
                        DatabaseManager.shared.saveTranscript(
                            sessionId: chunk.sessionId,
                            chunkNumber: chunk.chunkNumber,
                            transcript: transcript
                        )
                        DatabaseManager.shared.updateChunkTranscriptionStatus(chunkId: chunk.id, status: "complete")
                        print("✅ Transcribed chunk \(chunk.chunkNumber)")
                    } catch {
                        DatabaseManager.shared.updateChunkTranscriptionStatus(chunkId: chunk.id, status: "failed")
                        print("❌ Transcription failed: \(error)")
                    }
                }

                try? await Task.sleep(for: .seconds(3))
            }

            print("⏹️ TranscriptionWorker stopped")
        }
    }

    func stop() {
        isRunning = false
        workerTask?.cancel()
        workerTask = nil
    }
}
