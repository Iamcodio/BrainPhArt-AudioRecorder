import Foundation
@preconcurrency import SwiftWhisper
import AVFoundation

actor TranscriptionManager {
    static let shared = TranscriptionManager()

    private var whisper: Whisper?
    private var isLoading = false
    private var customVocabulary: [String] = []

    private init() {}

    /// Load custom vocabulary from database for improved recognition
    func loadCustomVocabulary() {
        // Load from custom_dictionary table
        customVocabulary = DatabaseManager.shared.getCustomDictionaryWords()
        print("📚 Loaded \(customVocabulary.count) custom vocabulary words")
    }

    /// Build initial prompt with vocabulary hints for Whisper
    private func buildInitialPrompt() -> String {
        // Include custom words to help Whisper recognize specialized terms
        // Format: comma-separated list of words/phrases
        let vocabHints = customVocabulary.prefix(50).joined(separator: ", ")

        // Base prompt for better transcription quality
        let basePrompt = "Transcribe accurately. Preserve original words and terminology."

        if vocabHints.isEmpty {
            return basePrompt
        } else {
            return "\(basePrompt) Key terms: \(vocabHints)"
        }
    }

    func loadModel() async throws {
        guard whisper == nil, !isLoading else { return }
        isLoading = true

        let modelPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("brainphart/models/ggml-base.bin")

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            isLoading = false
            throw TranscriptionError.modelNotFound(modelPath.path)
        }

        print("🔄 Loading whisper model...")

        // Create params with better quality settings
        let params = WhisperParams(strategy: .beamSearch)
        params.language = .english  // Set explicit language for better accuracy

        whisper = Whisper(fromFileURL: modelPath, withParams: params)

        // Load custom vocabulary
        loadCustomVocabulary()

        isLoading = false
        print("✅ Whisper model loaded with custom vocabulary")
    }

    func transcribe(audioURL: URL) async throws -> String {
        if whisper == nil {
            try await loadModel()
        }

        guard let whisper = whisper else {
            throw TranscriptionError.modelNotLoaded
        }

        // Read and resample audio to 16kHz
        let audioFrames = try await resampleTo16kHz(audioURL)

        print("🎤 Transcribing \(audioFrames.count) samples with vocab hints...")

        // Set initial prompt with vocabulary hints
        // Note: We need to keep the prompt alive during transcription
        let prompt = buildInitialPrompt()
        let promptPointer = strdup(prompt)
        defer { free(promptPointer) }
        whisper.params.initial_prompt = UnsafePointer(promptPointer)

        let segments = try await whisper.transcribe(audioFrames: audioFrames)

        let transcript = segments.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespaces)

        print("📝 Transcribed: \(transcript.prefix(50))...")

        return transcript
    }

    /// Add word to custom vocabulary (for better future recognition)
    func addToVocabulary(_ word: String) {
        if !customVocabulary.contains(word.lowercased()) {
            customVocabulary.append(word.lowercased())
            DatabaseManager.shared.addCustomWord(word)
            print("📚 Added '\(word)' to vocabulary")
        }
    }

    /// Reload vocabulary (call after adding words)
    func reloadVocabulary() {
        loadCustomVocabulary()
    }

    private func resampleTo16kHz(_ sourceURL: URL) async throws -> [Float] {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let sourceFormat = sourceFile.processingFormat
        let sourceSampleRate = sourceFormat.sampleRate

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw TranscriptionError.formatError
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw TranscriptionError.converterError
        }

        let frameCount = AVAudioFrameCount(sourceFile.length)
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw TranscriptionError.bufferError
        }

        try sourceFile.read(into: sourceBuffer)

        let ratio = 16000.0 / sourceSampleRate
        let targetFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)

        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount) else {
            throw TranscriptionError.bufferError
        }

        var error: NSError?
        converter.convert(to: targetBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let error = error {
            throw TranscriptionError.conversionFailed(error.localizedDescription)
        }

        guard let channelData = targetBuffer.floatChannelData else {
            throw TranscriptionError.noChannelData
        }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(targetBuffer.frameLength)))

        return samples
    }
}

enum TranscriptionError: Error, LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded
    case formatError
    case converterError
    case bufferError
    case conversionFailed(String)
    case noChannelData

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Whisper model not found at: \(path)"
        case .modelNotLoaded:
            return "Whisper model not loaded"
        case .formatError:
            return "Failed to create audio format"
        case .converterError:
            return "Failed to create audio converter"
        case .bufferError:
            return "Failed to create audio buffer"
        case .conversionFailed(let message):
            return "Audio conversion failed: \(message)"
        case .noChannelData:
            return "No channel data in buffer"
        }
    }
}
