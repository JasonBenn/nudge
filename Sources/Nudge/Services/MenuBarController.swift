import AppKit
import Observation

/// Owns the NSStatusItem and NSMenu. Instant to open — pure AppKit, no SwiftUI overhead.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    // Kept as weak references so MenuBarController doesn't own the app's objects.
    weak var coordinator: CheckInCoordinator?
    weak var detector: DistractionDetector?

    // Animation timer for the icon while Claude is generating.
    private static let eyeFrames = ["eye", "eye.fill", "eye.circle", "eye.circle.fill", "eye.fill", "eye"]
    private var animationTimer: Timer?
    private var animationFrame = 0

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        setIcon("eye", tint: .labelColor)
        // Seed with a placeholder so NSMenu is never empty — AppKit won't call
        // menuWillOpen (and thus won't show anything) for a completely empty menu.
        rebuildMenu()
    }

    // MARK: - Icon

    func startIconAnimation() {
        animationFrame = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.animationFrame += 1
                let name = Self.eyeFrames[self.animationFrame % Self.eyeFrames.count]
                self.setIcon(name, tint: .systemPurple)
            }
        }
    }

    func stopIconAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        setIcon("eye", tint: .labelColor)
    }

    private func setIcon(_ name: String, tint: NSColor) {
        guard let button = statusItem.button else { return }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.isTemplate = (tint == .labelColor)   // template = adapts to light/dark
        button.image = img
        button.contentTintColor = (tint == .labelColor) ? nil : tint
    }

    // MARK: - NSMenuDelegate

    /// Called just before the menu is shown — rebuild items fresh each time. Instant.
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        let t0 = Date()
        print("[Nudge] menuWillOpen start \(t0.timeIntervalSince1970)")
        MainActor.assumeIsolated {
            rebuildMenu()
        }
        print("[Nudge] menuWillOpen done  \(Date().timeIntervalSince(t0) * 1000)ms elapsed")
    }

    private func rebuildMenu() {
        let r0 = Date()
        menu.removeAllItems()
        let r1 = Date()
        let isPaused = detector?.isPaused ?? false
        let r2 = Date()
        let hasActiveCheckIn = coordinator?.hasActiveCheckIn ?? false
        let r3 = Date()
        print("[Nudge] rebuildMenu breakdown: removeAll=\(r1.timeIntervalSince(r0)*1000)ms isPaused=\(r2.timeIntervalSince(r1)*1000)ms hasActiveCheckIn=\(r3.timeIntervalSince(r2)*1000)ms")

        menu.addItem(withTitle: isPaused ? "Status: Paused" : "Status: Watching",
                     action: nil, keyEquivalent: "")

        if hasActiveCheckIn {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Show Check-in",
                         action: #selector(showCheckIn), keyEquivalent: "")
                .target = self
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: isPaused ? "Resume" : "Pause",
                     action: #selector(togglePause), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Test Nudge",
                     action: #selector(testNudge), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Run Latency Test",
                     action: #selector(runLatencyTest), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Nudge",
                     action: #selector(quit), keyEquivalent: "")
            .target = self
    }

    // MARK: - Actions

    @objc private func showCheckIn()    { coordinator?.refocusPanel() }
    @objc private func togglePause()    { detector?.isPaused.toggle() }
    @objc private func testNudge()      { coordinator?.handleDistraction(url: "https://x.com", title: "X / Twitter") }
    @objc private func runLatencyTest() { coordinator?.runLatencyTest() }
    @objc private func quit()           { NSApplication.shared.terminate(nil) }
}
