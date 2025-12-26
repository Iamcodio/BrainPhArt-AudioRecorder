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
        // Empty WindowGroup - we use our own window instead
        WindowGroup {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    // Hide the default window, show our main window
                    DispatchQueue.main.async {
                        // Close any SwiftUI-created windows
                        for window in NSApp.windows where window != appDelegate.mainWindow {
                            window.orderOut(nil)
                        }
                        // Force app to foreground and show main window
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
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
    @Published var windowMode: WindowMode = .full  // Main window first

    // Focus restoration for dictation
    var previousApp: NSRunningApplication?
    var wasInternalDictation: Bool = false  // True if dictating into BrainPhArt itself

    // Legacy compatibility
    var isFloatingMode: Bool {
        get { windowMode != .full }
        set { windowMode = newValue ? .micro : .full }
    }

    /// Save the currently focused app before starting recording
    func saveFocusedApp() {
        previousApp = NSWorkspace.shared.frontmostApplication
        // Check if it's us - internal dictation
        wasInternalDictation = previousApp?.bundleIdentifier == Bundle.main.bundleIdentifier
        print("📍 Saved focus: \(previousApp?.localizedName ?? "none"), internal: \(wasInternalDictation)")
    }

    /// Restore focus to the previously focused app
    func restoreFocus() {
        guard let app = previousApp else {
            print("📍 No previous app to restore focus to")
            return
        }

        print("📍 Restoring focus to: \(app.localizedName ?? "unknown")")

        if wasInternalDictation {
            // For internal dictation, we need to activate main window and focus its text field
            if let delegate = NSApp.delegate as? AppDelegate {
                // First hide the floating panel
                delegate.floatingPanel?.orderOut(nil)
                // Then show main window and focus chat input
                delegate.mainWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                // Post notification to focus the chat input
                NotificationCenter.default.post(name: .focusChatInput, object: nil)
            }
        } else {
            // External app - hide our panel first, then activate the other app
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.floatingPanel?.orderOut(nil)
            }
            app.activate(options: [])
        }

        // Clear saved state
        previousApp = nil
        wasInternalDictation = false
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var floatingPanel: FloatingPanel?  // Borderless pill for dictation
    var mainWindow: NSWindow?          // Regular window (NOT floating) for editing
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
        // Start with main window (full mode with traffic lights)
        if appState.windowMode == .full {
            showMainWindow()
            setupModeWatcher()
            return
        }

        // For floating modes, create the borderless pill
        if floatingPanel != nil {
            floatingPanel?.makeKeyAndOrderFront(nil)
            return
        }

        createFloatingPill()
        setupModeWatcher()
    }

    private func createFloatingPill() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // Borderless floating pill for dictation
        let startWidth: CGFloat = mediumSize.width
        let startHeight: CGFloat = mediumSize.height
        let x = (screenFrame.width - startWidth) / 2 + screenFrame.origin.x
        let y = screenFrame.maxY - startHeight - 40

        let panel = FloatingPanel(
            contentRect: NSRect(x: x, y: y, width: startWidth, height: startHeight),
            showsTitleBar: false  // Borderless - no traffic lights
        )

        // Embed SwiftUI ContentView
        let contentView = ContentView()
            .environmentObject(appState)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.makeKeyAndOrderFront(nil)
        floatingPanel = panel
    }

    private var cancellables = Set<AnyCancellable>()
    private var modeWatcherSetup = false

    private func setupModeWatcher() {
        guard !modeWatcherSetup else { return }
        modeWatcherSetup = true

        // Watch for mode changes
        appState.$windowMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.updateWindowForMode(mode)
            }
            .store(in: &cancellables)
    }

    func updateWindowForMode(_ mode: WindowMode) {
        switch mode {
        case .micro, .medium:
            // Hide main window, show floating pill
            mainWindow?.orderOut(nil)

            // Create floating pill if needed
            if floatingPanel == nil {
                createFloatingPill()
            }

            guard let panel = floatingPanel else { return }
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear

            let size = mode == .micro ? microSize : mediumSize

            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = (screenFrame.width - size.width) / 2 + screenFrame.origin.x
                let y = screenFrame.maxY - size.height - 40
                panel.setFrame(
                    NSRect(x: x, y: y, width: size.width, height: size.height),
                    display: true,
                    animate: true
                )
            }
            panel.makeKeyAndOrderFront(nil)

        case .full:
            // Hide floating pill, show main window with traffic lights
            floatingPanel?.orderOut(nil)
            showMainWindow()
        }
    }

    func showMainWindow() {
        if mainWindow == nil {
            // Create REGULAR NSWindow (NOT panel) - proper app window
            guard let screen = NSScreen.main else { return }
            let screenFrame = screen.visibleFrame
            let x = (screenFrame.width - fullSize.width) / 2 + screenFrame.origin.x
            let y = (screenFrame.height - fullSize.height) / 2 + screenFrame.origin.y

            // Regular NSWindow with traffic lights
            let window = NSWindow(
                contentRect: NSRect(x: x, y: y, width: fullSize.width, height: fullSize.height),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )

            window.title = "BrainPhArt"

            // Same content view
            let contentView = ContentView()
                .environmentObject(appState)

            let hostingView = NSHostingView(rootView: contentView)
            hostingView.autoresizingMask = [.width, .height]
            window.contentView = hostingView

            // Normal window behavior (not floating)
            window.level = .normal
            window.collectionBehavior = [.managed, .fullScreenPrimary]
            window.isOpaque = true
            window.backgroundColor = NSColor.windowBackgroundColor
            window.isReleasedWhenClosed = false

            mainWindow = window
        }

        // Activate app and make window key
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow?.makeMain()

        // Force first responder to the window's content
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.mainWindow?.makeFirstResponder(self?.mainWindow?.contentView)
        }
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
        // Ctrl+Shift+Space - Toggle recording via floating panel
        let hasCtrl = modifiers.contains(.control)
        let hasShift = modifiers.contains(.shift)
        let isSpace = keyCode == 49

        if hasCtrl && hasShift && isSpace {
            print("🎤 Hotkey triggered: Ctrl+Shift+Space")

            // CRITICAL: Save focused app BEFORE we take focus
            // This allows us to restore focus and paste into the original app after transcription
            AppState.shared.saveFocusedApp()

            // ALWAYS switch to floating mode when using hotkey
            // This is the dictation workflow - quick record, transcribe, paste
            if let delegate = NSApp.delegate as? AppDelegate {
                // Switch to medium floating mode for dictation
                AppState.shared.windowMode = .medium

                // Create floating panel if needed (updateWindowForMode will handle this)
                // But also ensure it's visible
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    delegate.floatingPanel?.orderFrontRegardless()
                }
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
    static let focusChatInput = Notification.Name("focusChatInput")
    static let transcriptionReady = Notification.Name("transcriptionReady")  // Posted when transcript is ready to paste
}
