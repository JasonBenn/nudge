import XCTest
import SwiftUI
@testable import Nudge

final class CheckInCoordinatorTests: XCTestCase {

    // Verifies that the default contextLoader hops off the main thread before doing its
    // blocking I/O (HTTP to ActivityWatch + file reads).
    //
    // The old spin-loop "responsiveness" test gave a false green in the SPM runner because
    // SPM backs @MainActor with a preemptable thread pool rather than the real UI main
    // thread.  Checking Thread.isMainThread is the reliable proxy: in a live macOS app
    // @MainActor == UI main thread, so running blocking I/O there freezes the menubar.
    func testContextLoaderRunsOffMainThread() async throws {
        actor Spy {
            var ranOnMainThread: Bool?
            func record(_ v: Bool) { ranOnMainThread = v }
        }
        let spy = Spy()
        let (stream, continuation) = AsyncStream<Void>.makeStream()

        let coordinator = await MainActor.run {
            CheckInCoordinator(
                panel: TestPanel(),
                contextLoader: { _, _, _ in
                    await spy.record(Thread.isMainThread)
                    continuation.yield()
                    return "context"
                },
                generateCheckInAction: { _ in
                    CheckInData(
                        nudge: "Notice the tab switch.",
                        trigger_options: ["Bored", "Avoiding work", "Tired", "Restless", "Curious"],
                        replacement_options: ["Return to task", "Stretch", "Take a walk", "Journal", "Hydrate"]
                    )
                }
            )
        }

        await MainActor.run {
            coordinator.handleDistraction(url: "https://x.com", title: "X")
        }

        // Wait until the contextLoader has been called.
        for await _ in stream { break }

        let ranOnMain = await spy.ranOnMainThread
        XCTAssertEqual(
            ranOnMain, false,
            "contextLoader must not run on the main thread — blocking I/O there freezes the menubar"
        )
    }
}

@MainActor
final class FloatingPanelTests: XCTestCase {
    func testFloatingPanelSupportsTextInput() {
        let panel = FloatingPanel()

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
        XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel))
    }
}

@MainActor
private final class TestPanel: Paneling {
    var isVisible = false

    func show(view: AnyView) {
        isVisible = true
    }

    func makeKeyAndOrderFront(_ sender: Any?) {}

    func dismiss() {
        isVisible = false
    }
}
