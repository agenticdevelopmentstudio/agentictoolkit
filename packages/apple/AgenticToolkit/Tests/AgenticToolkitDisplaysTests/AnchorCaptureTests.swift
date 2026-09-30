import CoreGraphics
import Testing
@testable import AgenticToolkitDisplays

@Suite struct AnchorCaptureTests {
    let odyssey = DisplayIdentity(uuid: "ODYSSEY", vendor: 0, model: 0, serial: 0)
    let lgID = DisplayIdentity(uuid: "LG", vendor: 0, model: 0, serial: 0)
    let rtk = DisplayIdentity(uuid: "RTK", vendor: 0, model: 0, serial: 0)

    var desk: [DisplayIdentity: CGRect] {
        [odyssey: CGRect(x: 0, y: 0, width: 7680, height: 2160),
         lgID: CGRect(x: -3840, y: -1080, width: 3840, height: 2160),
         rtk: CGRect(x: 1173, y: 2160, width: 2560, height: 1440)]
    }

    @Test func capturesTheUsersDeskWithNaturalAnchors() throws {
        let anchors = try AnchorCapture.capture(main: odyssey, bounds: desk)
        #expect(anchors[lgID] == Anchor(parent: .local(odyssey), edge: .left, parentFraction: 0.5, childFraction: 1.0))
        let rtkAnchor = try #require(anchors[rtk])
        #expect(rtkAnchor.edge == .bottom)
        #expect(rtkAnchor.childFraction == 1.0)
        #expect(abs(rtkAnchor.parentFraction - 3733.0 / 7680.0) < 1e-9)
        #expect(anchors[odyssey] == nil)
    }

    @Test func roundTripsThroughTheSolver() throws {
        let anchors = try AnchorCapture.capture(main: odyssey, bounds: desk)
        let origins = try AnchorSolver.solve(main: odyssey, anchors: anchors, sizes: desk.mapValues(\.size))
        #expect(origins == desk.mapValues(\.origin))
    }

    @Test func snapsNearCentre() throws {
        var frames = desk
        frames[lgID] = CGRect(x: -3840, y: -1085, width: 3840, height: 2160)   // 5 pt off = 0.23% of 2160
        let anchors = try AnchorCapture.capture(main: odyssey, bounds: frames)
        #expect(anchors[lgID]?.parentFraction == 0.5)
    }

    /// A 5 pt contact is within the snap tolerance of the corner; snapping
    /// would leave a corner-only touch the solver rejects, so capture keeps
    /// the exact fractions and the layout still solves to the same origins.
    @Test(arguments: [CGFloat(2155), -2155])
    func shortContactIsNotSnappedAway(lgY: CGFloat) throws {
        var frames = desk
        frames[lgID] = CGRect(x: -3840, y: lgY, width: 3840, height: 2160)
        let anchors = try AnchorCapture.capture(main: odyssey, bounds: frames)
        let anchor = try #require(anchors[lgID])
        #expect(anchor.edge == .left)
        #expect(anchor.parentFraction != 0 && anchor.parentFraction != 1)
        let origins = try AnchorSolver.solve(main: odyssey, anchors: anchors, sizes: frames.mapValues(\.size))
        #expect(origins == frames.mapValues(\.origin))
    }

    @Test func prefersLongestContact() throws {
        let alpha = DisplayIdentity(uuid: "A", vendor: 0, model: 0, serial: 0)
        let frames: [DisplayIdentity: CGRect] = [
            odyssey: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            lgID: CGRect(x: 1000, y: 0, width: 1000, height: 100),
            alpha: CGRect(x: 1000, y: 100, width: 500, height: 900)          // touches odyssey (900) and lgID (500)
        ]
        let anchors = try AnchorCapture.capture(main: odyssey, bounds: frames)
        #expect(anchors[alpha]?.parent == .local(odyssey))
        #expect(anchors[alpha]?.edge == .right)
    }

    @Test func detachedDisplayThrows() {
        var frames = desk
        frames[rtk] = CGRect(x: 20000, y: 20000, width: 100, height: 100)
        #expect(throws: AnchorCaptureError.detached(rtk)) { try AnchorCapture.capture(main: odyssey, bounds: frames) }
    }

    @Test func missingMainThrows() {
        #expect(throws: AnchorCaptureError.mainMissing) {
            try AnchorCapture.capture(main: odyssey, bounds: [lgID: .zero])
        }
    }
}
