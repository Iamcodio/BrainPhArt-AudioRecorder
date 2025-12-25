import Cocoa

/// FloatingPanel - Always-on-top window that appears in full-screen Spaces
///
/// What this does:
/// - Creates a special window that floats above everything else
/// - Stays visible even in full-screen apps (like Super Whisper)
/// - Appears on all desktop Spaces (Desktop 1, 2, 3, etc.)
/// - Doesn't hide when you click other apps

class FloatingPanel: NSPanel {

    // MARK: - Initialization

    init(
        contentRect: NSRect,
        backing: NSWindow.BackingStoreType = .buffered,
        defer flag: Bool = false
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .nonactivatingPanel,  // Doesn't steal focus from other apps
                .titled,              // Has a title bar
                .closable,            // Has close button
                .fullSizeContentView  // Content extends under title bar
            ],
            backing: backing,
            defer: flag
        )

        configureFloatingBehavior()
        configureAppearance()
    }

    // MARK: - Configuration

    private func configureFloatingBehavior() {
        // 1. Make it a floating panel
        self.isFloatingPanel = true

        // 2. Set window level to float above normal windows
        self.level = .floating

        // 3. THE KEY: Allow in full-screen Spaces
        self.collectionBehavior.insert(.fullScreenAuxiliary)

        // 4. Show on all desktop Spaces
        self.collectionBehavior.insert(.canJoinAllSpaces)

        // 5. Don't hide when user clicks other apps
        self.hidesOnDeactivate = false

        // 6. Allow window to be moved by clicking anywhere
        self.isMovableByWindowBackground = true
    }

    private func configureAppearance() {
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.backgroundColor = NSColor.windowBackgroundColor
        self.isOpaque = false
    }

    // MARK: - Behavior Overrides

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}
