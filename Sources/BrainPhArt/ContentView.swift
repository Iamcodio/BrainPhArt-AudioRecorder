import SwiftUI

struct ContentView: View {
    @State private var recordingState: RecordingState = .idle
    @State private var selectedRecording: Recording? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            
            HSplitView {
                HistoryPanel(selectedRecording: $selectedRecording)
                    .frame(minWidth: 200, idealWidth: 250, maxWidth: 400)
                
                RecorderPanel(recordingState: $recordingState)
                    .frame(minWidth: 400)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

struct TopBar: View {
    var body: some View {
        HStack(spacing: 16) {
            Button(action: { print("Settings") }) {
                Image(systemName: "gear").font(.title2)
            }
            Button(action: { print("Folder") }) {
                Image(systemName: "folder").font(.title2)
            }
            Button(action: { print("Help") }) {
                Image(systemName: "questionmark.circle").font(.title2)
            }
            Spacer()
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct HistoryPanel: View {
    @Binding var selectedRecording: Recording?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HISTORY").font(.headline).padding()
            Divider()
            ScrollView {
                Text("No recordings yet")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct RecorderPanel: View {
    @Binding var recordingState: RecordingState
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            WaveformView().frame(height: 150).padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: {
                recordingState = (recordingState == .idle) ? .recording : .idle
                print(recordingState == .recording ? "START" : "STOP")
            }) {
                Label(recordingState == .idle ? "START" : "STOP", 
                      systemImage: recordingState == .idle ? "record.circle" : "stop.circle")
                    .font(.title2)
                    .frame(width: 200, height: 60)
            }
            .buttonStyle(.borderedProminent)
            .tint(recordingState == .idle ? .red : .gray)
            
            Spacer()
        }
    }
}

struct WaveformView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<50) { _ in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 4, height: CGFloat.random(in: 10...100))
            }
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct Recording: Identifiable {
    let id = UUID()
    let timestamp: String
    let duration: String
}

enum RecordingState {
    case idle
    case recording
}
