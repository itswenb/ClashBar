import AppKit
import XCTest
@testable import ClashBar

final class PanelGeometryTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testDropdownStartsBelowControlAndAlignsLeadingEdge() {
        let context = PanelAnchorContext(
            visibleFrame: self.visibleFrame,
            anchorFrameOnScreen: CGRect(x: 900, y: 800, width: 120, height: 20),
            hostWindowFrame: CGRect(x: 850, y: 300, width: 400, height: 570))
        let placement = context.belowAnchorPlacement(
            contentSize: CGSize(width: 240, height: 200),
            preferredWidth: nil,
            maximumHeight: nil,
            screenPadding: 6,
            verticalSpacing: 4)

        XCTAssertEqual(placement.frame, CGRect(x: 900, y: 596, width: 240, height: 200))
        XCTAssertNil(placement.attachmentSide)
    }

    func testDropdownClampsAtScreenEdgeAndScrollsWithinAvailableHeight() {
        let context = PanelAnchorContext(
            visibleFrame: self.visibleFrame,
            anchorFrameOnScreen: CGRect(x: 1390, y: 100, width: 30, height: 20),
            hostWindowFrame: nil)
        let placement = context.belowAnchorPlacement(
            contentSize: CGSize(width: 300, height: 500),
            preferredWidth: 240,
            maximumHeight: 300,
            screenPadding: 6,
            verticalSpacing: 4)

        XCTAssertEqual(placement.frame, CGRect(x: 1194, y: 6, width: 240, height: 90))
    }

    func testDropdownSupportsSecondaryScreenCoordinatesAndHeightLimit() {
        let context = PanelAnchorContext(
            visibleFrame: CGRect(x: -1440, y: -900, width: 1440, height: 900),
            anchorFrameOnScreen: CGRect(x: -1440, y: -100, width: 100, height: 20),
            hostWindowFrame: nil)
        let placement = context.belowAnchorPlacement(
            contentSize: CGSize(width: 2000, height: 500),
            preferredWidth: nil,
            maximumHeight: 100,
            screenPadding: 6,
            verticalSpacing: 4)

        XCTAssertEqual(placement.frame, CGRect(x: -1434, y: -216, width: 1428, height: 112))
    }

    func testSideMenusKeepExistingHostWindowAttachment() throws {
        let context = PanelAnchorContext(
            visibleFrame: self.visibleFrame,
            anchorFrameOnScreen: CGRect(x: 900, y: 800, width: 120, height: 20),
            hostWindowFrame: CGRect(x: 850, y: 300, width: 400, height: 570))
        let placement = try XCTUnwrap(context.sideAttachedPlacement(
            contentSize: CGSize(width: 160, height: 200),
            preferredWidth: nil,
            maximumHeight: nil,
            screenPadding: 6,
            edgeOverlap: 1))

        XCTAssertEqual(placement.attachmentSide, .right)
        XCTAssertEqual(placement.frame.minX, 1249)
    }
}
