<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin--test-vectors · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin.md -->

# AIPlugin

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin--test-vectors#<slug>`):

- `cheap-instantiation-has-dedicated-vector-constructor` SHOULD — cheap-instantiation (SHOULD) has no dedicated vector: constructor cost is a design guideline about how a plugin is …

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-plugin-001 | zero-argument-initialization | Construct a conforming type with no arguments, e.g. `EchoPlugin()` (`AIPluginKitTests.swift`). | The initializer returns a usable instance without throwing or crashing. |
| ai-plugin-002 | request-description | `EchoPlugin().buildRequest(AIChatContext(messages: [AIChatMessage(role: .user, content: "hi")], model: "test-model", config: AIPluginConfig(["apiKey": "secret"])))` (`AIPluginKitTests.swift`). | Returns an `AIRequestSpec` whose `.transport` is `.http(method: .post, url: https://api.example.com/chat, headers: ["x-api-key": "secret"], body: Data("test-model".utf8))`. |
| ai-plugin-003 | insufficient-context-error | `OpenAIPlugin().buildRequest(AIChatContext(messages: [...], model: "gpt-4.1-nano", config: AIPluginConfig([:])))` — no `apiKey` present (`OpenAIPlugin.swift`). | Throws `OpenAIPlugin.PluginError.missingAPIKey` instead of returning a spec. |
| ai-plugin-004 | fresh-decoder-per-response, decoder-isolation | Call `EchoPlugin().makeDecoder()` twice to get decoder A and decoder B; feed only decoder A the bytes `Data("a\n".utf8)`, then call `finish()` on both. | Decoder A's `finish()` (after `consume`) yields `[.textDelta("a")]`; decoder B's `finish()` yields `[]` — the two instances hold independent state. |
| ai-plugin-005 | fresh-decoder-per-response | `decoder.consume(Data("he".utf8))`, then `consume(Data("llo\nwor".utf8))`, then `consume(Data("ld\n".utf8))`, then `finish()`, on one `LineDecoder` from `EchoPlugin().makeDecoder()` (`AIPluginKitTests.swift`). | Emits `[.textDelta("hello"), .textDelta("world")]`, in order, across the three `consume` calls plus `finish()`. |
| ai-plugin-006 | validation-request-default | `EchoPlugin().buildValidationRequest(config: AIPluginConfig(["apiKey": "x"]))` — `EchoPlugin` does not override the method. | Returns `nil`. |
| ai-plugin-007 | validation-request-cannot-validate | A stub conformer overrides `buildValidationRequest(config:)` to return `.http(url: validationURL)` when `config.apiKey != nil`, else `nil`; call it with `AIPluginConfig([:])`. | Returns `nil` because the stub has no key to validate. |
| ai-plugin-008 | error-message-default | `EchoPlugin().describeError(status: 500, body: Data())` — `EchoPlugin` does not override the method. | Returns `nil`, signaling the host should use its generic "HTTP 500" fallback. |
| ai-plugin-009 | transport-non-ownership, ui-non-ownership, secret-non-ownership, metadata-non-ownership | Enumerate `AIPlugin`'s protocol requirements (`AIPlugin.swift`). | Exactly `init()`, `buildRequest(_:)`, `makeDecoder()`, `buildValidationRequest(config:)`, `describeError(status:body:)` — no member performs I/O directly, presents a view, reads/writes a credential store, or returns an identifier/display name. |
| ai-plugin-010 | sendable-conformance | Declare `final class BadPlugin: AIPlugin { var box = NSMutableString() }` with no `@unchecked Sendable` escape hatch, under `SWIFT_STRICT_CONCURRENCY: complete`. | Fails to compile: the non-`Sendable` stored property violates the `Sendable` conformance `AIPlugin: AnyObject, Sendable` requires. |
| ai-plugin-011 | concurrent-invocation-safety | A single, stateless `EchoPlugin` instance (as cached and reused by `AIPluginManager.loadPlugin(identifier:)`, `AIPluginManager.swift`) has `buildRequest(_:)` invoked concurrently from two `Task`s with two different `AIChatContext` values. | Both calls return correct, independent `AIRequestSpec` values; no data race occurs, because `EchoPlugin` reads only its `context` parameter and holds no shared mutable field. |
| ai-plugin-012 | foundation-only-dependency, shared-framework-image | Inspect `AIPlugin.swift`'s imports and `packages/apple/AIPlugins/project.yml`'s `OpenAI` target dependency on `AgenticToolkit/AIPluginKit`. | `AIPlugin.swift` imports only `Foundation`; the `OpenAI` (and every sibling plugin) target declares `dependencies: [{target: AgenticToolkit/AIPluginKit, embed: false}]` — linked, not embedded. |

`cheap-instantiation` (SHOULD) has no dedicated vector: constructor cost is a design guideline about how a plugin is expected to be written, not an automatable pass/fail assertion on the protocol itself; the rationale for this omission is recorded here per the Completeness guideline.
