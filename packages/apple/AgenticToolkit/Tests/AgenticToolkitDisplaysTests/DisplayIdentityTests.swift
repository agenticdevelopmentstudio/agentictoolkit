import CoreGraphics
import Foundation
import Testing
@testable import AgenticToolkitDisplays

@MainActor @Suite struct DisplayIdentityTests {
    @Test func keyPrefersUUID() {
        let id = DisplayIdentity(uuid: "ABC", vendor: 1, model: 2, serial: 3)
        #expect(id.key == "ABC")
    }

    @Test func keyFallsBackToVendorModelSerial() {
        let id = DisplayIdentity(uuid: nil, vendor: 1, model: 2, serial: 3)
        #expect(id.key == "1:2:3")
    }

    @Test func equalityAndHashFollowKey() {
        let lhs = DisplayIdentity(uuid: "ABC", vendor: 1, model: 2, serial: 3)
        let rhs = DisplayIdentity(uuid: "ABC", vendor: 9, model: 9, serial: 9)
        #expect(lhs == rhs)
        #expect(Set([lhs, rhs]).count == 1)
    }

    @Test func codableRoundTrip() throws {
        let id = DisplayIdentity(uuid: nil, vendor: 4, model: 5, serial: 6)
        let data = try JSONEncoder().encode(id)
        #expect(try JSONDecoder().decode(DisplayIdentity.self, from: data) == id)
    }

    @Test func displaySetIsOrderIndependent() {
        let first = DisplayIdentity(uuid: "B", vendor: 0, model: 0, serial: 0)
        let second = DisplayIdentity(uuid: "A", vendor: 0, model: 0, serial: 0)
        #expect(DisplaySet([first, second]).id == DisplaySet([second, first]).id)
        #expect(DisplaySet([first, second]).id == "A+B")
    }

    @Test func displaySetKeepsTwoIndistinguishableDisplays() {
        let twin = DisplayIdentity(uuid: nil, vendor: 7, model: 7, serial: 0)
        let set = DisplaySet([twin, twin])
        #expect(set.members.count == 2)
        #expect(set.id == "7:7:0+7:7:0")
    }

    @Test func menuLabelUsesDiagonal() {
        let display = FakeDisplaySystem.makeDisplay(
            id: 1, uuid: "X", bounds: CGRect(x: 0, y: 0, width: 3840, height: 2160),
            physicalSize: CGSize(width: 597, height: 336)
        )
        #expect(display.diagonalInches.map { Int($0.rounded()) } == 27)
        #expect(display.menuLabel == "27\" External")
    }
}
