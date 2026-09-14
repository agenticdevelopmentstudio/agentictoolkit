import Testing
@testable import AgenticToolkitMacOS

@Suite("OnceOnlyContinuation")
@MainActor
struct OnceOnlyContinuationTests {

    @Test("finish(value) delivers that value to the awaiting caller")
    func finishDeliversValue() async {
        let boxed: UncheckedSendableBox<Int?> = await withCheckedContinuation { continuation in
            let session = OnceOnlyContinuation<Int?>(continuation: continuation)
            session.finish(42)
        }
        #expect(boxed.value == 42)
    }

    @Test("finish(nil) delivers nil")
    func finishDeliversNil() async {
        let boxed: UncheckedSendableBox<Int?> = await withCheckedContinuation { continuation in
            let session = OnceOnlyContinuation<Int?>(continuation: continuation)
            session.finish(nil)
        }
        #expect(boxed.value == nil)
    }

    @Test("a second finish neither traps nor changes the delivered answer, and isFinished is true throughout")
    func secondFinishIsNoOp() async {
        var isFinishedBefore = true
        var isFinishedAfterFirst = false
        var isFinishedAfterSecond = false
        let boxed: UncheckedSendableBox<Int?> = await withCheckedContinuation { continuation in
            let session = OnceOnlyContinuation<Int?>(continuation: continuation)
            isFinishedBefore = session.isFinished
            session.finish(1)
            isFinishedAfterFirst = session.isFinished
            session.finish(2)
            isFinishedAfterSecond = session.isFinished
        }
        #expect(isFinishedBefore == false)
        #expect(isFinishedAfterFirst == true)
        #expect(isFinishedAfterSecond == true)
        #expect(boxed.value == 1)
    }
}
