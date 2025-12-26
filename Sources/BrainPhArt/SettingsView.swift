import SwiftUI
import AVFoundation
import CoreAudio

// MARK: - Settings View (Phase 0.1)

struct SettingsView: View {
    @Binding var isPresented: Bool
    @StateObject private var audioDevices = AudioDeviceManager()
    @StateObject private var audioTester = AudioTester()

    @AppStorage("inputDeviceID") private var inputDeviceID: String = ""
    @AppStorage("outputDeviceID") private var outputDeviceID: String = ""
    @AppStorage("inputLevel") private var inputLevel: Double = 0.8
    @AppStorage("outputLevel") private var outputLevel: Double = 1.0
    @AppStorage("spellCheckLanguage") private var spellCheckLanguage: String = "en-GB"
    @AppStorage("llm_provider") private var llmProvider: String = "ollama"

    @State private var claudeAPIKey: String = ""
    @State private var openaiAPIKey: String = ""
    @State private var geminiAPIKey: String = ""
    @State private var openrouterAPIKey: String = ""
    @State private var showAPIKeys: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("SETTINGS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // INPUT DEVICE
                    VStack(alignment: .leading, spacing: 8) {
                        Text("INPUT DEVICE")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker("", selection: $inputDeviceID) {
                            Text("System Default").tag("")
                            ForEach(audioDevices.inputDevices, id: \.id) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    // INPUT LEVEL
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("INPUT LEVEL")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(inputLevel * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $inputLevel, in: 0...1)
                            .tint(.primary)
                    }

                    // TEST INPUT
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("TEST INPUT")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()

                            // Status indicator
                            if audioTester.testResult == .success {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Device Working")
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                }
                            } else if audioTester.testResult == .failed {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text("No Signal")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red)
                                }
                            }

                            Button(action: {
                                audioTester.runTest()
                            }) {
                                Text(audioTester.isRunning ? "Testing..." : "Test")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .disabled(audioTester.isRunning)
                        }

                        // Level meter with clipping gradient
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.primary.opacity(0.1))

                                // Clipping zone markers (last 20%)
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(width: geo.size.width * 0.8)
                                    Rectangle()
                                        .fill(Color.red.opacity(0.15))
                                        .frame(width: geo.size.width * 0.2)
                                }
                                .cornerRadius(2)

                                // Level bar with gradient
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            colors: [.green, .yellow, .orange, .red],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * CGFloat(audioTester.level))
                            }
                        }
                        .frame(height: 10)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // OUTPUT DEVICE
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OUTPUT DEVICE")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker("", selection: $outputDeviceID) {
                            Text("System Default").tag("")
                            ForEach(audioDevices.outputDevices, id: \.id) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    // OUTPUT LEVEL
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("OUTPUT LEVEL")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(outputLevel * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $outputLevel, in: 0...1)
                            .tint(.primary)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // SPELL CHECK LANGUAGE
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SPELL CHECK")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker("Language", selection: $spellCheckLanguage) {
                            Text("British English").tag("en-GB")
                            Text("American English").tag("en-US")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: spellCheckLanguage) { newValue in
                            // Reload dictionary when language changes
                            Task {
                                await SpellEngine.shared.reloadDictionary(language: newValue)
                            }
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // LLM PROVIDER
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI PROVIDER")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        Picker("Provider", selection: $llmProvider) {
                            ForEach(LLMProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider.rawValue)
                            }
                        }
                        .pickerStyle(.menu)

                        // API Keys section
                        HStack {
                            Text("API Keys")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: { showAPIKeys.toggle() }) {
                                Image(systemName: showAPIKeys ? "eye.slash" : "eye")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)

                        // Claude API Key
                        HStack {
                            Text("Claude:")
                                .font(.system(size: 11))
                                .frame(width: 80, alignment: .leading)
                            if showAPIKeys {
                                TextField("sk-ant-...", text: $claudeAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            } else {
                                SecureField("sk-ant-...", text: $claudeAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                        .onChange(of: claudeAPIKey) { newValue in
                            Task { await LLMService.shared.setAPIKey(newValue, for: .claude) }
                        }

                        // OpenAI API Key
                        HStack {
                            Text("OpenAI:")
                                .font(.system(size: 11))
                                .frame(width: 80, alignment: .leading)
                            if showAPIKeys {
                                TextField("sk-...", text: $openaiAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            } else {
                                SecureField("sk-...", text: $openaiAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                        .onChange(of: openaiAPIKey) { newValue in
                            Task { await LLMService.shared.setAPIKey(newValue, for: .openai) }
                        }

                        // Gemini API Key
                        HStack {
                            Text("Gemini:")
                                .font(.system(size: 11))
                                .frame(width: 80, alignment: .leading)
                            if showAPIKeys {
                                TextField("AIza...", text: $geminiAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            } else {
                                SecureField("AIza...", text: $geminiAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                        .onChange(of: geminiAPIKey) { newValue in
                            Task { await LLMService.shared.setAPIKey(newValue, for: .gemini) }
                        }

                        // OpenRouter API Key
                        HStack {
                            Text("OpenRouter:")
                                .font(.system(size: 11))
                                .frame(width: 80, alignment: .leading)
                            if showAPIKeys {
                                TextField("sk-or-...", text: $openrouterAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            } else {
                                SecureField("sk-or-...", text: $openrouterAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                        .onChange(of: openrouterAPIKey) { newValue in
                            Task { await LLMService.shared.setAPIKey(newValue, for: .openrouter) }
                        }

                        Text("Ollama runs locally - no API key needed")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // LOCATIONS (read-only)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STORAGE LOCATIONS")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Audio:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("~/brainphart/audio/")
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            HStack {
                                Text("Database:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("~/Library/Application Support/brainphart/")
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 400, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Load existing API keys from Keychain
            Task {
                claudeAPIKey = await LLMService.shared.getAPIKey(for: .claude) ?? ""
                openaiAPIKey = await LLMService.shared.getAPIKey(for: .openai) ?? ""
                geminiAPIKey = await LLMService.shared.getAPIKey(for: .gemini) ?? ""
                openrouterAPIKey = await LLMService.shared.getAPIKey(for: .openrouter) ?? ""
            }
        }
    }

}

// MARK: - Audio Tester (simple AVAudioRecorder approach)

enum TestResult {
    case none
    case success
    case failed
}

@MainActor
class AudioTester: ObservableObject {
    @Published var isRunning = false
    @Published var level: Float = 0.0
    @Published var testResult: TestResult = .none

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var peakLevel: Float = -160.0

    func runTest() {
        testResult = .none
        peakLevel = -160.0
        isRunning = true
        level = 0

        print("🎤 ========== AUDIO TEST STARTING ==========")

        // Setup audio session
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            recorder = try AVAudioRecorder(url: tempURL, settings: settings)
            recorder?.isMeteringEnabled = true
            recorder?.prepareToRecord()

            guard recorder?.record() == true else {
                print("❌ Could not start recording")
                testFailed()
                return
            }

            print("✅ Test recording started")

            // Poll levels every 100ms
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateLevel()
                }
            }

            // Stop after 10 seconds (gives time to adjust levels)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                self?.finishTest(tempURL: tempURL)
            }

        } catch {
            print("❌ Test setup error: \(error.localizedDescription)")
            testFailed()
        }
    }

    private func updateLevel() {
        recorder?.updateMeters()
        let db = recorder?.averagePower(forChannel: 0) ?? -160.0

        // Convert dB to 0-1 range (dB is typically -160 to 0)
        let normalized = max(0, (db + 50) / 50)
        level = Float(normalized)

        if db > peakLevel {
            peakLevel = db
        }
    }

    private func finishTest(tempURL: URL) {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        print("🎤 Peak level: \(peakLevel) dB")

        // If peak > -40dB, we detected sound
        if peakLevel > -40 {
            testResult = .success
            print("✅ ========== DEVICE WORKING ==========")
        } else {
            testResult = .failed
            print("❌ ========== NO SIGNAL DETECTED ==========")
        }

        isRunning = false
        level = 0
    }

    private func testFailed() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        testResult = .failed
        isRunning = false
        level = 0
    }
}

// MARK: - Audio Device Manager

struct AudioDevice: Identifiable {
    let id: String
    let name: String
    let isInput: Bool
}

class AudioDeviceManager: ObservableObject {
    @Published var inputDevices: [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []

    init() {
        loadDevices()
    }

    func loadDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return }

        var inputs: [AudioDevice] = []
        var outputs: [AudioDevice] = []

        for deviceID in deviceIDs {
            if let name = getDeviceName(deviceID) {
                let hasInput = hasStreams(deviceID, scope: kAudioDevicePropertyScopeInput)
                let hasOutput = hasStreams(deviceID, scope: kAudioDevicePropertyScopeOutput)

                if hasInput {
                    inputs.append(AudioDevice(id: String(deviceID), name: name, isInput: true))
                }
                if hasOutput {
                    outputs.append(AudioDevice(id: String(deviceID), name: name, isInput: false))
                }
            }
        }

        inputDevices = inputs
        outputDevices = outputs
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        return status == noErr ? name as String? : nil
    }

    private func hasStreams(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)

        return status == noErr && dataSize > 0
    }
}
