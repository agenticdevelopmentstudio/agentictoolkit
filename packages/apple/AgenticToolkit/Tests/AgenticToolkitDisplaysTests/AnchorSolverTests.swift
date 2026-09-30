import CoreGraphics
import Foundation
import Testing
@testable import AgenticToolkitDisplays

@Suite struct AnchorSolverTests {
    let odyssey = DisplayIdentity(uuid: "ODYSSEY", vendor: 0, model: 0, serial: 0)
    let lgID = DisplayIdentity(uuid: "LG", vendor: 0, model: 0, serial: 0)
    let rtk = DisplayIdentity(uuid: "RTK", vendor: 0, model: 0, serial: 0)

    var sizes: [DisplayIdentity: CGSize] {
        [odyssey: CGSize(width: 7680, height: 2160),
         lgID: CGSize(width: 3840, height: 2160),
         rtk: CGSize(width: 2560, height: 1440)]
    }
    var deskAnchors: [DisplayIdentity: Anchor] {
        [lgID: Anchor(parent: .local(odyssey), edge: .left, parentFraction: 0.5, childFraction: 1.0),
         rtk: Anchor(parent: .local(odyssey), edge: .bottom, parentFraction: 3733.0 / 7680.0, childFraction: 1.0)]
    }

    @Test func solvesTheUsersDesk() throws {
        let origins = try AnchorSolver.solve(main: odyssey, anchors: deskAnchors, sizes: sizes)
        #expect(origins[odyssey] == .zero)
        #expect(origins[lgID] == CGPoint(x: -3840, y: -1080))   // LG's lower-right at Odyssey's vertical centre
        #expect(origins[rtk] == CGPoint(x: 1173, y: 2160))    // RTK's top-right on Odyssey's bottom edge
    }

    @Test func staysAnchoredWhenAResolutionChanges() throws {
        var resized = sizes
        resized[lgID] = CGSize(width: 2560, height: 1440)
        let origins = try AnchorSolver.solve(main: odyssey, anchors: deskAnchors, sizes: resized)
        #expect(origins[lgID] == CGPoint(x: -2560, y: -360))    // bottom still at y = 1080
    }

    @Test func eachEdgePlacesTheChildOnThatSide() {
        let parent = CGRect(x: 0, y: 0, width: 100, height: 50)
        let child = CGSize(width: 20, height: 10)
        func place(_ edge: DisplayEdge) -> CGPoint {
            let anchor = Anchor(parent: .local(odyssey), edge: edge, parentFraction: 0, childFraction: 0)
            return AnchorSolver.place(childSize: child, anchor: anchor, parent: parent)
        }
        #expect(place(.left) == CGPoint(x: -20, y: 0))
        #expect(place(.right) == CGPoint(x: 100, y: 0))
        #expect(place(.top) == CGPoint(x: 0, y: -10))
        #expect(place(.bottom) == CGPoint(x: 0, y: 50))
    }

    @Test func chainsThroughNonMainParents() throws {
        var anchors = deskAnchors
        anchors[rtk] = Anchor(parent: .local(lgID), edge: .top, parentFraction: 0, childFraction: 0)
        let origins = try AnchorSolver.solve(main: odyssey, anchors: anchors, sizes: sizes)
        #expect(origins[rtk] == CGPoint(x: -3840, y: -1080 - 1440))
    }

    @Test func mainAnchorIsIgnored() throws {
        var anchors = deskAnchors
        anchors[odyssey] = Anchor(parent: .local(lgID), edge: .right, parentFraction: 0, childFraction: 0)
        #expect(try AnchorSolver.solve(main: odyssey, anchors: anchors, sizes: sizes)[odyssey] == .zero)
    }

    @Test func errors() {
        #expect(throws: AnchorSolverError.mainNotConnected(odyssey)) {
            try AnchorSolver.solve(main: odyssey, anchors: [:], sizes: [lgID: CGSize(width: 1, height: 1)])
        }
        #expect(throws: AnchorSolverError.unanchored(rtk)) {
            try AnchorSolver.solve(main: odyssey, anchors: [lgID: deskAnchors[lgID]!], sizes: sizes)
        }
        let ghost = DisplayIdentity(uuid: "GHOST", vendor: 0, model: 0, serial: 0)
        var missing = deskAnchors
        missing[rtk] = Anchor(parent: .local(ghost), edge: .left, parentFraction: 0, childFraction: 0)
        #expect(throws: AnchorSolverError.missingParent(child: rtk, parent: .local(ghost))) {
            try AnchorSolver.solve(main: odyssey, anchors: missing, sizes: sizes)
        }
        var remoteParent = deskAnchors
        let remote = DisplayRef.remote(RemoteScreenID(device: "D", display: "S"))
        remoteParent[rtk] = Anchor(parent: remote, edge: .left, parentFraction: 0, childFraction: 0)
        #expect(throws: AnchorSolverError.missingParent(child: rtk, parent: remote)) {
            try AnchorSolver.solve(main: odyssey, anchors: remoteParent, sizes: sizes)
        }
        var cyclic = deskAnchors
        cyclic[lgID] = Anchor(parent: .local(rtk), edge: .left, parentFraction: 0, childFraction: 0)
        cyclic[rtk] = Anchor(parent: .local(lgID), edge: .left, parentFraction: 0, childFraction: 0)
        #expect(throws: AnchorSolverError.cycle([lgID, rtk])) {
            try AnchorSolver.solve(main: odyssey, anchors: cyclic, sizes: sizes)
        }
        var badFraction = deskAnchors
        badFraction[lgID] = Anchor(parent: .local(odyssey), edge: .left, parentFraction: 1.5, childFraction: 0)
        #expect(throws: AnchorSolverError.invalidFraction(lgID)) {
            try AnchorSolver.solve(main: odyssey, anchors: badFraction, sizes: sizes)
        }
        var overlapping = deskAnchors
        overlapping[rtk] = Anchor(parent: .local(odyssey), edge: .left, parentFraction: 0.5, childFraction: 1.0)
        #expect(throws: AnchorSolverError.overlap(lgID, rtk)) {
            try AnchorSolver.solve(main: odyssey, anchors: overlapping, sizes: sizes)
        }
    }

    @Test func cornerOnlyContactIsRejected() {
        var corner = deskAnchors
        corner[lgID] = Anchor(parent: .local(odyssey), edge: .left, parentFraction: 1, childFraction: 0)
        #expect(throws: AnchorSolverError.noContact(lgID)) {
            try AnchorSolver.solve(main: odyssey, anchors: corner, sizes: sizes)
        }
        var cornerBelow = deskAnchors
        cornerBelow[rtk] = Anchor(parent: .local(odyssey), edge: .bottom, parentFraction: 1, childFraction: 0)
        #expect(throws: AnchorSolverError.noContact(rtk)) {
            try AnchorSolver.solve(main: odyssey, anchors: cornerBelow, sizes: sizes)
        }
    }

    @Test func onePointOfContactIsEnough() throws {
        var sliver = deskAnchors
        sliver[lgID] = Anchor(parent: .local(odyssey), edge: .left, parentFraction: 0, childFraction: 2159.0 / 2160)
        let origins = try AnchorSolver.solve(main: odyssey, anchors: sliver, sizes: sizes)
        #expect(origins[lgID] == CGPoint(x: -3840, y: -2159))   // 1pt of the left edge shared
    }

    @Test func anchorCodableRoundTripIncludingRemote() throws {
        let anchor = Anchor(
            parent: .remote(RemoteScreenID(device: "D", display: "S")),
            edge: .top, parentFraction: 0.25, childFraction: 1
        )
        let data = try JSONEncoder().encode(anchor)
        #expect(try JSONDecoder().decode(Anchor.self, from: data) == anchor)
    }
}
