import AVFoundation
import SwiftUI

enum AudioSource: String, CaseIterable {
    case microphone = "Microphone"
    case systemAudio = "System Audio"
    case both = "Mic + System"
}


final class AudioRecorder: NSObject, ObservableObject, @unchecked Sendable {
    @Published var isRecording = false
    @Published var audioSource: AudioSource = .microphone
    @Published var audioLevel: Float = 0.0  // Live audio level for waveform
    @Published var recordingDuration: TimeInterval = 0

    @Published var micVolume: Float = 0.8
    @Published var systemVolume: Float = 0.2
    @Published var outputVolume: Float = 1.0
    
    private var audioEngine = AVAudioEngine()
    private var currentSessionId: String = ""
    
    private let bufferQueue = DispatchQueue(label: "com.brainphart.audioBuffer", qos: .userInitiated)
    private var audioBuffer: [Float] = []
    private var sampleRate: Double = 0
    private var chunkNumber: Int = 0
    private let chunkDuration: TimeInterval = 32.0
    
    private var consumerTask: Task<Void, Never>?
    private var shouldContinueProcessing = false
    private var recordingTimer: Timer?
    
    override init() {
        super.init()
        print("✅ AudioRecorder initialized (Black Box Mode)")
    }
    

    func startRecording(sessionId: String) async {
        currentSessionId = sessionId
        
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        
        guard micGranted else {
            print("❌ Microphone permission denied")
            return
        }
        
        print("✅ Microphone permission granted")
        
        bufferQueue.sync {
            audioBuffer = []
            chunkNumber = 0
        }
        
        setupAudioEngine()
        startConsumerTask()
    }
    

    func stopRecording() {
        print("⏹️ Stopping")

        isRecording = false
        shouldContinueProcessing = false

        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        consumerTask?.cancel()
        consumerTask = nil

        // IMPORTANT: Save any remaining audio in buffer (for short recordings < 32s)
        var finalSamples: [Float]?
        bufferQueue.sync {
            if !audioBuffer.isEmpty {
                finalSamples = audioBuffer
                audioBuffer = []
            }
        }

        if let samples = finalSamples, !samples.isEmpty {
            print("💾 Saving final chunk with \(samples.count) samples")
            _ = saveChunk(samples: samples, isFinal: true)
        }

        // Mark session complete before clearing
        if !currentSessionId.isEmpty {
            DatabaseManager.shared.completeSession(id: currentSessionId)
        }

        print("✅ Stopped")
        currentSessionId = ""
    }

    func cancelRecording() {
        print("❌ Cancelling")

        isRecording = false
        shouldContinueProcessing = false

        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        consumerTask?.cancel()
        consumerTask = nil

        // Mark session cancelled (keep chunks - black box principle)
        if !currentSessionId.isEmpty {
            DatabaseManager.shared.cancelSession(id: currentSessionId)
        }

        print("✅ Cancelled")
        currentSessionId = ""
    }
    
    private func setupAudioEngine() {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        sampleRate = format.sampleRate
        
        print("🎤 \(format.sampleRate)Hz, \(format.channelCount)ch")
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self = self else { return }

            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

            // Calculate RMS audio level for waveform
            let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
            let rms = sqrt(sumOfSquares / Float(samples.count))
            let level = min(1.0, rms * 5.0)  // Scale up for visibility

            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }

            self.bufferQueue.async {
                self.audioBuffer.append(contentsOf: samples)
            }
        }
        
        do {
            try audioEngine.start()
            shouldContinueProcessing = true
            Task { @MainActor [weak self] in
                self?.isRecording = true
                self?.recordingDuration = 0
                self?.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self = self, self.isRecording else { return }
                    Task { @MainActor in
                        self.recordingDuration += 1.0
                    }
                }
            }
            print("🔴 Started recording (microphone only)")
        } catch {
            print("❌ Failed to start: \(error)")
        }
    }
    
    private func startConsumerTask() {
        consumerTask = Task.detached { [weak self] in
            guard let self = self else { return }
            
            while self.shouldContinueProcessing {
                let samplesNeeded = Int(self.chunkDuration * self.sampleRate)
                
                var chunkSamples: [Float]?
                
                self.bufferQueue.sync {
                    if self.audioBuffer.count >= samplesNeeded {
                        chunkSamples = Array(self.audioBuffer.prefix(samplesNeeded))
                        self.audioBuffer.removeFirst(samplesNeeded)
                    }
                }
                
                if let samples = chunkSamples {
                    var saveSuccess = false
                    var retryCount = 0
                    
                    while !saveSuccess && retryCount < 5 {
                        saveSuccess = self.saveChunk(samples: samples, isFinal: false)
                        
                        if !saveSuccess {
                            retryCount += 1
                            print("⚠️ Chunk \(self.chunkNumber) save failed, retry \(retryCount)/5")
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                    }
                    
                    if saveSuccess {
                        self.chunkNumber += 1
                    } else {
                        print("❌ CRITICAL: Failed to save chunk \(self.chunkNumber) after 5 retries")
                        self.bufferQueue.sync {
                            self.audioBuffer.insert(contentsOf: samples, at: 0)
                        }
                    }
                }
                
                try? await Task.sleep(for: .milliseconds(100))
            }
            
            var finalSamples: [Float]?
            self.bufferQueue.sync {
                if !self.audioBuffer.isEmpty {
                    finalSamples = self.audioBuffer
                    self.audioBuffer = []
                }
            }
            
            if let samples = finalSamples {
                _ = self.saveChunk(samples: samples, isFinal: true)
            }
        }
    }
    
    private func saveChunk(samples: [Float], isFinal: Bool) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        
        let audioDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("brainphart/audio/\(dateString)")
        
        do {
            try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create directory: \(error)")
            return false
        }
        
        let fileName = "session_\(currentSessionId)_chunk_\(chunkNumber).wav"
        let fileURL = audioDir.appendingPathComponent(fileName)
        
        do {
            try writeWAV(samples: samples, to: fileURL, sampleRate: sampleRate)
        } catch {
            print("❌ Failed to write WAV: \(error)")
            return false
        }
        
        let chunkId = UUID().uuidString
        let durationMs = Int(Double(samples.count) / sampleRate * 1000.0)
        
        DatabaseManager.shared.createChunk(
            id: chunkId,
            sessionId: currentSessionId,
            chunkNumber: chunkNumber,
            filePath: fileURL.path,
            durationMs: durationMs
        )

        let finalLabel = isFinal ? " (FINAL)" : ""
        print("💾 Chunk \(chunkNumber) saved: \(fileName) (\(samples.count) samples, \(durationMs)ms)\(finalLabel)")
        
        return true
    }
    
    private func writeWAV(samples: [Float], to url: URL, sampleRate: Double) throws {
        let sampleRateInt = Int32(sampleRate)
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let bytesPerSample = Int16(bitsPerSample / 8)
        
        let int16Samples = samples.map { sample in
            Int16(max(-1.0, min(1.0, sample)) * 32767.0)
        }
        
        var data = Data()
        
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(36 + int16Samples.count * 2)) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)
        
        data.append("fmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(16)) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(1)) { Data($0) })
        data.append(withUnsafeBytes(of: numChannels) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRateInt) { Data($0) })
        
        let byteRate = sampleRateInt * Int32(numChannels) * Int32(bytesPerSample)
        data.append(withUnsafeBytes(of: byteRate) { Data($0) })
        
        let blockAlign = numChannels * bytesPerSample
        data.append(withUnsafeBytes(of: blockAlign) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample) { Data($0) })
        
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(int16Samples.count * 2)) { Data($0) })
        
        for sample in int16Samples {
            data.append(withUnsafeBytes(of: sample) { Data($0) })
        }
        
        try data.write(to: url)
    }
}
