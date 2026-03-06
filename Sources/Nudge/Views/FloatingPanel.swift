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
        hosting.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = NSView()
        wrapper.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: wrapper.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
        ])
        contentView = wrapper
        hostingView = hosting

        // Let SwiftUI determine the intrinsic size
        let fittingSize = hosting.fittingSize
        let newFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: max(fittingSize.width, 420),
            height: min(fittingSize.height, 700)
        )
        setFrame(newFrame, display: true)
        center()
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        orderOut(nil)
        hostingView = nil
        contentView = nil
    }
}
