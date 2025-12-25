import SwiftUI
import AppKit

@main
struct BrainPhArtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    Task {
                        await TranscriptionWorker.shared.start()
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force app to foreground when launched from CLI
        NSApp.activate(ignoringOtherApps: true)

        // Ensure window is visible
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.center()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
