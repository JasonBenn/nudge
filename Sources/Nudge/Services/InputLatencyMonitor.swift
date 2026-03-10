import AppKit
import QuartzCore

/// Measures text input latency: time from text injection → AppKit layout() call on the hosting view.
///
/// Theory being tested: the wrapper-NSView + auto-layout setup caused layout() to be called
/// many times per keystroke (cascade), producing visible input lag. After removing the wrapper,
/// layout() should be called 0–1 times per keystroke with very low latency.
@MainActor
final class InputLatencyMonitor {
    static let shared = InputLatencyMonitor()

    private(set) var lastKeystrokeTime: CFAbsoluteTime?
    private var latencies: [Double] = []       // ms, keystroke→layout
    private var layoutCallsPerKeystroke: [Int] = []
    private(set) var layoutCallsThisKeystroke = 0
    private var keystrokeIndex = 0

    func reset() {
        latencies = []
        layoutCallsPerKeystroke = []
        layoutCallsThisKeystroke = 0
        lastKeystrokeTime = nil
        keystrokeIndex = 0
    }

    /// Called by InstrumentedHostingView on every layout() pass.
    func recordLayout() {
        layoutCallsThisKeystroke += 1
        guard let t0 = lastKeystrokeTime else { return }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        // First layout call after the keystroke = perceived latency
        latencies.append(ms)
        layoutCallsPerKeystroke.append(layoutCallsThisKeystroke)
        print("[Latency] keystroke \(latencies.count): \(String(format: "%.1f", ms))ms "
              + "(\(layoutCallsThisKeystroke) layout call(s))")
        lastKeystrokeTime = nil   // don't double-count
    }

    func printSummary() {
        guard !latencies.isEmpty else { print("[Latency] No measurements recorded"); return }
        let avg = latencies.reduce(0, +) / Double(latencies.count)
        let max = latencies.max() ?? 0
        let min = latencies.min() ?? 0
        let avgLayouts = Double(layoutCallsPerKeystroke.reduce(0, +)) / Double(layoutCallsPerKeystroke.count)
        print("""
[Latency] ── Summary (\(latencies.count) keystrokes) ──────────────────
[Latency]   avg latency  : \(String(format: "%.1f", avg))ms
[Latency]   min / max    : \(String(format: "%.1f", min))ms / \(String(format: "%.1f", max))ms
[Latency]   avg layouts  : \(String(format: "%.1f", avgLayouts)) per keystroke
[Latency]   cascade?     : \(avgLayouts > 2 ? "⚠️  YES — layout cascade confirmed" : "✅  NO — layout is clean")
[Latency]   verdict      : \(avg < 16 ? "✅  FAST (<16ms, under one frame)" : avg < 50 ? "⚠️  MARGINAL (\(String(format: "%.0f", avg))ms)" : "🔴  SLOW (\(String(format: "%.0f", avg))ms) — noticeably laggy")
[Latency] ────────────────────────────────────────────────────────────
""")
    }

    // MARK: - Programmatic test

    /// Shows the test panel, injects 13 characters one by one, and reports per-keystroke latency.
    func runTest(panel: FloatingPanel) {
        reset()
        Task { @MainActor in
            // Wait for SwiftUI to render the view and focus the TextField
            try? await Task.sleep(for: .seconds(2.0))

            guard let textView = findTextInput(in: panel) else {
                print("[Latency] ⚠️  Could not find a text input in the panel — is it showing?")
                print("[Latency]     firstResponder = \(String(describing: panel.firstResponder))")
                // Walk view hierarchy for debugging
                if let cv = panel.contentView { printResponderChain(cv) }
                return
            }
            print("[Latency] Found text input: \(type(of: textView)) — starting test")

            let chars = Array("hello nudge!!")
            for ch in chars {
                try? await Task.sleep(for: .milliseconds(200))
                // Record keystroke time THEN inject — layout() fires synchronously during layout pass
                lastKeystrokeTime = CFAbsoluteTimeGetCurrent()
                layoutCallsThisKeystroke = 0
                textView.insertText(String(ch),
                                    replacementRange: NSRange(location: NSNotFound, length: 0))
                // Give the runloop one cycle to process the layout
                try? await Task.sleep(for: .milliseconds(50))
                // If no layout was recorded yet, flush it now
                if lastKeystrokeTime != nil {
                    let ms = (CFAbsoluteTimeGetCurrent() - lastKeystrokeTime!) * 1000
                    latencies.append(ms)
                    layoutCallsPerKeystroke.append(layoutCallsThisKeystroke)
                    print("[Latency] keystroke \(latencies.count): \(String(format: "%.1f", ms))ms "
                          + "(\(layoutCallsThisKeystroke) layout calls — no layout triggered?)")
                    lastKeystrokeTime = nil
                }
            }

            try? await Task.sleep(for: .milliseconds(300))
            printSummary()
        }
    }

    // MARK: - Helpers

    /// Walk the panel to find the focused text input (NSTextField or NSTextView).
    private func findTextInput(in panel: NSPanel) -> NSTextInputClient? {
        // Check firstResponder first
        if let fr = panel.firstResponder as? NSTextInputClient { return fr }
        if let fr = panel.firstResponder as? NSTextView { return fr }
        // Otherwise walk the content view tree
        if let cv = panel.contentView {
            return firstTextInput(in: cv)
        }
        return nil
    }

    private func firstTextInput(in view: NSView) -> NSTextInputClient? {
        if let tf = view as? NSTextField, let ed = tf.currentEditor() as? NSTextInputClient { return ed }
        if let tv = view as? NSTextView  { return tv }
        for sub in view.subviews {
            if let found = firstTextInput(in: sub) { return found }
        }
        return nil
    }

    private func printResponderChain(_ view: NSView, depth: Int = 0) {
        let prefix = String(repeating: "  ", count: depth)
        print("[Latency]   \(prefix)\(type(of: view))")
        for sub in view.subviews { printResponderChain(sub, depth: depth + 1) }
    }
}
