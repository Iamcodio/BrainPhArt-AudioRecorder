import SwiftUI
import Cocoa

/// FloatingWindowManager - Bridges SwiftUI and NSPanel
///
/// Creates and manages the floating panel that stays on top

@MainActor
class FloatingWindowManager: ObservableObject {

    // MARK: - Properties

    private var floatingPanel: FloatingPanel?
    @Published var isFloatingMode: Bool = true

    // Window sizes
    private let floatingSize = NSSize(width: 340, height: 100)
    private let expandedSize = NSSize(width: 1200, height: 800)

    // MARK: - Public Methods

    func showFloatingWindow<Content: View>(@ViewBuilder content: () -> Content) {
        if let existingPanel = floatingPanel {
            existingPanel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = createFloatingPanel()

        let hostingView = NSHostingView(rootView: content())
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView = hostingView
        panel.makeKeyAndOrderFront(nil)

        self.floatingPanel = panel
    }

    func updateWindowSize(floating: Bool) {
        guard let panel = floatingPanel else { return }

        isFloatingMode = floating

        if floating {
            // Switch to floating mode
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
            // Switch to expanded mode
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
    }

    func hideFloatingWindow() {
        floatingPanel?.orderOut(nil)
    }

    func closeFloatingWindow() {
        floatingPanel?.close()
        floatingPanel = nil
    }

    // MARK: - Private Methods

    private func createFloatingPanel() -> FloatingPanel {
        guard let screen = NSScreen.main else {
            return FloatingPanel(
                contentRect: NSRect(x: 100, y: 100, width: floatingSize.width, height: floatingSize.height)
            )
        }

        let screenFrame = screen.visibleFrame
        let x = (screenFrame.width - floatingSize.width) / 2 + screenFrame.origin.x
        let y = screenFrame.maxY - floatingSize.height - 40

        return FloatingPanel(
            contentRect: NSRect(x: x, y: y, width: floatingSize.width, height: floatingSize.height)
        )
    }
}
