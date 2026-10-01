---
id: 2beaca09-67b4-4e19-b4a4-f66f048687b8
title: VS Code Language Models Bridge
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/language-models/main-thread-language-models
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Installs vscode.lm.selectChatModels, the LanguageModelChat handback, sendRequest's
  teed stream/text response, and onDidChangeChatModels for the extension host.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- language-model
- streaming
depends-on: []
related:
- agentictoolkit://cookbook/workspace/extensions/vscode-api/language-models/ai-plugin-language-model-provider
- agentictoolkit://cookbook/workspace/extensions/host/extension-event
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadLanguageModels.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/MainThreadLanguageModelsTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/JSValueBridge.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/NotImplementedLedger.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/ExtensionHost.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWindow.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadDiagnostics.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# VS Code Language Models Bridge

## Overview

This component is the `vscode.lm` namespace's bridge: it installs `vscode.lm.selectChatModels`, the readonly `vscode.LanguageModelChat` object that call hands back (itself carrying `sendRequest` and `countTokens`), `vscode.lm.onDidChangeChatModels`, and the per-request response object `sendRequest`'s promise resolves with. It owns no chat model or provider of its own — every chat model descriptor and every streamed response part comes from an injected language-model provider seam (the production provider is a sibling recipe) — but it owns everything the seam does not: `vscode.LanguageModelChatSelector` matching, the readonly object-handback shape, `sendRequest` argument parsing and role/option validation, teeing one single-consumption provider stream into the two independent async iterables (`stream` and `text`) `vscode.LanguageModelChatResponse` declares, cancellation-token handling, the id-set comparison `onDidChangeChatModels` fires on, and recording unimplemented request options and the unimplemented `System` message role into a shared not-implemented ledger.

## Behavioral Requirements

- **provider-seam-injected**: Construction MUST store the given language-model provider as the sole source of chat models and streamed responses; this component MUST NOT construct or reach a model provider of its own.
- **chat-descriptor-fields**: The chat model descriptor MUST support value equality and MUST expose exactly six fields — `name`, `id`, `vendor`, `family`, `version`, `maxInputTokens` — mirroring `vscode.LanguageModelChat`'s six readonly properties.
- **message-role-vocabulary**: A message's role MUST have exactly two possible values, user (numeric value `1`) and assistant (numeric value `2`), matching `vscode.LanguageModelChatMessageRole`'s two implemented values.
- **response-part-cases**: A streamed response part MUST be exactly one of three kinds — text (carrying a string), a tool call (carrying an id, a name, and arguments as a JSON string), or an end marker (carrying a stop reason).
- **snapshot-seeded-at-init**: Construction MUST seed the last-known model identifier snapshot from the provider's available chat models at construction time; it MUST NOT leave that snapshot empty and rely on the first change-detection pass to populate it.
- **dispose-marks-disposed-first**: Disposal MUST record that the component is disposed before performing any other teardown step.
- **dispose-rejects-outstanding-waiters**: Disposal MUST reject every live request's outstanding `next()` waiter, on both the `stream` and `text` cursors, with the torn-down wording, before cancelling any pump.
- **dispose-cancels-pumps**: Disposal MUST cancel every live request's pump after rejecting its outstanding waiters.
- **dispose-removes-event-listener**: Disposal MUST remove this component's own subscription to the model-list change event.
- **dispose-retains-live-requests**: Disposal MUST NOT clear the live-request set; a request whose promise already resolved MUST stay reachable so a `next()` call issued after disposal gets a proper rejection rather than an answer built on torn-down state.
- **select-chat-models-torn-down-response**: `vscode.lm.selectChatModels`'s implementation MUST reject its returned promise, never raise or answer, when invoked after disposal or after this component has been torn down.
- **select-chat-models-empty-result**: When no chat model matches the given selector, `selectChatModels` MUST resolve with an empty array; it MUST NOT reject, throw, or record a not-implemented-ledger access.
- **selector-absent-matches-all**: `selectChatModels()` called with no argument MUST match every available model.
- **selector-empty-object-matches-all**: `selectChatModels({})` MUST also match every model, through the same "every field unconstrained" path as the no-argument call.
- **selector-non-object-matches-all**: A selector argument that is present but not an object MUST be treated as imposing no constraint, matching every model, rather than causing an error.
- **selector-fields-are-a-conjunction**: The selector-matching logic MUST require every field the selector actually sets (`vendor`, `family`, `version`, `id`) to equal the model's corresponding property; a model matching only some of the set fields MUST be excluded.
- **chat-model-object-readonly-getters**: Building the resolved chat-model object MUST install `name`, `id`, `vendor`, `family`, `version`, and `maxInputTokens` as readonly getter properties on the returned object; assigning to any of the six from the calling extension MUST be a silent no-op that leaves the original value unchanged.
- **chat-model-object-dropped-on-bridge-failure**: When building the returned object for a matched model fails, resolving `selectChatModels` MUST log an error and drop that model from the resolved array rather than failing the whole `selectChatModels` call.
- **count-tokens-string-argument**: `countTokens` called with a bare string MUST count that string's whitespace-delimited words as the returned token count.
- **count-tokens-message-argument**: `countTokens` called with a `LanguageModelChatMessage`-shaped object MUST read its `content` property as an array and sum the whitespace-delimited word counts of every element whose `value` is a string; it MUST NOT read `content` as a plain string when the argument is a message object.
- **count-tokens-content-string-fallback**: When a message-shaped argument's `content` property is itself a string rather than an array, the token-counting text extraction MUST count that string directly rather than treating it as an empty array.
- **count-tokens-empty-fallback**: The token-counting text extraction MUST return an empty string for an absent argument, a non-string non-object argument, or an object with no `content` property, so `countTokens` answers `0` rather than raising.
- **array-length-bound**: Reading array elements MUST decline to read any value whose reported `length` exceeds the maximum decodable array length (100,000), answering absent rather than reserving unbounded capacity.
- **array-length-real-arrays-only**: Reading array elements MUST require the argument to be a genuine array; an object that merely carries a numeric `length` property (including a string) MUST read as absent, not as that many `undefined` elements.
- **send-request-torn-down-response**: `sendRequest` MUST return a rejected promise, never a synchronous throw, when called after disposal.
- **send-request-context-unavailable**: When no script context is current at the moment `sendRequest` is invoked, the request handler MUST return nothing usable, since there is no context in which to construct even a rejected promise.
- **send-request-role-validation**: `sendRequest` MUST reject the whole call when any message's `role` is neither `1` nor `2`; it MUST NOT process a partial message list or silently skip the offending message.
- **send-request-role-exact-integer**: A message `role` MUST be read via an exact integer conversion of its numeric value, never a lossy conversion; a fractional value, or a value outside the 32-bit signed integer range that would wrap under ECMA-262 `ToInt32` semantics, MUST be rejected as unsupported rather than rounded or wrapped into a valid role.
- **send-request-system-role-ledgered**: When a message's `role` is exactly `3` (`vscode.LanguageModelChatMessageRole.System`, declared upstream but unimplemented here), the rejection path MUST additionally record that role into the shared not-implemented ledger for this component's owning extension; no other unsupported role value MUST be recorded.
- **send-request-justification-passthrough**: `sendRequest`'s `options.justification`, when present, MUST be passed to the provider's response-streaming call unchanged; nothing in this component interprets or gates on its content.
- **send-request-degraded-options-ledgered**: When `options.modelOptions`, `options.tools`, or `options.toolMode` is present (not absent, `undefined`, or `null`), `sendRequest` MUST record the corresponding member path into the shared not-implemented ledger; presence alone is recorded, never the option's content, and an honoured cancellation token MUST NOT be recorded as a degraded option.
- **send-request-cancelled-before-start**: A `CancellationToken` that is already cancelled when `sendRequest` is called MUST reject the returned promise before the provider's response-streaming call is invoked.
- **send-request-cancellation-duck-typed**: The cancellation wrapper MUST read a cancellation token by duck-typing exactly the two members `isCancellationRequested` and `onCancellationRequested`; a token that is absent, is not an object, or whose `onCancellationRequested` is not callable MUST leave the request permanently un-cancelled rather than failing the call.
- **send-request-seam-throw-rejects**: When the provider's response-streaming call throws, `sendRequest`'s promise MUST reject with that error's description; it MUST NOT propagate as a synchronous throw.
- **send-request-response-object-build-failure**: When building the response object fails, `sendRequest` MUST remove the request from the live-request set and reject the promise, and MUST NOT start the pump.
- **send-request-stored-before-pump**: A live request MUST be inserted into the live-request set before its pump is started, so a part arriving on the pump's first loop iteration always has a live owner to record into.
- **response-object-two-members**: The object `sendRequest`'s promise resolves with MUST expose exactly two members, `stream` and `text`, each an async-iterable.
- **tee-single-pump**: Starting the pump MUST run exactly one task per request that drains the provider's stream into a buffer; `stream` and `text` MUST read from that same buffer through independent cursors rather than each consuming the provider's stream directly.
- **tee-independent-cursors**: Iterating only one of `stream`/`text` to completion, or neither, MUST leave the other cursor's completion state unaffected; a cursor that is never iterated MUST NOT block or alter delivery on the cursor that is.
- **stream-yields-non-end-parts**: The `stream` cursor MUST yield every buffered part except the end marker, bridged into a `LanguageModelTextPart` or `LanguageModelToolCallPart` object matching the part's kind.
- **text-yields-text-only**: The `text` cursor MUST yield only the string payload of text parts, advancing past tool-call parts and the end marker without yielding them.
- **end-terminates-both-cursors**: The end marker MUST terminate both cursors' iteration (`done: true`) without itself being yielded as a value on either cursor.
- **end-stop-reason-dropped**: The end marker's stop reason MUST NOT be surfaced anywhere in the response object visible to the extension; `vscode.LanguageModelChatResponse` declares no member to carry it.
- **source-end-without-end-part**: A provider stream that finishes without ever yielding an end marker MUST still finish both cursors (`done: true`) once the buffer is exhausted and the source has finished.
- **part-after-end-ignored**: A part the provider stream yields after an end marker MUST NOT reach either cursor, since both cursors already finished at the end marker.
- **bridging-failure-fails-cursor**: When a buffered part cannot be bridged into a value on the `stream` cursor, that cursor MUST fail with a bridging-failure error rather than silently skip the part; a data-loss event MUST NOT masquerade as a successful, shorter response.
- **tool-call-json-parse-failure-is-null-not-fatal**: When a tool-call part's arguments do not parse as JSON, the delivered `LanguageModelToolCallPart`'s `input` MUST be `null` and an error MUST be logged; the part MUST still be delivered and the response MUST NOT fail over one malformed tool call.
- **json-parse-through-vscodeapi-call**: Tool-call argument parsing MUST invoke the script context's `JSON.parse` through the shared bridging call, not a direct engine call, so the parse error a malformed payload throws is caught here and never reaches the extension host's uncaught-exception handler.
- **one-outstanding-next-per-cursor**: Each cursor MUST hold at most one outstanding `next()` waiter at a time; a second `next()` call issued before the first settles MUST log an error and reject the displaced (earlier) waiter's promise before installing the new waiter.
- **next-settles-synchronously-when-possible**: `next()` MUST settle its returned promise synchronously whenever a value is already available to deliver; only when the buffer is exhausted for that cursor and the source has neither failed nor finished MUST the call become a pending waiter, settled later when a part arrives or the source finishes.
- **return-marks-only-its-own-cursor**: A cursor's `return(value)` MUST mark only that cursor finished and resolve that cursor's own outstanding waiter (if any) with `done: true`; it MUST NOT affect the other cursor's completion state.
- **wake-on-stale-context-clears-silently**: When a pending waiter's promise belongs to a script context that has already been released, waking it MUST clear the waiter without attempting to settle it, and MUST NOT strand it for a later wake to hit the same condition again.
- **check-completion-both-cursors**: A request MUST be cancelled and removed from the live-request set only once both the `stream` and `text` cursors have finished; a request with one cursor never iterated MUST remain in the live-request set, its buffer retained, for the rest of this component's lifetime.
- **cancellation-token-cancels-source**: When the `sendRequest` caller's `CancellationToken` becomes cancelled after streaming has started, cancelling the source MUST stop the pump, set the request's failure to a cancellation error, and mark the source finished, through the same path a thrown provider error takes.
- **cancellation-preserves-buffered-parts**: Parts already buffered before a `CancellationToken` cancellation MUST still be delivered to both cursors before either cursor observes the cancellation failure.
- **cancellation-after-finish-is-a-no-op**: Cancelling the source after it has already finished MUST NOT overwrite a completed response's outcome with a failure.
- **on-did-change-chat-models-torn-down-response**: `vscode.lm.onDidChangeChatModels`'s implementation MUST raise an exception, never reject a promise or answer normally, when invoked after disposal or after this component has been torn down, using the identical message for both causes.
- **available-chat-models-did-change-set-comparison**: Change detection MUST compare the current set of available-model ids against the last-known snapshot and MUST fire the change-notification event only when that set differs.
- **available-chat-models-did-change-replaces-before-firing**: Change detection MUST replace the last-known snapshot with the new set before firing the event.
- **metadata-only-republish-does-not-fire**: A republish of the available models that changes some model's `name`, `vendor`, `family`, `version`, or `maxInputTokens` without changing the set of ids MUST NOT fire `onDidChangeChatModels`.
- **reorder-does-not-fire**: A republish of the available models that reorders the same set of ids MUST NOT fire `onDidChangeChatModels`.
- **removal-fires**: A republish of the available models that removes an id MUST fire `onDidChangeChatModels`.
- **available-chat-models-did-change-guarded-on-disposed**: Change detection MUST return immediately, without recomputing the snapshot or firing, when the component is already disposed.

## Appearance

Not applicable — this is a script-context bridge for the `vscode.lm` namespace, not a visual component.

## States

Not applicable — this is a script-context bridge for the `vscode.lm` namespace, not a visual component. Its only lifecycle-shaped behavior is disposal and per-request completion, captured under Behavioral Requirements (**dispose-marks-disposed-first** through **dispose-retains-live-requests**, **check-completion-both-cursors**) rather than as a visual-state table.

## Accessibility

Not applicable — this is a script-context bridge for the `vscode.lm` namespace, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| main-thread-language-models-001 | select-chat-models-empty-result | `selectChatModels()` against a provider with no available chat models | Resolves with `[]`; does not reject — `MainThreadLanguageModelsTests.selectChatModelsWithNoProviderResolvesWithEmptyArrayRatherThanRejectingOrThrowing` |
| main-thread-language-models-002 | selector-absent-matches-all | `selectChatModels()` (no argument) against a provider with several models | Resolves with every model in `availableChatModels` — `MainThreadLanguageModelsTests.selectChatModelsWithNoSelectorArgumentMatchesEveryModel` |
| main-thread-language-models-003 | selector-empty-object-matches-all | `selectChatModels({})` against the same provider | Resolves with every model, identically to the no-argument call — `MainThreadLanguageModelsTests.selectChatModelsWithEmptyObjectSelectorAlsoMatchesEveryModel` |
| main-thread-language-models-004 | selector-fields-are-a-conjunction | `selectChatModels({ vendor: 'a' })` against models with mixed `vendor` values | Resolves with only the models whose `vendor == 'a'`, excluding the rest — `MainThreadLanguageModelsTests.selectorFieldExcludesNonMatchingModelAndIncludesMatchingModel` |
| main-thread-language-models-005 | selector-fields-are-a-conjunction | `selectChatModels({ vendor: 'a', family: 'x' })` against a model matching only `vendor` and one matching both | Resolves with only the model matching both fields — `MainThreadLanguageModelsTests.selectorWithTwoFieldsRequiresBothToMatchNotEither` |
| main-thread-language-models-006 | chat-descriptor-fields, chat-model-object-readonly-getters | `selectChatModels()` resolving one model, then read `name`/`id`/`vendor`/`family`/`version`/`maxInputTokens` off the resolved object | Each property equals the matching chat model descriptor field, none mixed with another field — `MainThreadLanguageModelsTests.chatModelObjectExposesEachDescriptorFieldWithoutMixingThem` |
| main-thread-language-models-007 | chat-model-object-readonly-getters | Assign `model.name = 'other'` on a resolved chat model object, then read `model.name` again | The assignment is a silent no-op; `model.name` still reads the original value — `MainThreadLanguageModelsTests.chatModelDataPropertiesAreReadonlyAssignmentIsASilentNoOp` |
| main-thread-language-models-008 | count-tokens-string-argument | `model.countTokens('one two three')` | Resolves with `3` — `MainThreadLanguageModelsTests.countTokensWithAStringArgumentCountsItsWords` |
| main-thread-language-models-009 | count-tokens-message-argument | `model.countTokens(vscode.LanguageModelChatMessage.User('one two three four'))` | Resolves with `4`, read from the message's array `content`, not by treating `content` as a string — `MainThreadLanguageModelsTests.countTokensWithAMessageArgumentReadsItsArrayContentNotAString` |
| main-thread-language-models-010 | one-outstanding-next-per-cursor, next-settles-synchronously-when-possible | Iterate `response.stream` with `for await` across several already-buffered parts | At most one `next()` call is outstanding on the cursor at any time — `MainThreadLanguageModelsTests.gateZeroForAwaitNeverHoldsMoreThanOneOutstandingNext` |
| main-thread-language-models-011 | one-outstanding-next-per-cursor | Call `it.next()` twice on the same cursor before the first settles | The first call's promise rejects, naming the one-outstanding-`next()` constraint; the second call's promise settles normally — `MainThreadLanguageModelsTests.aSecondConcurrentNextRejectsTheDisplacedFirstWaiter` |
| main-thread-language-models-012 | response-object-two-members | `sendRequest(messages, options, token)` resolving normally | The resolved object exposes exactly `stream` and `text`, each an async-iterable — `MainThreadLanguageModelsTests.sendRequestResolvesWithExactlyStreamAndText` |
| main-thread-language-models-013 | stream-yields-non-end-parts | A provider stream yielding one text part with value `"hello"`, then an end marker | `response.stream`'s first yielded value is a `LanguageModelTextPart` with `value == "hello"` — `MainThreadLanguageModelsTests.streamYieldsALanguageModelTextPart` |
| main-thread-language-models-014 | stream-yields-non-end-parts, json-parse-through-vscodeapi-call | A provider stream yielding one tool-call part with id `"t1"`, name `"search"`, and arguments JSON `{"q":"x"}` | `response.stream` yields a `LanguageModelToolCallPart` with `callId == "t1"`, `name == "search"`, `input` parsed to `{ q: "x" }` — `MainThreadLanguageModelsTests.streamYieldsALanguageModelToolCallPartWithIdNameAndParsedInput` |
| main-thread-language-models-015 | text-yields-text-only | A provider stream yielding a text part `"a"`, a tool-call part, a text part `"b"`, then an end marker | `response.text` yields `"a"` then `"b"`, skipping the tool call — `MainThreadLanguageModelsTests.textYieldsStringsOnlyAndSkipsToolCalls` |
| main-thread-language-models-016 | tee-single-pump | A provider stream yielding several parts, consumed independently on both `response.stream` and `response.text` | Both branches observe every part relevant to their own filter, drawn from one shared buffer — `MainThreadLanguageModelsTests.teeDeliversEveryPartToBothBranches` |
| main-thread-language-models-017 | tee-independent-cursors | Iterate only `response.text` to completion; never touch `response.stream` | `response.text` finishes normally; `response.stream`'s completion state is unaffected by `text` having finished — `MainThreadLanguageModelsTests.iteratingOnlyTextTerminatesWithoutTouchingStream` |
| main-thread-language-models-018 | source-end-without-end-part | A provider stream that yields a text part `"a"` and finishes without ever yielding an end marker | Both `response.stream` and `response.text` finish (`done: true`) once the buffer is exhausted — `MainThreadLanguageModelsTests.sourceFinishingWithoutEndStillFinishesBothCursors` |
| main-thread-language-models-019 | end-stop-reason-dropped | A provider stream yielding an end marker with stop reason `"some-reason"` | Neither `response.stream` nor `response.text` yields a value carrying `"some-reason"`; both simply finish — `MainThreadLanguageModelsTests.nonNilEndStopReasonIsDroppedNotSurfaced` |
| main-thread-language-models-020 | part-after-end-ignored | A provider stream yielding an end marker, then (erroneously) a text part `"late"` | The `"late"` text part never reaches either cursor — `MainThreadLanguageModelsTests.aPartAfterEndIsIgnoredNotTrapped` |
| main-thread-language-models-021 | send-request-seam-throw-rejects | A provider stream that throws mid-stream, with both cursors' `next()` calls outstanding | Both outstanding `next()` calls reject with the thrown error's description — `MainThreadLanguageModelsTests.errorMidStreamRejectsInFlightNextOfBothBranches` |
| main-thread-language-models-022 | send-request-seam-throw-rejects | The provider's response-streaming call throws synchronously before yielding any part | `sendRequest`'s returned promise rejects; it is never a synchronous throw — `MainThreadLanguageModelsTests.seamSynchronousThrowProducesARejectedPromiseNotASynchronousThrow` |
| main-thread-language-models-023 | send-request-torn-down-response | `sendRequest(...)` called after the owning component has been torn down | The returned promise rejects with the torn-down wording; it is never a synchronous throw — `MainThreadLanguageModelsTests.aTornDownAdaptorRejectsSendRequestRatherThanAnsweringOrRaising` |
| main-thread-language-models-024 | dispose-rejects-outstanding-waiters | Disposal, called while a `next()` call is outstanding on an in-flight request's cursor | The outstanding call rejects with the torn-down wording — `MainThreadLanguageModelsTests.teardownMidStreamRejectsInFlightNextWithTornDownWording` |
| main-thread-language-models-025 | dispose-retains-live-requests | Disposal, called after a request's response object already resolved, then `it.next()` called on that response | The call rejects rather than answering `undefined` or throwing from torn-down state — `MainThreadLanguageModelsTests.nextCalledAfterDisposeOnAnAlreadyObtainedResponseRejectsRatherThanAnsweringUndefined` |
| main-thread-language-models-026 | send-request-justification-passthrough, send-request-degraded-options-ledgered | `sendRequest(messages, { justification: 'why', modelOptions: {}, tools: [] }, token)` | The provider's response-streaming call receives `justification == "why"`; the not-implemented ledger records `modelOptions` and `tools` present for this extension — `MainThreadLanguageModelsTests.sendRequestPassesJustificationAndLedgersDegradedOptionsWhenPresent` |
| main-thread-language-models-027 | return-marks-only-its-own-cursor | A `for await` loop over `response.stream` that `break`s early, with `response.text` still being iterated separately | Only `response.stream` finishes from the `break`; `response.text` continues to receive parts — `MainThreadLanguageModelsTests.breakingOneBranchsForAwaitEndsOnlyThatBranch` |
| main-thread-language-models-028 | send-request-degraded-options-ledgered, send-request-system-role-ledgered | `sendRequest(messages, {}, token)` with no `modelOptions`/`tools`/`toolMode` and every message role valid | The not-implemented ledger records nothing for this call — `MainThreadLanguageModelsTests.sendRequestRecordsNothingIntoTheNotImplementedLedger` |
| main-thread-language-models-029 | send-request-cancelled-before-start | `sendRequest(messages, {}, token)` where `token.isCancellationRequested == true` before the call | The returned promise rejects with a cancellation error; the provider's response-streaming call is never invoked — `MainThreadLanguageModelsTests.aTokenAlreadyCancelledRejectsSendRequestWithoutCallingTheSeam` |
| main-thread-language-models-030 | cancellation-token-cancels-source | The `CancellationToken` fires after the response object has already resolved and both cursors have an outstanding `next()` | Both outstanding calls reject with the cancellation error — `MainThreadLanguageModelsTests.cancellingAfterTheResponseArrivesRejectsInFlightNextOnBothCursors` |
| main-thread-language-models-031 | cancellation-preserves-buffered-parts | Parts buffered before the token fires, then the token fires before either cursor drains the buffer | The buffered parts are still delivered to both cursors before either observes the cancellation failure — `MainThreadLanguageModelsTests.partsBufferedBeforeCancellationAreDeliveredBeforeTheFailure` |
| main-thread-language-models-032 | cancellation-token-cancels-source | The token fires, then the provider stream (erroneously) yields a further part | That further part never reaches either cursor — `MainThreadLanguageModelsTests.partsYieldedAfterCancellationNeverReachTheExtension` |
| main-thread-language-models-033 | cancellation-after-finish-is-a-no-op | The token fires after the provider stream has already finished normally | The already-completed response's outcome is unchanged; it does not turn into a failure — `MainThreadLanguageModelsTests.cancellingAfterTheSourceFinishedLeavesTheCompletedResponseCompleted` |
| main-thread-language-models-034 | send-request-cancellation-duck-typed | `sendRequest(messages, {}, token)` where `token.onCancellationRequested` is not a function | The request proceeds and completes normally; it is never treated as cancelled — `MainThreadLanguageModelsTests.aTokenWithoutACallableSubscriberLeavesTheRequestUncancelledNotFailed` |
| main-thread-language-models-035 | send-request-degraded-options-ledgered | `sendRequest(messages, {}, token)` with an honoured, never-fired `CancellationToken` and no other options present | The not-implemented ledger records nothing for the token — only actual degraded options are recorded — `MainThreadLanguageModelsTests.anHonouredCancellationTokenIsNotLedgeredAlongsideADegradedOption` |
| main-thread-language-models-036 | select-chat-models-torn-down-response | `selectChatModels()` called after the owning component has been torn down | The returned promise rejects with the torn-down wording; it never raises or answers — `MainThreadLanguageModelsTests.aTornDownAdaptorRejectsSelectChatModelsRatherThanAnsweringOrRaising` |
| main-thread-language-models-037 | available-chat-models-did-change-set-comparison | The available chat models gain a genuinely new id, then change detection runs | `onDidChangeChatModels` fires exactly once — `MainThreadLanguageModelsTests.aChangedIdSetFiresTheEventOnce` |
| main-thread-language-models-038 | metadata-only-republish-does-not-fire | The available chat models republish the same ids with a changed `name`/`vendor`/`family`/`version`/`maxInputTokens`, then change detection runs | `onDidChangeChatModels` does not fire — `MainThreadLanguageModelsTests.aMetadataOnlyChangeDoesNotFire` |
| main-thread-language-models-039 | available-chat-models-did-change-replaces-before-firing | Change detection runs once for a changed id set, then runs again with the same (now current) set | The event fires on the first run only; the second run does not re-fire — `MainThreadLanguageModelsTests.theSnapshotIsReplacedSoAFurtherUnchangedSignalDoesNotFireAgain` |
| main-thread-language-models-040 | snapshot-seeded-at-init | This component constructed with a provider whose available chat models already has ids, then change detection runs immediately with that same set | The event does not fire on this first call, because the snapshot was seeded at construction, not left empty — `MainThreadLanguageModelsTests.theSnapshotIsSeededInInitNotLazily` |
| main-thread-language-models-041 | reorder-does-not-fire | The available chat models republish the same ids in a different order, then change detection runs | `onDidChangeChatModels` does not fire — `MainThreadLanguageModelsTests.reorderingIsNotAChange` |
| main-thread-language-models-042 | removal-fires | The available chat models republish with one id removed, then change detection runs | `onDidChangeChatModels` fires — `MainThreadLanguageModelsTests.removalIsAlsoAChange` |
| main-thread-language-models-043 | on-did-change-chat-models-torn-down-response | `vscode.lm.onDidChangeChatModels(listener)` called after the owning component has been torn down | The call raises an exception with the torn-down wording — `MainThreadLanguageModelsTests.aTornDownAdaptorRaisesRatherThanAnsweringOrRejecting` |
| main-thread-language-models-044 | dispose-removes-event-listener | A listener registered via `vscode.lm.onDidChangeChatModels`, then disposal runs, then change detection fires a changed set | The listener registered before disposal receives nothing after it — `MainThreadLanguageModelsTests.disposeStopsDeliveryToAnAlreadyRegisteredListener` |

## Edge Cases

- **Null/empty input**: `sendRequest` called with an empty `messages` array MUST parse to an empty message list and proceed to call the provider's response-streaming call with that empty list, per **send-request-role-validation**'s own scope (nothing to reject) (MUST).
- **Null/empty input**: a message whose `role` is `undefined`, `null`, or a non-numeric value MUST reject the whole `sendRequest` call, naming the unsupported role, per **send-request-role-validation** (MUST).
- **Boundary values**: an array-like `content` object whose declared `length` exceeds the maximum decodable array length (100,000) MUST be treated as absent when reading array elements, rather than reserving that much capacity, per **array-length-bound** (MUST).
- **Boundary values**: a `role` value that only becomes `1` or `2` by wrapping under ECMA-262 `ToInt32` (for example `4294967297` wrapping to `1`) MUST be rejected, not accepted as that in-range role, per **send-request-role-exact-integer** (MUST).
- **Concurrent access**: not applicable in the sense of requiring synchronization — this component's operations are confined to a single serialized execution domain, so no two calls into its functions can execute concurrently against the same live-request state; see Platform Notes for how each platform enforces that confinement (MUST).
- **Concurrent access**: two `next()` calls issued on the same cursor before the first settles MUST NOT both remain outstanding; the earlier one is displaced and rejected, per **one-outstanding-next-per-cursor** (MUST).
- **Concurrent access**: an available-chat-models mutation concurrent with an in-flight `sendRequest` call MUST NOT retroactively change that call's already-captured messages or resolved model, because both are read synchronously before any asynchronous step.
- **Error states**: the provider's response-streaming call throwing, whether before the first part or mid-stream, MUST reject the promise or cursor(s) currently outstanding rather than propagate as a synchronous throw or leave a request silently stuck, per **send-request-seam-throw-rejects** and **errorMidStreamRejectsInFlightNextOfBothBranches**'s test (MUST).
- **Error states**: a response part that cannot bridge into a value MUST fail that cursor with a bridging-failure error rather than silently drop the part, per **bridging-failure-fails-cursor** (MUST).
- **Error states**: malformed tool-call arguments MUST deliver the part with `input: null` and a logged error rather than fail the whole response, per **tool-call-json-parse-failure-is-null-not-fatal** (MUST).
- **Offline or disconnected state**: this component makes no network call itself; connectivity loss during an in-flight `sendRequest` surfaces exactly however the provider's response stream reports it — a thrown error caught by the request handler, or a mid-stream failure caught by the pump — passed through unmodified, per **send-request-seam-throw-rejects**.
- **Cancellation and timeouts**: this component enforces no timeout of its own; the only enforced deadline is `CancellationToken`-driven cancellation, honoured per **send-request-cancelled-before-start** and **cancellation-token-cancels-source** (MUST). No timer or deadline mechanism exists in the source.
- **Missing file or unreachable server**: not applicable — this component opens no file and makes no network call of its own; the injected provider and not-implemented ledger are both in-memory collaborators, and any network dependency belongs to the provider, not to this component.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `provider` | language-model provider seam | none (required) | Sole source of the available chat models and the response stream; not defaulted, per **provider-seam-injected**. |
| not-implemented ledger | shared ledger reference | none (required) | Recorded into for the unimplemented `System` message role and for degraded `sendRequest` options; not defaulted. |
| owning extension identifier | string | none (required) | Which extension owns this component; stamped into every ledger record. Not validated for non-emptiness. |
| `selector` (`selectChatModels` argument) | `vscode.LanguageModelChatSelector?` | absent, matches all | `vendor`/`family`/`version`/`id`, each independently optional; a present-but-non-object value is also treated as "match all." |
| `messages` (`sendRequest` argument) | array of messages | none (required) | Parsed from `sendRequest`'s first argument; a message with an unsupported `role` rejects the whole call. |
| `options.justification` (`sendRequest` argument) | string or absent | absent | Forwarded to the provider's response-streaming call unchanged; never interpreted here. |
| `options.modelOptions` / `.tools` / `.toolMode` (`sendRequest` argument) | present or absent | absent | Presence alone is recorded into the not-implemented ledger; content is never read. |
| `token` (`sendRequest` argument, `CancellationToken`) | duck-typed value or absent | uncancelled | Honoured only when it is an object exposing a callable `onCancellationRequested`; otherwise the request is never cancelled. |
| maximum decodable array length | integer | `100_000` | The ceiling reading array elements enforces for every array this component walks. Not settable per call. |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable destination — it installs `vscode.lm` members and streams responses, with no navigation surface of its own.

## Localization

- **hardcoded-role-rejection-messages**: the message `sendRequest` uses to reject a call with an unsupported `role` names the offending role value and is a hardcoded English string literal with no localization key. It is visible to the extension author whose call triggered it, not to the app's own end-user UI.
- **hardcoded-teardown-messages**: the torn-down messages `selectChatModels`, `sendRequest`, and `onDidChangeChatModels` each produce (built by a shared teardown helper every `vscode` member adaptor uses, not by this component directly) are likewise hardcoded English, in the fixed shape `"<path> is unavailable: this extension's host has been torn down."`.
- **hardcoded-cursor-rejection-messages**: the message rejecting a displaced `next()` waiter (**one-outstanding-next-per-cursor**) and the message a bridging or cancellation failure surfaces on a cursor are both hardcoded English error descriptions with no localization mechanism.
- **hardcoded-log-strings**: every error-log call this component makes (a dropped chat-model object, a displaced waiter, a bridging failure, a tool-call JSON parse failure) is a hardcoded English interpolated string, also unlocalized.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `vscode.lm.selectChatModels is unavailable: this extension's host has been torn down.` | Shared teardown helper, produced when `selectChatModels` reaches a torn-down component. |
| (none — literal only) | `vscode.lm.sendRequest` (chat model object) `is unavailable: this extension's host has been torn down.` | Shared teardown helper, produced when `sendRequest` reaches a torn-down component. |
| (none — literal only) | `vscode.lm.onDidChangeChatModels is unavailable: this extension's host has been torn down.` | Shared teardown helper, produced when `onDidChangeChatModels` reaches a torn-down component. |
| (none — literal only) | A message naming the unsupported `role` value | `refuseUnsupportedRole`, raised when a message's `role` is not `1` or `2`. |
| (none — literal only) | A message naming the one-outstanding-`next()` constraint | The cursor executor, raised on the earlier of two overlapping `next()` calls. |

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; every member is always available once this component is installed on a host.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent calls are the error-log lines covered under Logging, which are diagnostic logging, not analytics events.

## Privacy

- **Data collected**: this component collects no data of its own; it handles whatever `messages`, `justification`, tool-call arguments, and streamed response text an extension supplies to or receives from `sendRequest`, none of which this component logs.
- **Storage**: conversation messages and streamed response parts are held only in the injected request's in-memory buffer for the lifetime of that request; nothing here writes to disk, a database, or any persistent store.
- **Transmission**: this component makes no network call of its own; whatever transmission the provider's response-streaming call performs is the seam's responsibility, not this component's.
- **Retention**: per **dispose-retains-live-requests** and **check-completion-both-cursors**, a request's buffered parts (which may include conversation text and tool-call arguments) stay retained in the live-request set for the rest of this component's lifetime if the extension never fully iterates both `stream` and `text` — a deliberate memory-retention cost, not a leak the source treats as a bug.

## Logging

Logged through the shared extension-host logger, under this component's own category, at the levels below.

| Event | Level | Message |
|-------|-------|---------|
| Building a matched model's returned object fails, inside resolving `selectChatModels` | error | Names the dropped model; the model is excluded from the resolved array rather than failing the call. |
| A second `next()` call displaces an outstanding waiter on the same cursor | error | Names the one-outstanding-`next()` constraint being violated. |
| A buffered part fails to bridge into a value on the `stream` cursor | error | Names the bridging failure that becomes a bridging-failure error. |
| A tool-call part's arguments fail to parse as JSON | error | Names the malformed payload; the part is still delivered with `input: null`. |

No other event in this component is logged: a rejected `selectChatModels`/`sendRequest` call and a raised `onDidChangeChatModels` exception are each surfaced to the caller directly, per **select-chat-models-torn-down-response**, **send-request-torn-down-response**, and **on-did-change-chat-models-torn-down-response**, rather than logged.

## Platform Notes

- **SwiftUI**: not applicable to this file — `MainThreadLanguageModels.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing here renders or observes view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadLanguageModels.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is installed onto an `ExtensionHost`'s `vscode.lm` namespace via `defineVSCodeMember(namespacePath:name:implementation:)`, the same seam every other `VSCodeAPI` adaptor in this directory uses. `MainThreadLanguageModels`, `ExtensionLanguageModelProviding`, `LanguageModelCancellation`, and `LanguageModelResponseRequest` are all declared `@MainActor`, so every stored property read, mutation, and method body is confined to the main actor — this is what makes the "single serialized execution domain" edge-case note above true on this platform, enforced by the compiler rather than by any lock or queue in the source. `LanguageModelChatDescriptor` additionally conforms to `Sendable` and `Equatable`, and each case of `ExtensionLanguageModelResponsePart` is `Sendable`, so both can cross the actor boundary and be compared for the id-set change check safely. `JSContext`/`JSValue` are not `Sendable` and JavaScriptCore always calls back on the thread that made the call, which is why the whole bridge lives on the main actor rather than a background queue. This is purely a Swift-concurrency fact about this implementation; a port to another platform's threading model documents its own equivalent confinement mechanism instead.
- **Compose**: model `ExtensionLanguageModelProviding` as a Kotlin interface exposing `val availableChatModels: List<LanguageModelChatDescriptor>` and `suspend fun streamResponse(...): Flow<ExtensionLanguageModelResponsePart>`. Model the tee (`stream`/`text`) as a small class holding a `MutableList` buffer plus two independent cursor indices, matching **tee-single-pump** and **tee-independent-cursors** exactly, rather than calling `Flow.shareIn` twice against the same upstream (which would re-collect, not replay, the source). Model `LanguageModelCancellation` against `kotlinx.coroutines.CancellationException`/`CoroutineScope.cancel()` in place of the duck-typed `CancellationToken` object this file reads.
- **React/Web**: this is closest to the actual runtime shape — extension code in the real VS Code product already calls `vscode.lm.selectChatModels`/`sendRequest` against the genuine `vscode.d.ts` declarations these types mirror. A React/Web extension host implementing the same bridge would tee a single provider stream into two independent async generators reading a shared buffer array by index, exactly this file's **tee-single-pump** design, across whatever serialization boundary (for example `postMessage` to a worker) replaces this file's `JSContext` boundary.
- **WinUI 3**: model `ExtensionLanguageModelProviding` as a C# interface — `IReadOnlyList<LanguageModelChatDescriptor> AvailableChatModels { get; }` and `IAsyncEnumerable<ExtensionLanguageModelResponsePart> StreamResponseAsync(IReadOnlyList<ExtensionLanguageModelMessage> messages, string? justification, string extensionIdentifier, CancellationToken cancellationToken)` — letting .NET's native `CancellationToken` replace this file's duck-typed `LanguageModelCancellation` wrapper entirely, since WinUI 3 has no JavaScript boundary to duck-type across. `IAsyncEnumerable<T>` has no built-in tee, so model the response object as a small class holding a `List<ExtensionLanguageModelResponsePart>` buffer plus two cursor offsets — the direct analogue of **tee-single-pump**, **tee-independent-cursors**, and **check-completion-both-cursors** — exposing two custom `IAsyncEnumerator<T>` implementations (one filtering to non-`.End` parts, one to `.Text` payloads only) rather than two independent `Channel<T>` readers, since a `Channel` broadcast would not preserve "already-buffered parts survive a later cancellation" (**cancellation-preserves-buffered-parts**). Parse tool-call arguments with `System.Text.Json.JsonDocument.Parse` inside a `try`/`catch` around `JsonException`, mirroring **tool-call-json-parse-failure-is-null-not-fatal**'s "log and deliver `null`, never fail the whole response" rule. Model `Dictionary<Guid, LanguageModelResponseRequest>` for `liveRequests` and a plain `event Action? AvailableChatModelsChanged`, firing only when a computed `HashSet<string>` of ids changes from the previous snapshot, for **available-chat-models-did-change-set-comparison**.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadLanguageModels.swift` |

## Design Decisions

**Decision**: `.end`'s `stopReason` is dropped rather than surfaced through any member of the JS-visible response object.
**Rationale**: `vscode.LanguageModelChatResponse` declares only `stream` and `text`, neither of which has anywhere to carry a stop reason; the loss is upstream's own type shape, not a gap this file introduces, so `.end` is buffered like any other part internally but never yielded as a value on either cursor.
**Approved**: pending

**Decision**: `dispose()` does not clear `liveRequests`.
**Rationale**: a request whose response object has already been handed to the extension can still receive a `next()` call after `dispose()` runs. Clearing `liveRequests` would let that call fall through to deallocated state and answer with `undefined` or crash; retaining the entry lets it be rejected with the correct torn-down wording instead, at the cost of keeping that request's buffer allocated for the rest of the adaptor's lifetime.
**Approved**: pending

**Decision**: a response part that fails to bridge into JavaScript on the `stream` cursor now fails that cursor with `LanguageModelPartBridgingFailure`, rather than being silently skipped.
**Rationale**: silently dropping a part would let a shorter, incomplete response masquerade as a successful one; failing the cursor makes the data loss observable to the extension that would otherwise trust an under-delivered result.
**Approved**: pending

**Decision**: a message `role` is validated with `Int32(exactly:)`, never `toInt32()`.
**Rationale**: `toInt32()` implements ECMAScript's `ToInt32`, which wraps modulo 2³² and truncates fractions, so a value like `4294967297` would read as the in-range integer `1` and be silently accepted as `.user` when it is not a role JavaScript ever meant to send. `Int32(exactly:)` answers `nil` for any value that is not exactly representable, so `sendRequest` refuses the whole call instead of accepting a role value that only looks valid after wraparound.
**Approved**: pending

**Decision**: `options.modelOptions`, `options.tools`, and `options.toolMode` are recorded into `notImplementedLedger` by presence alone and never passed to `provider.streamResponse`.
**Rationale**: no provider conformer given to this file honours any of the three yet; passing them through unread would misrepresent them as handled, while inventing partial handling here would guess at a contract the seam does not define. Recording presence in the shared ledger keeps the gap visible to whoever inspects it without this file pretending to close it.
**Approved**: pending

**Decision**: `LanguageModelCancellation` duck-types a `CancellationToken` by checking only for `isCancellationRequested` and a callable `onCancellationRequested`, leaving any other shape permanently un-cancelled rather than raising.
**Rationale**: `token` is optional in `vscode.d.ts`'s own `sendRequest` signature, and an extension may pass `undefined` or an object that merely resembles a token; failing the call over an absent or malformed cancellation mechanism would reject requests the declared API contract allows through, so this file treats anything it cannot duck-type as "never cancelled" instead.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because this file's responsibilities stay cleanly divided: selector matching (`LanguageModelChatSelectorCriteria`), the readonly object-handback shape (`makeChatModelObject`), request/option parsing (`handleSendRequest`, `parseRequestOptions`), the tee itself (`LanguageModelResponseRequest`, `startPump`, `scan`/`next`/`wake`), and event filtering (`availableChatModelsDidChange`) each live in their own type or function, none reaching into `provider`'s own streaming implementation. `unit-test-coverage` passes: `MainThreadLanguageModelsTests.swift`'s 47 test methods exercise every documented branch this recipe cites — selector matching in all three shapes, both readonly-getter and count-tokens paths, the one-outstanding-`next()` gate, every tee/cursor independence and termination case, every `sendRequest` rejection path (torn-down, role validation, seam throw, cancellation before and during streaming), and every `onDidChangeChatModels` filtering and teardown case. `explicit-error-handling` passes: every failure path this file defines — torn-down responses, role rejection, seam throws, bridging failures, malformed tool-call JSON, cancellation — settles as a typed rejection, a raised exception, or a logged-and-substituted value, per the Behavioral Requirements and Edge Cases above; none of them is swallowed with no signal. `secure-log-output` passes because none of this file's four log events (a dropped model, a displaced waiter, a bridging failure, a JSON parse failure) includes message content, `justification`, or tool-call argument values — each names only the failure kind and an identifier, never the conversation itself. `no-hardcoded-strings` fails because every rejection message, teardown message, and log message this file produces is an English literal with no localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/language-models/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
