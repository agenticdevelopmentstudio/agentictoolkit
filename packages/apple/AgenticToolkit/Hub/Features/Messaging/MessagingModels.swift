import Foundation

public enum MessagingChannel: String, Codable, CaseIterable, Sendable {
    case email, sms

    public var title: String { self == .email ? "Email" : "SMS" }
    public var providerName: String { self == .email ? "Postmark" : "Twilio" }
    public var providerLabel: String { "\(title) (\(providerName))" }
    public var systemImage: String { self == .email ? "envelope" : "message" }
}

public struct MessagingStatus: Codable, Hashable, Sendable {
    public var email: Bool
    public var sms: Bool
    public init(email: Bool, sms: Bool) { self.email = email; self.sms = sms }
    public func isConnected(_ channel: MessagingChannel) -> Bool { channel == .email ? email : sms }
}

public struct MessagingTemplate: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var subject: String
    public var htmlBody: String
    public var textBody: String
    public var smsBody: String?
    public var category: String?

    public init(
        id: String, name: String, subject: String, htmlBody: String, textBody: String,
        smsBody: String? = nil, category: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subject = subject
        self.htmlBody = htmlBody
        self.textBody = textBody
        self.smsBody = smsBody
        self.category = category
    }

    /// Placeholder names across the text body and SMS body (never the subject), in first-seen order.
    public var placeholders: [String] {
        MessagingTopic.placeholders(in: [textBody, smsBody ?? ""].joined(separator: "\n"))
    }
}

public struct MessagingLogEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var customerId: String
    public var ecosystemId: String
    public var channel: MessagingChannel
    public var recipient: String
    public var subject: String?
    public var body: String
    public var templateId: String?
    public var status: String
    public var providerId: String?
    public var errorMessage: String?
    public var sentBy: String?
    public var origin: String?
    public var createdAt: String?

    public init(
        id: String, customerId: String, ecosystemId: String, channel: MessagingChannel, recipient: String,
        subject: String? = nil, body: String, templateId: String? = nil, status: String, providerId: String? = nil,
        errorMessage: String? = nil, sentBy: String? = nil, origin: String? = nil, createdAt: String? = nil
    ) {
        self.id = id
        self.customerId = customerId
        self.ecosystemId = ecosystemId
        self.channel = channel
        self.recipient = recipient
        self.subject = subject
        self.body = body
        self.templateId = templateId
        self.status = status
        self.providerId = providerId
        self.errorMessage = errorMessage
        self.sentBy = sentBy
        self.origin = origin
        self.createdAt = createdAt
    }
}

public struct MessagingLogPage: Codable, Hashable, Sendable {
    public var items: [MessagingLogEntry]
    public var total: Int
    public var page: Int
    public var pageSize: Int
    public init(items: [MessagingLogEntry], total: Int, page: Int, pageSize: Int) {
        self.items = items
        self.total = total
        self.page = page
        self.pageSize = pageSize
    }
}

public struct MessagingSend: Codable, Hashable, Sendable {
    public var userId: String
    public var channel: MessagingChannel
    public var subject: String?
    public var body: String?
    public var templateId: String?
    public var templateVars: [String: String]?
    public var recipient: String?

    public init(
        userId: String, channel: MessagingChannel, subject: String? = nil, body: String? = nil,
        templateId: String? = nil, templateVars: [String: String]? = nil, recipient: String? = nil
    ) {
        self.userId = userId
        self.channel = channel
        self.subject = subject
        self.body = body
        self.templateId = templateId
        self.templateVars = templateVars
        self.recipient = recipient
    }
}

public struct MessagingSendResult: Codable, Hashable, Sendable {
    public var status: String
    public var providerId: String?
    public var error: String?
    public init(status: String, providerId: String? = nil, error: String? = nil) {
        self.status = status
        self.providerId = providerId
        self.error = error
    }
}

public protocol MessagingDataSource: AnyObject, Sendable {
    func status(ecosystemID: String) async throws -> MessagingStatus
    func templates() async throws -> [MessagingTemplate]
    func log(ecosystemID: String, page: Int, pageSize: Int) async throws -> MessagingLogPage
    func send(ecosystemID: String, _ message: MessagingSend) async throws -> MessagingSendResult
}
