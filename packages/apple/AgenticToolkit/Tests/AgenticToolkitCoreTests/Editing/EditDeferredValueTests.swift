import Testing
@testable import AgenticToolkitCore

/// Review V21-b: the edit-hold both in-place tables share.
@Suite("EditDeferredValue")
struct EditDeferredValueTests {

    @Test func anOfferWithNoEditInFlightAppliesAtOnce() {
        var held = EditDeferredValue<[Int]>()
        #expect(held.offer([1]) == [1])
        #expect(held.pending == nil)
    }

    @Test func offersDuringAnEditAreHeldAndOnlyTheNewestIsReleased() {
        var held = EditDeferredValue<[Int]>()
        held.beginEditing()
        #expect(held.offer([1]) == nil)
        #expect(held.offer([2]) == nil)
        #expect(held.isEditing)

        #expect(held.endEditing() == [2])
        #expect(!held.isEditing)
        #expect(held.endEditing() == nil, "a second end has nothing left to release")
    }

    @Test func anEditWithNoReloadReleasesNothing() {
        var held = EditDeferredValue<String>()
        held.beginEditing()
        #expect(held.endEditing() == nil)
        #expect(held.offer("next") == "next")
    }
}
