import Foundation

/// `/persona/personas` row. Field names are the wire names.
public struct Persona: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var slug: String
    public var name: String
    public var description: String?
    public var visibility: String
    public var model: String?
    public var serviceId: String?
    public var appId: String?
    public var avatarAttachmentId: String?
    public var modelPrompt: String
    public var voice: String?
    public var character: String?
    public var examples: String?
    public var cannedChat: JSONValue?
    public var chatStatus: JSONValue?
    public var createdAt: String?
    public var updatedAt: String?
    public var ownedEcosystemId: String?
    public var corpusEcosystemId: String?

    public init(
        id: String, slug: String, name: String, description: String?, visibility: String, model: String?,
        serviceId: String?, appId: String?, avatarAttachmentId: String?, modelPrompt: String, voice: String?,
        character: String?, examples: String?, cannedChat: JSONValue?, chatStatus: JSONValue?,
        createdAt: String?, updatedAt: String?, ownedEcosystemId: String?, corpusEcosystemId: String?
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.description = description
        self.visibility = visibility
        self.model = model
        self.serviceId = serviceId
        self.appId = appId
        self.avatarAttachmentId = avatarAttachmentId
        self.modelPrompt = modelPrompt
        self.voice = voice
        self.character = character
        self.examples = examples
        self.cannedChat = cannedChat
        self.chatStatus = chatStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ownedEcosystemId = ownedEcosystemId
        self.corpusEcosystemId = corpusEcosystemId
    }

    /// The editable subset, as the web's `personaToBody(draft)` produces it.
    public var body: PersonaBody {
        PersonaBody(
            slug: slug, name: name, description: description, modelPrompt: modelPrompt, voice: voice,
            character: character, examples: examples, avatarAttachmentId: avatarAttachmentId, serviceId: serviceId,
            model: model, visibility: visibility, cannedChat: cannedChat, chatStatus: chatStatus
        )
    }
}

/// `POST /persona/personas` and `PUT /persona/personas/{id}` body.
public struct PersonaBody: Codable, Sendable, Equatable {
    public var slug: String
    public var name: String
    public var description: String?
    public var modelPrompt: String
    public var voice: String?
    public var character: String?
    public var examples: String?
    public var avatarAttachmentId: String?
    public var serviceId: String?
    public var model: String?
    public var visibility: String
    public var cannedChat: JSONValue?
    public var chatStatus: JSONValue?

    public init(
        slug: String, name: String, description: String? = nil, modelPrompt: String, voice: String? = nil,
        character: String? = nil, examples: String? = nil, avatarAttachmentId: String? = nil,
        serviceId: String? = nil, model: String? = nil, visibility: String, cannedChat: JSONValue? = nil,
        chatStatus: JSONValue? = nil
    ) {
        self.slug = slug
        self.name = name
        self.description = description
        self.modelPrompt = modelPrompt
        self.voice = voice
        self.character = character
        self.examples = examples
        self.avatarAttachmentId = avatarAttachmentId
        self.serviceId = serviceId
        self.model = model
        self.visibility = visibility
        self.cannedChat = cannedChat
        self.chatStatus = chatStatus
    }
}

/// `/persona/services` row (the subset the LLM Settings facet needs).
public struct PersonaService: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var providerKind: String
    public var baseUrl: String
    public var connectStatus: String
    public var models: [PersonaServiceModel]

    public init(
        id: String, name: String, providerKind: String, baseUrl: String, connectStatus: String,
        models: [PersonaServiceModel]
    ) {
        self.id = id
        self.name = name
        self.providerKind = providerKind
        self.baseUrl = baseUrl
        self.connectStatus = connectStatus
        self.models = models
    }
}

public struct PersonaServiceModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String?
    public init(id: String, displayName: String?) {
        self.id = id
        self.displayName = displayName
    }
}
