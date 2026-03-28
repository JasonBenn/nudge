import XCTest
import SwiftUI
@testable import Nudge

@MainActor
final class FloatingPanelTests: XCTestCase {
    func testFloatingPanelSupportsTextInput() {
        let panel = FloatingPanel()

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
        XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel))
    }
}
