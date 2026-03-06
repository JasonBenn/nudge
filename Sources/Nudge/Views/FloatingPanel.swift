import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    private var hostingView: NSHostingView<AnyView>?

    init(contentRect: NSRect = NSRect(x: 0, y: 0, width: 420, height: 500)) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        center()
    }

    func show<Content: View>(_ view: Content) {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = contentRect(forFrameRect: frame)
        contentView = hosting
        hostingView = hosting
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        orderOut(nil)
        hostingView = nil
        contentView = nil
    }
}
