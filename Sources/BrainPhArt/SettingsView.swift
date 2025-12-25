import SwiftUI
import AVFoundation
import CoreAudio

// MARK: - Settings View (Phase 0.1)

struct SettingsView: View {
    @Binding var isPresented: Bool
    @StateObject private var audioDevices = AudioDeviceManager()

    @AppStorage("inputDeviceID") private var inputDeviceID: String = ""
    @AppStorage("outputDeviceID") private var outputDeviceID: String = ""
    @AppStorage("inputLevel") private var inputLevel: Double = 0.8
    @AppStorage("outputLevel") private var outputLevel: Double = 1.0

    @State private var testLevel: Float = 0.0
    @State private var isTesting: Bool = false

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
                            Button(action: toggleTest) {
                                Text(isTesting ? "Stop" : "Test")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.08))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }

                        // Level meter
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.primary.opacity(0.1))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.primary.opacity(0.5))
                                    .frame(width: geo.size.width * CGFloat(testLevel))
                            }
                        }
                        .frame(height: 8)
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
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toggleTest() {
        isTesting.toggle()
        if isTesting {
            startLevelMonitoring()
        } else {
            stopLevelMonitoring()
        }
    }

    private func startLevelMonitoring() {
        // Simple level test using AVAudioEngine
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let samples = UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength))
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
            DispatchQueue.main.async {
                self.testLevel = min(1.0, rms * 5.0)
            }
        }

        do {
            try engine.start()
        } catch {
            print("Test failed: \(error)")
        }
    }

    private func stopLevelMonitoring() {
        testLevel = 0
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
