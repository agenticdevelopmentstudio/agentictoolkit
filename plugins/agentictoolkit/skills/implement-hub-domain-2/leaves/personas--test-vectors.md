<!-- leaf: implement-hub-domain-2/personas--test-vectors · source: hub-domain-personas.md -->

# Hub Domain: Personas

## Conformance Test Vectors

| Input | Expected output / effect | Traced to |
|-------|---------------------------|-----------|
| `rootLevel()` with personas Ada, Bob | `HTDVLevel` with `items.label == ["Ada","Bob"]`, `items.sublabel == ["ada","bob"]`, `emptyMessage == "No personas yet."`, `createAction.title == "New Persona"` | `testRootLevelListsPersonas` |
| `child(for:[ada])` | `.level` with `id == "persona-topics"`, `title == "Ada"`, item ids exactly `identity, description, personality, purpose, project, knowledge, memory, abilities, permissions, access, demo, chatStatus, llm` | `testPersonaChildIsFacetRail` |
| Identity form: set `name` to `"Ada Lovelace"`, `visibility` to `"hub"`, save | `source.updates[0]` has `body.name == "Ada Lovelace"`, `body.visibility == "hub"`, `body.modelPrompt == "You are Ada."` (untouched, rides along) | `testIdentityFormValuesAndSave` |
| Identity slug field validated against `"Bad Slug"` | `FormValidator.validate(...) == Slug.patternMessage` | `testIdentityFormValidatesSlug` |
| Delete action performed on Ada's identity facet | `spec.actions.delete.confirmationText == "Delete persona \"Ada\"? This cannot be undone."`; `source.deletes == ["persona.me.ada"]` | `testIdentityDeleteAction` |
| Personality form: `voice = "   "`, `character = "Curious"`, save | `body.voice == nil`, `body.character == "Curious"` | `testBlankTextBecomesNilOnSave` |
| LLM form: clear `serviceId` to `""`, save | `body.serviceId == nil`, `body.model == nil` | `testLLMSaveClearsModelWhenServiceHasNoSuchModel` |
| `child(for:)` on each of the 8 unsupported facet ids | detail form value for key `"notice"` equals `"Not available in this version"`; `facetSpec` returns `nil` | `testUnsupportedFacetsShowNotice` |
| `createSpec().actions.save.perform(name: "Bob", slug: "bob", description: "", modelPrompt: "You are Bob.")` | `source.creates[0]` has `description == nil`, `model == ""`, `visibility == "private"` | `testCreateSpecAndPerform` |
| Decode a web JSON payload with extra fields `userId`/`ownerKind`/`ownerId` | Decode succeeds; `persona.name == "Ada"`, unknown fields dropped, `persona.cannedChat == .object(["mode": .string("script"), "turns": .array([])])` | `testPersonaDecodesFromWebJSON` |
| `canDemoChat({ enabled: true, ink: { source: "* [unclosed\n", signInLine: "x" } })` | `true` — a syntax error in the ink script still advertises a demo | canned.test.ts, "does not compile the ink — a syntax error still advertises a demo" |
| `canDemoChat({ ...good, enabled: false })` and `canDemoChat(null)` | both `false` | canned.test.ts, "is false for a parked script and for no config at all" |
| `parseChatStatus({ words: 7 })` | `{ words: [], icons: [] }` — malformed field dropped to an empty list, not substituted with the default | chat-status.test.ts, "drops a malformed words/icons field to an empty list rather than substituting the default" |
| `resolveChatStatus(cfg, "search")` where `cfg` has one word pair tagged `"search"` plus untagged defaults | `words` is the UNION of the tagged and untagged rows; `frames` resolves to the first matching icon set only | chat-status.test.ts, "unions rows tagged with the kind with untagged rows that fit anything" |
