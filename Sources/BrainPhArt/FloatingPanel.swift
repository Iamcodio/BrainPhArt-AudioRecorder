import Cocoa

/// FloatingPanel - Always-on-top window that appears in full-screen Spaces
///
/// What this does:
/// - Creates a special window that floats above everything else
/// - Stays visible even in full-screen apps (like Super Whisper)
/// - Appears on all desktop Spaces (Desktop 1, 2, 3, etc.)
/// - Doesn't hide when you click other apps

class FloatingPanel: NSPanel {

    var showsTitleBar: Bool = false

    // MARK: - Initialization

    init(
        contentRect: NSRect,
        backing: NSWindow.BackingStoreType = .buffered,
        defer flag: Bool = false,
        showsTitleBar: Bool = false
    ) {
        self.showsTitleBar = showsTitleBar

        // Use different style mask based on whether we show title bar
        let styleMask: NSWindow.StyleMask = showsTitleBar
            ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            : [.nonactivatingPanel, .borderless, .fullSizeContentView]

        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
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
        if showsTitleBar {
            // Full window mode - show title bar with traffic lights
            self.titleVisibility = .hidden
            self.titlebarAppearsTransparent = true
            self.backgroundColor = NSColor.windowBackgroundColor
            self.isOpaque = true
            self.minSize = NSSize(width: 800, height: 500)  // Minimum size

            // Allow standard window behavior
            self.contentView?.wantsLayer = true
            self.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        } else {
            // Floating mode - borderless, clean look
            self.titleVisibility = .hidden
            self.titlebarAppearsTransparent = true
            self.backgroundColor = .clear
            self.isOpaque = false

            // Rounded corners for clean look
            self.contentView?.wantsLayer = true
            self.contentView?.layer?.cornerRadius = 12
            self.contentView?.layer?.masksToBounds = true
            self.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    // MARK: - Behavior Overrides

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}
