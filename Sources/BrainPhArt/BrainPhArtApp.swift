import SwiftUI
import AppKit
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Auto-Paste Helper

@MainActor
func simulatePaste() {
    let source = CGEventSource(stateID: .hidSystemState)

    if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) {
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
    }

    usleep(10000)

    if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }

    print("⌨️ Simulated Cmd+V paste")
}

// MARK: - App Entry Point

@main
struct BrainPhArtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty WindowGroup - we use our own FloatingPanel instead
        WindowGroup {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    // Hide the default window, use our FloatingPanel
                    DispatchQueue.main.async {
                        NSApp.windows.first?.orderOut(nil)
                        appDelegate.showFloatingPanel()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1, height: 1)
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    @Published var isFloatingMode = true
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingPanel: FloatingPanel?
    let appState = AppState.shared

    // Window sizes
    private let floatingSize = NSSize(width: 340, height: 100)
    private let expandedSize = NSSize(width: 1200, height: 800)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        registerGlobalHotkeys()

        // Start transcription worker
        Task {
            await TranscriptionWorker.shared.start()
        }
    }

    func showFloatingPanel() {
        if floatingPanel != nil {
            floatingPanel?.makeKeyAndOrderFront(nil)
            return
        }

        // Create the panel
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = (screenFrame.width - floatingSize.width) / 2 + screenFrame.origin.x
        let y = screenFrame.maxY - floatingSize.height - 40

        let panel = FloatingPanel(
            contentRect: NSRect(x: x, y: y, width: floatingSize.width, height: floatingSize.height)
        )

        // Embed SwiftUI ContentView
        let contentView = ContentView()
            .environmentObject(appState)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.makeKeyAndOrderFront(nil)
        floatingPanel = panel

        // Watch for mode changes
        appState.$isFloatingMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] floating in
                self?.updateWindowForMode(floating: floating)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func updateWindowForMode(floating: Bool) {
        guard let panel = floatingPanel else { return }

        if floating {
            // Floating mode - on top, compact
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = (screenFrame.width - floatingSize.width) / 2 + screenFrame.origin.x
                let y = screenFrame.maxY - floatingSize.height - 40
                panel.setFrame(
                    NSRect(x: x, y: y, width: floatingSize.width, height: floatingSize.height),
                    display: true,
                    animate: true
                )
            }
        } else {
            // Expanded mode - normal level, larger
            panel.level = .normal
            panel.collectionBehavior = [.managed, .fullScreenPrimary]

            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = (screenFrame.width - expandedSize.width) / 2 + screenFrame.origin.x
                let y = (screenFrame.height - expandedSize.height) / 2 + screenFrame.origin.y
                panel.setFrame(
                    NSRect(x: x, y: y, width: expandedSize.width, height: expandedSize.height),
                    display: true,
                    animate: true
                )
            }
        }

        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func registerGlobalHotkeys() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            Task { @MainActor in
                Self.handleGlobalKeyEvent(keyCode: keyCode, modifiers: modifiers)
            }
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            Task { @MainActor in
                Self.handleGlobalKeyEvent(keyCode: keyCode, modifiers: modifiers)
            }
            return event
        }
    }

    static func handleGlobalKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        // Ctrl+Shift+Space - Toggle recording
        if modifiers.contains([.control, .shift]) && keyCode == 49 {
            NotificationCenter.default.post(name: .toggleRecording, object: nil)
        }

        // Escape - Cancel recording
        if keyCode == 53 {
            NotificationCenter.default.post(name: .cancelRecording, object: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running - we manage our own FloatingPanel
    }
}

// MARK: - Combine Import

import Combine

// MARK: - Notification Names

extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
    static let cancelRecording = Notification.Name("cancelRecording")
}
