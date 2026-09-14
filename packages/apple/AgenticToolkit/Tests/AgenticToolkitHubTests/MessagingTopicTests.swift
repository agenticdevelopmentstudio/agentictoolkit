import AgenticToolkitHTDV
import XCTest
@testable import AgenticToolkitHub

final class FakeMessagingDataSource: MessagingDataSource, @unchecked Sendable {
    var status: MessagingStatus? = MessagingStatus(email: true, sms: false)
    var templates: [MessagingTemplate] = []
    var entries: [MessagingLogEntry] = []
    var sends: [MessagingSend] = []
    var result = MessagingSendResult(status: "sent", providerId: "pm-1", error: nil)
    var failure: Error?
    var statusFailure: Error?
    var logRequests: [(page: Int, pageSize: Int)] = []

    func status(ecosystemID: String) async throws -> MessagingStatus {
        if let statusFailure { throw statusFailure }
        guard let status else { throw HubError.unexpected("no status") }
        return status
    }
    func templates() async throws -> [MessagingTemplate] { if let failure { throw failure }; return templates }
    func log(ecosystemID: String, page: Int, pageSize: Int) async throws -> MessagingLogPage {
        if let failure { throw failure }
        logRequests.append((page, pageSize))
        return MessagingLogPage(items: entries, total: entries.count, page: page, pageSize: pageSize)
    }
    func send(ecosystemID: String, _ message: MessagingSend) async throws -> MessagingSendResult {
        if let failure { throw failure }
        sends.append(message)
        return result
    }
}

extension MessagingTemplate {
    static func fixture(
        id: String = "tpl-welcome", name: String = "Welcome", subject: String = "Welcome, {{name}}!",
        textBody: String = "Hi {{name}}, your code is {{code}}.", smsBody: String? = "{{name}}: {{code}}"
    ) -> MessagingTemplate {
        MessagingTemplate(
            id: id, name: name, subject: subject, htmlBody: "<p>\(textBody)</p>", textBody: textBody,
            smsBody: smsBody, category: "onboarding"
        )
    }
}

extension MessagingLogEntry {
    static func fixture(
        id: String = "m-1", channel: MessagingChannel = .email, status: String = "sent",
        errorMessage: String? = nil
    ) -> MessagingLogEntry {
        MessagingLogEntry(
            id: id, customerId: "c-jane", ecosystemId: "org.acme.shop", channel: channel,
            recipient: "jane@example.com", subject: "Your order", body: "Shipped today.", templateId: nil,
            status: status, providerId: "pm-1", errorMessage: errorMessage, sentBy: "owner@acme.test",
            origin: "ecosystem", createdAt: "2026-09-03T12:00:00.000Z"
        )
    }
}

@MainActor
final class MessagingTopicTests: XCTestCase {
    private var data = FakeMessagingDataSource()
    private lazy var topic = MessagingTopic(dataSource: data)
    private lazy var rail = SingleTopicRail(topic: topic)

    func testPlaceholdersAreOrderedAndUnique() {
        XCTAssertEqual(MessagingTopic.placeholders(in: "Hi {{name}}, {{ code }} and {{name}}"), ["name", "code"])
        XCTAssertEqual(MessagingTemplate.fixture().placeholders, ["name", "code"])
        XCTAssertEqual(MessagingTemplate.fixture(textBody: "Plain", smsBody: nil).placeholders, [])
    }

    func testStatusLineAndBanners() {
        XCTAssertEqual(
            MessagingTopic.statusLine(MessagingStatus(email: true, sms: false)),
            "Email: connected · SMS: not connected"
        )
        XCTAssertEqual(MessagingTopic.statusLine(nil), "Provider status unavailable")
        XCTAssertNil(MessagingTopic.bannerText(for: .email, status: MessagingStatus(email: true, sms: false)))
        XCTAssertEqual(
            MessagingTopic.bannerText(for: .sms, status: MessagingStatus(email: true, sms: false)),
            // swiftlint:disable:next line_length
            "SMS (Twilio) is not connected — sends on this channel will fail. Connect a Twilio integration on this product's Integrations tab."
        )
        XCTAssertEqual(
            MessagingTopic.bannerText(for: .email, status: nil),
            "Couldn't check whether Email (Postmark) is connected — sends on this channel may fail."
        )
    }

    func testTopicLevel() async throws {
        let level = try await rail.level([])
        XCTAssertEqual(level.id, "messaging:org.acme.shop")
        XCTAssertEqual(level.title, "Messaging")
        XCTAssertEqual(level.items.map(\.id), ["send", "log"])
        XCTAssertEqual(level.items[0].sublabel, "Email: connected · SMS: not connected")
        XCTAssertEqual(level.items[0].leadsTo, .detail)
        XCTAssertEqual(level.items[1].leadsTo, .list)
    }

    func testTopicLevelSurvivesStatusFailure() async throws {
        data.statusFailure = HubError.offline
        let level = try await rail.level([])
        XCTAssertEqual(level.items[0].sublabel, "Provider status unavailable")
    }

    func testSendFormFieldsAndBanners() async throws {
        data.templates = [.fixture()]
        let (detail, form) = try await rail.form(["send"])
        XCTAssertEqual(detail.id, "messaging:org.acme.shop:send")
        XCTAssertEqual(detail.title, "Send a message")
        XCTAssertEqual(
            form.state.spec.fields.map(\.key),
            ["smsStatus", "channel", "userId", "recipient", "templateId", "subject", "body", "templateVars"]
        )
        XCTAssertEqual(form.state.value(for: "channel"), .string("email"))
        XCTAssertEqual(form.state.value(for: "templateId"), .string(""))
        guard case .select(let content) = form.state.spec.fields[4] else { return XCTFail("expected select") }
        XCTAssertEqual(
            content.options, [MessagingTopic.freeformOption, FormSelectOption(value: "tpl-welcome", title: "Welcome")]
        )
        XCTAssertEqual(form.state.spec.actions.save?.title, "Send")
        XCTAssertNil(form.state.spec.actions.delete)
    }

    func testSendFreeformEmail() async throws {
        let (_, form) = try await rail.form(["send"])
        let firstSave = await form.state.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(form.state.errors["userId"], "Customer ID is required")
        form.state.set(.string("c-jane"), for: "userId")
        let secondSave = await form.state.save()
        XCTAssertFalse(secondSave)
        XCTAssertEqual(form.state.saveError, "Enter a subject.")
        form.state.set(.string("Your order"), for: "subject")
        let thirdSave = await form.state.save()
        XCTAssertFalse(thirdSave)
        XCTAssertEqual(form.state.saveError, "Enter a message body.")
        form.state.set(.string("Shipped today."), for: "body")
        let fourthSave = await form.state.save()
        XCTAssertTrue(fourthSave)
        XCTAssertEqual(data.sends, [MessagingSend(
            userId: "c-jane", channel: .email, subject: "Your order", body: "Shipped today.",
            templateId: nil, templateVars: nil, recipient: nil
        )])
    }

    func testSendSMSRequiresRecipientAndSkipsSubject() async throws {
        let (_, form) = try await rail.form(["send"])
        form.state.set(.string("sms"), for: "channel")
        form.state.set(.string("c-jane"), for: "userId")
        form.state.set(.string("Code 1234"), for: "body")
        let firstSave = await form.state.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(form.state.saveError, "A recipient phone number is required for SMS.")
        form.state.set(.string("+15555550123"), for: "recipient")
        let secondSave = await form.state.save()
        XCTAssertTrue(secondSave)
        XCTAssertEqual(data.sends.last, MessagingSend(
            userId: "c-jane", channel: .sms, subject: nil, body: "Code 1234",
            templateId: nil, templateVars: nil, recipient: "+15555550123"
        ))
    }

    func testSendTemplateRequiresEveryPlaceholder() async throws {
        data.templates = [.fixture()]
        let (_, form) = try await rail.form(["send"])
        form.state.set(.string("c-jane"), for: "userId")
        form.state.set(.string("tpl-welcome"), for: "templateId")
        let firstSave = await form.state.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(form.state.saveError, "Template needs a value for \"name\".")
        form.state.set(.string(#"{"name": "Jane"}"#), for: "templateVars")
        let secondSave = await form.state.save()
        XCTAssertFalse(secondSave)
        XCTAssertEqual(form.state.saveError, "Template needs a value for \"code\".")
        form.state.set(.string(#"{"name": "Jane", "code": "1234"}"#), for: "templateVars")
        let thirdSave = await form.state.save()
        XCTAssertTrue(thirdSave)
        XCTAssertEqual(data.sends.last, MessagingSend(
            userId: "c-jane", channel: .email, subject: nil, body: nil, templateId: "tpl-welcome",
            templateVars: ["name": "Jane", "code": "1234"], recipient: nil
        ))
    }

    func testSendTemplateVarsMustBeStringObject() async throws {
        data.templates = [.fixture()]
        let (_, form) = try await rail.form(["send"])
        form.state.set(.string("c-jane"), for: "userId")
        form.state.set(.string("tpl-welcome"), for: "templateId")
        form.state.set(.string(#"["a"]"#), for: "templateVars")
        let saved = await form.state.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(form.state.saveError, "Template variables must be a JSON object of strings.")
    }

    func testFailedSendReportsProviderError() async throws {
        data.result = MessagingSendResult(status: "failed", providerId: nil, error: "Recipient rejected")
        let (_, form) = try await rail.form(["send"])
        form.state.set(.string("c-jane"), for: "userId")
        form.state.set(.string("S"), for: "subject")
        form.state.set(.string("B"), for: "body")
        let firstSave = await form.state.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(form.state.saveError, "Recipient rejected")

        data.result = MessagingSendResult(status: "failed", providerId: nil, error: nil)
        let secondSave = await form.state.save()
        XCTAssertFalse(secondSave)
        XCTAssertEqual(form.state.saveError, MessagingTopic.sendFailedMessage)
    }

    func testLogLevelAndEntryDetail() async throws {
        data.entries = [
            .fixture(), .fixture(id: "m-2", channel: .sms, status: "failed", errorMessage: "Number unreachable")
        ]
        let level = try await rail.level(["log"])
        XCTAssertEqual(level.id, "messaging-log:org.acme.shop")
        XCTAssertEqual(level.title, "Message log")
        XCTAssertEqual(level.items.map(\.label), ["jane@example.com", "jane@example.com"])
        XCTAssertEqual(level.items[0].sublabel, "Email · sent · \(HubDates.display("2026-09-03T12:00:00.000Z"))")
        XCTAssertEqual(level.items[1].systemImage, "message")
        XCTAssertEqual(level.emptyMessage, "No messages sent yet.")
        XCTAssertNil(level.createAction)
        XCTAssertEqual(data.logRequests.last?.page, 1)
        XCTAssertEqual(data.logRequests.last?.pageSize, MessagingTopic.logPageSize)

        let (detail, form) = try await rail.form(["log", "m-2"])
        XCTAssertEqual(detail.id, "messaging-log-entry:m-2")
        XCTAssertEqual(detail.title, "Your order")
        XCTAssertEqual(
            form.state.spec.fields.map(\.key),
            ["channel", "recipient", "subject", "status", "error", "body", "sent"]
        )
        XCTAssertEqual(form.state.value(for: "error"), .string("Number unreachable"))
        XCTAssertNil(form.state.spec.actions.save)
        XCTAssertNil(form.state.spec.actions.delete)

        let (_, okForm) = try await rail.form(["log", "m-1"])
        XCTAssertEqual(
            okForm.state.spec.fields.map(\.key), ["channel", "recipient", "subject", "status", "body", "sent"]
        )
    }

    func testUnknownEntryIsEmpty() async throws {
        guard case .empty = try await rail.child(["log", "nope"]) else { return XCTFail("expected .empty") }
        guard case .empty = try await rail.child(["nope"]) else { return XCTFail("expected .empty") }
    }
}
