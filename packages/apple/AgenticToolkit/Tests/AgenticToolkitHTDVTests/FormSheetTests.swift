import Foundation
import XCTest
@testable import AgenticToolkitHTDV

/// Root level with one detail row, whose detail is a `FormViewController`. Counts `rootLevel()` calls so a
/// test can see the owning level being re-fetched. Self-contained: the controller calls it off the main
/// actor, so the counter is behind a lock.
private final class FormReloadDataSource: HTDVDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var rootCalls = 0
    /// Installed on every form this source vends, before the host gets to attach its own callbacks.
    private let nonisolatedPriorSaved: @Sendable () -> Void

    init(priorSaved: @escaping @Sendable () -> Void = {}) {
        self.nonisolatedPriorSaved = priorSaved
    }

    var rootLoadCount: Int { lock.withLock { rootCalls } }

    func rootLevel() async throws -> HTDVLevel {
        lock.withLock { rootCalls += 1 }
        return HTDVLevel(
            id: "root", title: "Root",
            items: [HTDVItem(id: "a", label: "Alpha", leadsTo: .detail)]
        )
    }

    func child(for path: [HTDVItem]) async throws -> HTDVChild {
        guard path.map(\.id) == ["a"] else { return .empty }
        let priorSaved = nonisolatedPriorSaved
        return .detail(HTDVDetail(id: "a", title: "Alpha") {
            let spec = FormSpec(
                sections: [FormSection(fields: [.text(FormTextField(key: "name", label: "Name"))])],
                actions: FormActions(
                    save: FormAction(id: "save", title: "Save") { _ in },
                    delete: FormDeleteAction(title: "Delete") {}
                )
            )
            let form = FormViewController(
                state: FormState(spec: spec, values: [:]), markdownEditing: PlainTextMarkdownEditing()
            )
            form.onSaved = priorSaved
            return form
        })
    }
}

/// Root level with ten detail rows, each vending a BRAND-NEW `FormViewController`. Navigating between
/// them tears the previous form down before the next is built, so the replacement can land on the freed
/// object's address — which is exactly what a host-side `Set<ObjectIdentifier>` of attached forms cannot
/// tell apart from the form it just released. Every one of these forms must get the host's level-reload
/// chained onto it.
private final class FreshFormDataSource: HTDVDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var rootCalls = 0

    static let itemIDs = (0..<10).map { "row-\($0)" }

    var rootLoadCount: Int { lock.withLock { rootCalls } }

    func rootLevel() async throws -> HTDVLevel {
        lock.withLock { rootCalls += 1 }
        return HTDVLevel(
            id: "root", title: "Root",
            items: Self.itemIDs.map { HTDVItem(id: $0, label: $0, leadsTo: .detail) }
        )
    }

    func child(for path: [HTDVItem]) async throws -> HTDVChild {
        guard let itemID = path.map(\.id).last, Self.itemIDs.contains(itemID) else { return .empty }
        return .detail(HTDVDetail(id: "detail-\(itemID)", title: itemID) {
            let spec = FormSpec(
                sections: [FormSection(fields: [.text(FormTextField(key: "name", label: "Name"))])],
                actions: FormActions(save: FormAction(id: "save", title: "Save") { _ in })
            )
            return FormViewController(
                state: FormState(spec: spec, values: [:]), markdownEditing: PlainTextMarkdownEditing()
            )
        })
    }
}

/// Root level with two detail rows ("a" and "b") that both resolve to the SAME `FormViewController`
/// instance, memoized on first creation. `HTDVDetail.make`'s contract does not require a fresh instance
/// per call, so a module is free to do this — and `attachFormCallbacks(to:)` must stay idempotent when it
/// does, rather than accumulating one chained closure per attach.
private final class MemoizedFormDataSource: HTDVDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var rootCalls = 0
    private var cachedForm: FormViewController?

    var rootLoadCount: Int { lock.withLock { rootCalls } }

    func rootLevel() async throws -> HTDVLevel {
        lock.withLock { rootCalls += 1 }
        return HTDVLevel(
            id: "root", title: "Root",
            items: [
                HTDVItem(id: "a", label: "Alpha", leadsTo: .detail),
                HTDVItem(id: "b", label: "Bravo", leadsTo: .detail)
            ]
        )
    }

    func child(for path: [HTDVItem]) async throws -> HTDVChild {
        guard let itemID = path.map(\.id).last, itemID == "a" || itemID == "b" else { return .empty }
        let detailID = itemID == "a" ? "d1" : "d2"
        return .detail(HTDVDetail(id: detailID, title: itemID) { [self] in self.memoizedForm() })
    }

    @MainActor private func memoizedForm() -> FormViewController {
        if let cachedForm { return cachedForm }
        let spec = FormSpec(
            sections: [FormSection(fields: [.text(FormTextField(key: "name", label: "Name"))])],
            actions: FormActions(save: FormAction(id: "save", title: "Save") { _ in })
        )
        let form = FormViewController(
            state: FormState(spec: spec, values: [:]), markdownEditing: PlainTextMarkdownEditing()
        )
        cachedForm = form
        return form
    }
}

@MainActor
final class FormSheetTests: XCTestCase {
    private func makeForm(saveSucceeds: Bool = true) -> FormViewController {
        let spec = FormSpec(
            sections: [FormSection(fields: [.text(FormTextField(key: "name", label: "Name", isRequired: true))])],
            actions: FormActions(save: FormAction(id: "save", title: "Create") { _ in
                if !saveSucceeds { throw NSError(domain: "t", code: 1) }
            })
        )
        let state = FormState(spec: spec, values: ["name": .string("Ada")])
        return FormViewController(state: state, markdownEditing: PlainTextMarkdownEditing())
    }

    /// Polls rather than sleeping a fixed amount: the reload runs in an unawaited `Task`, so the only
    /// thing the test can observe is the data source's call count changing.
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("condition was never met", file: file, line: line)
    }

    // MARK: FormSheetController

    func testSaveFinishesTrue() async {
        var finished: [Bool] = []
        let form = makeForm()
        let sheet = FormSheetController(title: "New thing", form: form) { finished.append($0) }
        _ = sheet.view
        XCTAssertTrue(sheet.children.contains(form))
        form.onSaved()
        XCTAssertEqual(finished, [true])
    }

    func testCancelFinishesFalseWhenClean() async {
        var finished: [Bool] = []
        let form = makeForm()
        form.state.markSaved()
        let sheet = FormSheetController(title: "New thing", form: form) { finished.append($0) }
        _ = sheet.view
        sheet.cancel()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(finished, [false])
    }

    func testFinishIsDeliveredOnce() async {
        var finished: [Bool] = []
        let form = makeForm()
        let sheet = FormSheetController(title: "New thing", form: form) { finished.append($0) }
        _ = sheet.view
        form.onSaved()
        form.onSaved()
        XCTAssertEqual(finished, [true])
    }

    func testTitleIsShown() {
        let form = makeForm()
        let sheet = FormSheetController(title: "New persona", form: form) { _ in }
        _ = sheet.view
        XCTAssertEqual(sheet.title, "New persona")
    }

    func testCancelButtonHasAccessibilityIdentifier() {
        let form = makeForm()
        let sheet = FormSheetController(title: "New thing", form: form) { _ in }
        _ = sheet.view
        XCTAssertEqual(sheet.cancelButton.accessibilityIdentifier(), "htdv.form.cancel")
    }

    /// `isConfirmingDiscard` is set synchronously before `cancel()` spawns its `Task`, so a second
    /// `cancel()` made before the first's confirmation resolves must see the guard already up and
    /// return immediately rather than prompting a second time.
    func testSecondCancelWhileConfirmingDiscardDoesNotPromptTwice() async throws {
        let form = makeForm()
        form.state.set(.string("Changed"), for: "name")
        var confirmCallCount = 0
        form.confirmDiscardHandler = {
            confirmCallCount += 1
            return true
        }
        var finished: [Bool] = []
        let sheet = FormSheetController(title: "New thing", form: form) { finished.append($0) }
        _ = sheet.view
        sheet.cancel()
        sheet.cancel()
        try await waitUntil { finished.count == 1 }
        XCTAssertEqual(confirmCallCount, 1, "a second cancel() must not open a second confirm prompt")
    }

    // MARK: Level reload after a form save/delete

    /// The host must stay alive for the whole test: `reloadOwningLevel()` captures it weakly, so a host
    /// released with the tuple that produced it would silently skip the reload under test.
    private func hostedForm(_ source: FormReloadDataSource) async -> HostedForm? {
        let controller = HTDVController(dataSource: source)
        let host = HTDVViewController(controller: controller)
        host.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        host.loadViewIfNeeded()
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        guard let form = host.detailViewController as? FormViewController else { return nil }
        return HostedForm(controller: controller, host: host, form: form)
    }

    func testFormSaveReloadsOwningLevel() async throws {
        let source = FormReloadDataSource()
        guard let hosted = await hostedForm(source) else { return XCTFail("expected a form detail") }
        let before = source.rootLoadCount
        hosted.form.onSaved()
        try await waitUntil { source.rootLoadCount == before + 1 }
        withExtendedLifetime(hosted) {}
    }

    func testFormDeleteReloadsOwningLevel() async throws {
        let source = FormReloadDataSource()
        guard let hosted = await hostedForm(source) else { return XCTFail("expected a form detail") }
        let before = source.rootLoadCount
        hosted.form.onDeleted()
        try await waitUntil { source.rootLoadCount == before + 1 }
        withExtendedLifetime(hosted) {}
    }

    /// The host chains onto the detail factory's own `onSaved` instead of replacing it, so a module that
    /// installs its own save handling keeps it.
    func testAttachKeepsTheDetailFactorysOwnSavedCallback() async throws {
        let counter = SavedCounter()
        let source = FormReloadDataSource(priorSaved: { counter.increment() })
        guard let hosted = await hostedForm(source) else { return XCTFail("expected a form detail") }
        let before = source.rootLoadCount
        hosted.form.onSaved()
        XCTAssertEqual(counter.value, 1, "the factory's own onSaved must still run")
        try await waitUntil { source.rootLoadCount == before + 1 }
        withExtendedLifetime(hosted) {}
    }

    /// Render detail A, tear it down, render detail B: B is a different object that may occupy A's
    /// freed address, and its `onSaved` must still reload the owning level. Ten hops, because address
    /// reuse is what makes the failure intermittent rather than absent.
    func testEachFreshFormReloadsTheOwningLevelAfterTheLastOneWasTornDown() async throws {
        let source = FreshFormDataSource()
        let controller = HTDVController(dataSource: source)
        let host = HTDVViewController(controller: controller)
        host.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        host.loadViewIfNeeded()
        await controller.load()

        for itemID in FreshFormDataSource.itemIDs {
            await controller.select(itemID: itemID, atLevel: 0)
            guard let form = host.detailViewController as? FormViewController else {
                return XCTFail("expected a form detail for \(itemID)")
            }
            let before = source.rootLoadCount
            form.onSaved()
            try await waitUntil { source.rootLoadCount > before }
        }
        withExtendedLifetime(host) {}
    }

    /// A memoized `FormViewController` returned for two different detail ids gets `attachFormCallbacks`
    /// called twice; the second attach must be a no-op, so one save still triggers exactly one reload.
    func testAttachingTheSameFormInstanceTwiceReloadsOnceOnSave() async throws {
        let source = MemoizedFormDataSource()
        let controller = HTDVController(dataSource: source)
        let host = HTDVViewController(controller: controller)
        host.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        host.loadViewIfNeeded()
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        guard let formA = host.detailViewController as? FormViewController else {
            return XCTFail("expected a form detail")
        }
        await controller.select(itemID: "b", atLevel: 0)
        guard let formB = host.detailViewController as? FormViewController else {
            return XCTFail("expected a form detail")
        }
        XCTAssertTrue(formA === formB, "the fixture memoizes one instance across both detail ids")

        let before = source.rootLoadCount
        formB.onSaved()
        try await waitUntil { source.rootLoadCount == before + 1 }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(source.rootLoadCount, before + 1, "the second attach must not add a second reload")
        withExtendedLifetime(host) {}
    }
}

/// Keeps the rail host, its controller and the hosted form alive together for the length of a test.
@MainActor
private final class HostedForm {
    let controller: HTDVController
    let host: HTDVViewController
    let form: FormViewController

    init(controller: HTDVController, host: HTDVViewController, form: FormViewController) {
        self.controller = controller
        self.host = host
        self.form = form
    }
}

/// Counts calls from the non-isolated `onSaved` closure the fake data source installs.
private final class SavedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
