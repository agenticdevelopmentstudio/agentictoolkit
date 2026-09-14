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
