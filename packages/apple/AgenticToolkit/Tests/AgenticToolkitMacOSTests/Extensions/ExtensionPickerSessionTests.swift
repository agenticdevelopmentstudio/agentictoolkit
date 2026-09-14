import Testing
@testable import AgenticToolkitMacOS

@Suite("ExtensionPickerSession")
@MainActor
struct ExtensionPickerSessionTests {

    @Test("finish(value) delivers that value to the awaiting caller")
    func finishDeliversValue() async {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let session = ExtensionPickerSession<Int>(continuation: continuation)
            session.finish(42)
        }
        #expect(result == 42)
    }

    @Test("finish(nil) delivers nil")
    func finishDeliversNil() async {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let session = ExtensionPickerSession<Int>(continuation: continuation)
            session.finish(nil)
        }
        #expect(result == nil)
    }

    @Test("a second finish neither traps nor changes the delivered answer, and isFinished is true throughout")
    func secondFinishIsNoOp() async {
        var isFinishedBefore = true
        var isFinishedAfterFirst = false
        var isFinishedAfterSecond = false
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let session = ExtensionPickerSession<Int>(continuation: continuation)
            isFinishedBefore = session.isFinished
            session.finish(1)
            isFinishedAfterFirst = session.isFinished
            session.finish(2)
            isFinishedAfterSecond = session.isFinished
        }
        #expect(isFinishedBefore == false)
        #expect(isFinishedAfterFirst == true)
        #expect(isFinishedAfterSecond == true)
        #expect(result == 1)
    }
}
