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

enum WindowMode {
    case micro    // Tiny pill
    case medium   // Floating recorder with controls
    case full     // Main UI with history
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    @Published var windowMode: WindowMode = .full  // Opens to main window by default

    // Legacy compatibility
    var isFloatingMode: Bool {
        get { windowMode != .full }
        set { windowMode = newValue ? .micro : .full }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingPanel: FloatingPanel?
    let appState = AppState.shared

    // Window sizes for 3 modes
    private let microSize = NSSize(width: 200, height: 52)     // Tiny pill
    private let mediumSize = NSSize(width: 340, height: 100)   // Floating recorder
    private let fullSize = NSSize(width: 1200, height: 800)    // Main UI

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

        // Create the panel - start in FULL mode with title bar
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // Start with full size, centered
        let startWidth: CGFloat = 1100
        let startHeight: CGFloat = 700
        let x = (screenFrame.width - startWidth) / 2 + screenFrame.origin.x
        let y = (screenFrame.height - startHeight) / 2 + screenFrame.origin.y

        let panel = FloatingPanel(
            contentRect: NSRect(x: x, y: y, width: startWidth, height: startHeight),
            showsTitleBar: true  // Show traffic lights and allow resize
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
        appState.$windowMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.updateWindowForMode(mode)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func updateWindowForMode(_ mode: WindowMode) {
        guard let panel = floatingPanel else { return }

        switch mode {
        case .micro:
            // Tiny pill - floating, on top
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear

            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = (screenFrame.width - microSize.width) / 2 + screenFrame.origin.x
                let y = screenFrame.maxY - microSize.height - 40
                panel.setFrame(
                    NSRect(x: x, y: y, width: microSize.width, height: microSize.height),
                    display: true,
                    animate: true
                )
            }

        case .medium:
            // Medium floating recorder - floating, on top
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear

            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = (screenFrame.width - mediumSize.width) / 2 + screenFrame.origin.x
                let y = screenFrame.maxY - mediumSize.height - 40
                panel.setFrame(
                    NSRect(x: x, y: y, width: mediumSize.width, height: mediumSize.height),
                    display: true,
                    animate: true
                )
            }

        case .full:
            // Full main UI - normal level, larger, opaque
            panel.level = .normal
            panel.collectionBehavior = [.managed, .fullScreenPrimary]
            panel.isOpaque = true
            panel.backgroundColor = NSColor.windowBackgroundColor

            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = (screenFrame.width - fullSize.width) / 2 + screenFrame.origin.x
                let y = (screenFrame.height - fullSize.height) / 2 + screenFrame.origin.y
                panel.setFrame(
                    NSRect(x: x, y: y, width: fullSize.width, height: fullSize.height),
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
        let hasCtrl = modifiers.contains(.control)
        let hasShift = modifiers.contains(.shift)
        let isSpace = keyCode == 49

        if hasCtrl && hasShift && isSpace {
            print("🎤 Hotkey triggered: Ctrl+Shift+Space")
            // Show the app first
            NSApp.activate(ignoringOtherApps: true)
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.floatingPanel?.makeKeyAndOrderFront(nil)
            }
            // Then toggle recording
            NotificationCenter.default.post(name: .toggleRecording, object: nil)
        }

        // Escape - Cancel recording or close panel
        if keyCode == 53 {
            NotificationCenter.default.post(name: .cancelRecording, object: nil)
            // Also hide panel if in floating mode
            if let delegate = NSApp.delegate as? AppDelegate,
               delegate.appState.isFloatingMode {
                delegate.floatingPanel?.orderOut(nil)
            }
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
    static let openSettings = Notification.Name("openSettings")
}
