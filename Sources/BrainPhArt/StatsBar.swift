import SwiftUI

struct StatsBar: View {
    let wordCount: Int
    let versionNumber: Int
    let unreviewedCount: Int
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Word count
            HStack(spacing: 4) {
                Image(systemName: "text.word.spacing")
                    .font(.system(size: 12))
                Text("Words: \(wordCount)")
            }

            Divider()
                .frame(height: 16)

            // Version number
            Text("v\(versionNumber)")

            Divider()
                .frame(height: 16)

            // Privacy status
            if unreviewedCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text("\(unreviewedCount) unreviewed")
                }
                .foregroundColor(.yellow)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Ready to publish")
                }
                .foregroundColor(.green)
            }

            Divider()
                .frame(height: 16)

            // Recording indicator
            if isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("Recording")
                }
                .foregroundColor(.red)
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text("Idle")
                }
                .foregroundColor(.gray)
            }

            Spacer()
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white.opacity(0.9))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 36)
        .background(Color.black.opacity(0.85))
    }
}

// #Preview macros require Xcode - commented out for SPM builds
// #Preview {
//     VStack(spacing: 0) {
//         Spacer()
//         StatsBar(
//             wordCount: 234,
//             versionNumber: 3,
//             unreviewedCount: 3,
//             isRecording: true
//         )
//     }
//     .frame(width: 600, height: 200)
// }

// #Preview("Ready State") {
//     VStack(spacing: 0) {
//         Spacer()
//         StatsBar(
//             wordCount: 1024,
//             versionNumber: 5,
//             unreviewedCount: 0,
//             isRecording: false
//         )
//     }
//     .frame(width: 600, height: 200)
// }
