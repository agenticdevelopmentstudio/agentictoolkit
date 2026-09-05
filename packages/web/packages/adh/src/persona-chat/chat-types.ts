// The chat contract types this package's chat backends speak, copied VERBATIM from
// `external/agenticdevelopertoolkit/packages/web/packages/chat/src/types.ts` (and its
// `src/backends/types.ts` for `ChatBackend`) — this repo's OWN submodule, so the paths
// resolve in any recursive clone, with or without adh.
//
// WHY A COPY RATHER THAN A DEPENDENCY. `@agenticdevelopertoolkit/chat` lives in a
// DIFFERENT submodule. A `link:` from here to a sibling submodule only resolves in a
// checkout that has both — and this toolkit is consumed by repos that have neither adh
// nor that submodule (see <adh-tools>/sites/scripts/verify_toolkit_boundary.py's docstring). Both
// uses here (`persona-chat/index.ts`, `visitor-chat/sse.ts`) are TYPE-ONLY, so they
// erase at build time and a structural copy is exact: any real chat backend passed in
// by a consumer satisfies these shapes.
//
// If the source file changes shape, this copy must follow. It is duplication with a
// named source, not an independent definition — and `packages/web/tools/
// verify_chat_types_copy.py` (run in web-tests CI, which triggers on the submodule
// gitlink for exactly this reason) fails the build when the two disagree. Nothing else
// would notice: a stale copy still compiles, and a consumer's real backend just
// satisfies a shape this repo believes is current.

export interface ChatParticipant {
  name: string
  avatar?: string
}

export interface LinkContent {
  type: 'link'
  url: string
  label?: string
}

export interface ImageContent {
  type: 'image'
  src: string
  alt?: string
}

export type ContentItem = LinkContent | ImageContent

export interface PopoverData {
  title: string
  description?: string
  links?: Array<{ label: string; url: string }>
}

export interface ToolCallInfo {
  name: string
  arguments: string
  status: 'started' | 'completed' | 'failed'
  result?: string
  ok?: boolean
}

export interface ChatMessage {
  id: string
  sender: ChatParticipant
  text: string
  content?: ContentItem[]
  popover?: PopoverData
  toolCalls?: ToolCallInfo[]
  timestamp: Date
  isPersona: boolean
  isStreaming?: boolean
  /**
   * Why this message did not make it, when it did not. Present means failed.
   *
   * The contract reports a rejected send as `deliveryStatus: { kind: 'failed' }`
   * on the sender's own message, which is the honest place for it — the turn
   * produced no reply to attach an apology to. Without a field here the
   * failure reaches the transcript and renders as nothing at all: an outgoing
   * bubble sitting there with no answer and no explanation.
   */
  failure?: string
}

export type ChatResponse =
  | string
  | {
      text: string
      content?: ContentItem[]
      popover?: PopoverData
    }

export type ChatStreamEvent =
  | { type: 'token'; text: string }
  | { type: 'tool_call_started'; name: string; arguments: string }
  | { type: 'tool_call_completed'; name: string; ok: boolean; result: string }
  | { type: 'content'; items: ContentItem[] }
  | { type: 'popover'; data: PopoverData }
  | { type: 'done' }
  | { type: 'error'; message: string }

export interface ChatBackend {
  sendMessage(text: string, history: ChatMessage[]): Promise<ChatResponse>
  /**
   * Optional streaming variant. When present, useChatSession prefers it over
   * sendMessage so the UI can show token-by-token updates and tool-call events.
   *
   * Implementations should yield events in order and end with a `done` or
   * `error` event. Honor the AbortSignal if provided.
   */
  sendMessageStream?(
    text: string,
    history: ChatMessage[],
    signal?: AbortSignal,
  ): AsyncIterable<ChatStreamEvent>
  destroy?(): void
}
