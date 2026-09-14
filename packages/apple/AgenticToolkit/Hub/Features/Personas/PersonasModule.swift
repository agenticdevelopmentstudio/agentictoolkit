import AgenticToolkitHTDV
import Foundation

public struct PersonaFacet: Sendable, Hashable {
    public let id: String
    public let label: String
    public let systemImage: String
    public init(id: String, label: String, systemImage: String) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
    }
}

/// Personas rail: list → facet rail → one form per facet. Every facet form saves the whole persona
/// (the web editor does the same: one `PUT` with the full body).
@MainActor
public final class PersonasModule: HTDVDataSource {
    public static let facets: [PersonaFacet] = [
        PersonaFacet(id: "identity", label: "Identity", systemImage: "person.text.rectangle"),
        PersonaFacet(id: "description", label: "Description", systemImage: "text.alignleft"),
        PersonaFacet(id: "personality", label: "Personality", systemImage: "theatermasks"),
        PersonaFacet(id: "purpose", label: "Purpose", systemImage: "target"),
        PersonaFacet(id: "project", label: "Project", systemImage: "folder"),
        PersonaFacet(id: "knowledge", label: "Knowledge", systemImage: "book"),
        PersonaFacet(id: "memory", label: "Memory", systemImage: "brain"),
        PersonaFacet(id: "abilities", label: "Abilities", systemImage: "wrench"),
        PersonaFacet(id: "permissions", label: "Permissions", systemImage: "checkmark.shield"),
        PersonaFacet(id: "access", label: "Access", systemImage: "key"),
        PersonaFacet(id: "demo", label: "Demo Chat", systemImage: "message"),
        PersonaFacet(id: "chatStatus", label: "Chat Status", systemImage: "sparkles"),
        PersonaFacet(id: "llm", label: "LLM Settings", systemImage: "slider.horizontal.3")
    ]
    public static let supportedFacetIDs: Set<String> = ["identity", "description", "personality", "purpose", "llm"]
    public static let visibilityOptions: [FormSelectOption] = [
        FormSelectOption(value: "public", title: "Public"),
        FormSelectOption(value: "hub", title: "Hub"),
        FormSelectOption(value: "private", title: "Private")
    ]

    private let dataSource: any PersonasDataSource

    public init(dataSource: any PersonasDataSource) {
        self.dataSource = dataSource
    }

    // MARK: HTDVDataSource

    public func rootLevel() async throws -> HTDVLevel {
        let personas: [Persona]
        do { personas = try await dataSource.list() } catch { throw HubError.wrap(error) }
        let items = personas.map {
            HTDVItem(id: $0.id, label: $0.name, sublabel: $0.slug, systemImage: "person.crop.circle")
        }
        let spec = createSpec()
        let action = HTDVCreateAction(title: "New Persona") { presenter in
            _ = await FormSheet.present(
                title: "New persona", spec: spec, markdownEditing: HubModules.markdownEditing, from: presenter
            )
        }
        return HTDVLevel(
            id: "personas", title: "Personas", items: items, emptyMessage: "No personas yet.", createAction: action
        )
    }

    public func child(for path: [HTDVItem]) async throws -> HTDVChild {
        guard let personaID = RailPath.id(at: 0, in: path) else { return .empty }
        let persona: Persona
        do {
            persona = try await dataSource.get(id: personaID)
        } catch HubError.notFound {
            return .empty
        } catch {
            throw HubError.wrap(error)
        }
        guard let facetID = RailPath.id(at: 1, in: path) else {
            return .level(topicsLevel(for: persona))
        }
        guard let facet = Self.facets.first(where: { $0.id == facetID }) else { return .empty }
        let detailID = "persona:\(persona.id):\(facet.id)"
        let services: [PersonaService]
        if facet.id == "llm" {
            do { services = try await dataSource.listServices() } catch { throw HubError.wrap(error) }
        } else {
            services = []
        }
        if Self.supportedFacetIDs.contains(facet.id),
           let (spec, values) = facetSpec(facet.id, persona: persona, services: services) {
            return .detail(FormDetails.form(id: detailID, title: facet.label, spec: spec, values: values))
        }
        return .detail(FormDetails.notice(id: detailID, title: facet.label, message: FormDetails.unavailableMessage))
    }

    // MARK: Levels

    private func topicsLevel(for persona: Persona) -> HTDVLevel {
        let items = Self.facets.map {
            HTDVItem(id: $0.id, label: $0.label, systemImage: $0.systemImage, leadsTo: .detail)
        }
        return HTDVLevel(id: "persona-topics", title: persona.name, items: items)
    }

    // MARK: Specs

    /// The "New persona" dialog. Blank description is sent as nil; `model` is "" and visibility "private", as the web
    /// does.
    public func createSpec() -> FormSpec {
        let dataSource = self.dataSource
        return FormSpec(
            sections: [FormSection(fields: [
                .text(FormTextField(key: "name", label: "Name", placeholder: "Bob", isRequired: true)),
                .text(FormTextField(
                    key: "slug", label: "Slug", placeholder: "bob", isRequired: true,
                    pattern: Slug.pattern, patternMessage: Slug.patternMessage
                )),
                .textArea(FormTextAreaField(
                    key: "description", label: "Description", placeholder: "A one-line summary of this persona.",
                    isRequired: false, minLines: 2
                )),
                .textArea(FormTextAreaField(
                    key: "modelPrompt", label: "Prompt", placeholder: "You are Bob, an expert at naming dogs…",
                    isRequired: false, minLines: 4
                ))
            ])],
            actions: FormActions(save: FormAction(id: "create", title: "Create") { values in
                let body = PersonaBody(
                    slug: values["slug"]?.stringValue ?? "",
                    name: values["name"]?.stringValue ?? "",
                    description: HubText.nonBlank(values["description"]?.stringValue),
                    modelPrompt: values["modelPrompt"]?.stringValue ?? "",
                    model: "",
                    visibility: "private"
                )
                _ = try await dataSource.create(body)
            })
        )
    }

    /// Spec + initial values for one facet, or nil for facets this version does not edit.
    public func facetSpec(
        _ facetID: String, persona: Persona, services: [PersonaService]
    ) -> (spec: FormSpec, values: [String: FormValue])? {
        switch facetID {
        case "identity": return identitySpec(persona)
        case "description": return descriptionSpec(persona)
        case "personality": return personalitySpec(persona)
        case "purpose": return purposeSpec(persona)
        case "llm": return llmSpec(persona, services: services)
        default: return nil
        }
    }

    private func identitySpec(_ persona: Persona) -> (FormSpec, [String: FormValue]) {
        let dataSource = self.dataSource
        let spec = FormSpec(
            sections: [FormSection(title: "Identity", fields: [
                .text(FormTextField(key: "name", label: "Name", placeholder: "Bob", isRequired: true)),
                .text(FormTextField(
                    key: "slug", label: "Slug", placeholder: "bob", isRequired: true,
                    pattern: Slug.pattern, patternMessage: Slug.patternMessage
                )),
                .select(FormSelectField(
                    key: "visibility", label: "Visibility", options: Self.visibilityOptions, isRequired: true
                ))
            ])],
            actions: FormActions(
                save: saveAction(persona) { body, values in
                    body.name = values["name"]?.stringValue ?? body.name
                    body.slug = values["slug"]?.stringValue ?? body.slug
                    body.visibility = values["visibility"]?.stringValue ?? body.visibility
                },
                delete: FormDeleteAction(
                    title: "Delete persona",
                    confirmationText: "Delete persona \"\(persona.name)\"? This cannot be undone."
                ) {
                    do { try await dataSource.delete(id: persona.id) } catch { throw HubError.wrap(error) }
                }
            )
        )
        return (spec, [
            "name": .string(persona.name), "slug": .string(persona.slug), "visibility": .string(persona.visibility)
        ])
    }

    private func descriptionSpec(_ persona: Persona) -> (FormSpec, [String: FormValue]) {
        let spec = FormSpec(
            sections: [FormSection(fields: [
                .textArea(FormTextAreaField(
                    key: "description", label: "Description", placeholder: "A one-line summary of this persona.",
                    isRequired: false, minLines: 6
                ))
            ])],
            actions: FormActions(save: saveAction(persona) { body, values in
                body.description = HubText.nonBlank(values["description"]?.stringValue)
            })
        )
        return (spec, ["description": .string(persona.description ?? "")])
    }

    private func personalitySpec(_ persona: Persona) -> (FormSpec, [String: FormValue]) {
        let spec = FormSpec(
            sections: [FormSection(fields: [
                .textArea(FormTextAreaField(
                    key: "character", label: "Character", placeholder: "Personality, quirks, values.",
                    isRequired: false, minLines: 5
                )),
                .textArea(FormTextAreaField(
                    key: "voice", label: "Voice", placeholder: "How the persona speaks.", isRequired: false, minLines: 5
                )),
                .textArea(FormTextAreaField(
                    key: "examples", label: "Examples", placeholder: "Example exchanges.",
                    isRequired: false, minLines: 5
                ))
            ])],
            actions: FormActions(save: saveAction(persona) { body, values in
                body.character = HubText.nonBlank(values["character"]?.stringValue)
                body.voice = HubText.nonBlank(values["voice"]?.stringValue)
                body.examples = HubText.nonBlank(values["examples"]?.stringValue)
            })
        )
        return (spec, [
            "character": .string(persona.character ?? ""),
            "voice": .string(persona.voice ?? ""),
            "examples": .string(persona.examples ?? "")
        ])
    }

    private func purposeSpec(_ persona: Persona) -> (FormSpec, [String: FormValue]) {
        let spec = FormSpec(
            sections: [FormSection(fields: [
                .markdown(FormMarkdownField(key: "modelPrompt", label: "Purpose", isRequired: false))
            ])],
            actions: FormActions(save: saveAction(persona) { body, values in
                body.modelPrompt = values["modelPrompt"]?.stringValue ?? ""
            })
        )
        return (spec, ["modelPrompt": .string(persona.modelPrompt)])
    }

    private func llmSpec(_ persona: Persona, services: [PersonaService]) -> (FormSpec, [String: FormValue]) {
        let serviceOptions = [FormSelectOption(value: "", title: "No service")]
            + services.map { FormSelectOption(value: $0.id, title: $0.name) }
        let active = services.first { $0.id == persona.serviceId }
        let modelOptions = [
            FormSelectOption(value: "", title: active == nil ? "Pick a service first" : "No model selected")
        ]
            + (active?.models ?? []).map { FormSelectOption(value: $0.id, title: $0.displayName ?? $0.id) }
        let spec = FormSpec(
            sections: [FormSection(title: "Settings", fields: [
                .select(FormSelectField(
                    key: "serviceId", label: "Service", options: serviceOptions, isRequired: false
                )),
                .select(FormSelectField(key: "model", label: "Model", options: modelOptions, isRequired: false))
            ])],
            actions: FormActions(save: saveAction(persona) { body, values in
                let serviceID = HubText.nonBlank(values["serviceId"]?.stringValue)
                var model = HubText.nonBlank(values["model"]?.stringValue)
                let chosen = services.first { $0.id == serviceID }
                let offered = chosen?.models.contains { $0.id == (model ?? "") } ?? false
                if serviceID == nil || !offered { model = nil }
                body.serviceId = serviceID
                body.model = model
            })
        )
        return (spec, ["serviceId": .string(persona.serviceId ?? ""), "model": .string(persona.model ?? "")])
    }

    // MARK: Helpers

    /// Builds a save action that starts from the persona's full body, applies the facet's edits, and PUTs.
    private func saveAction(
        _ persona: Persona, apply: @escaping @Sendable (inout PersonaBody, [String: FormValue]) -> Void
    ) -> FormAction {
        let dataSource = self.dataSource
        return FormAction(id: "save", title: "Save") { values in
            var body = persona.body
            apply(&body, values)
            do { _ = try await dataSource.update(id: persona.id, body) } catch { throw HubError.wrap(error) }
        }
    }
}
