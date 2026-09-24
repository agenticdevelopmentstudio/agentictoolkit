'use client'

import { useEffect, useMemo, useRef, useState, type RefObject } from 'react'
import {
  CHAT_INPUT_SELECTOR,
  InlineChatView,
  useBlockCursor,
  useChatSession,
  useConnectRitual,
  useInputFocusReclaim,
  usePersonaGaze,
  usePersonaMood,
  useRotatingPhrase,
  useTransientEcho,
  type ChatBackend,
  type GazeVector,
  type InlineChatSizing,
} from '@agenticdevelopertoolkit/chat'
import { ThemeStyle, type ThemeKey } from '@agenticdevelopertoolkit/themes'
import { BitbagBackend } from './backend'
import type { BitbagExpression } from './avatar'
import {
  CONNECTED,
  CONNECTING,
  DISABLED_PLACEHOLDER,
  GREETING,
  IDLE_WORDS,
  NEGOTIATION,
  PLACEHOLDERS,
  SUMMON_SEQUENCE,
  TERMINAL_THEME,
  THINKING_GLYPH,
  THINKING_GLYPH_DONE,
  THINKING_WORDS,
  WELCOME,
} from './voice'

const PERSONA = { name: 'bitbag' }

/** While a reply is in flight he cycles engaged moods so he reads as pondering. */
const FLIGHT_MOODS: readonly BitbagExpression[] = ['thinking', 'inquisitive', 'excited']
/** While the user composes he rotates through curious / interested. */
const TYPING_MOODS: readonly BitbagExpression[] = ['inquisitive', 'excited']
/** The satisfied beat when a reply lands, then back to his reflexes. */
const ANSWER_BEAT = { mood: 'smug' as const, ms: 2200 }
/** He holds his random utterances for this long after first connecting. */
const QUIET_START_MS = 30000
/** How far the dock's transcript may grow before it starts scrolling. */
const DOCK_MAX_HEIGHT = '46vh'

// The chat's visual skin comes entirely from the toolkit theme applied here,
// scoped to this wrapper so switching it never touches the rest of the page.
const THEME_SCOPE = 'pc-theme-scope'

/**
 * How bitbag occupies the page — the one axis the two mountings differ on, so
 * they can't drift into two forks of him. (Which is what they WERE: fishlamp.com
 * ran a vendored copy of this file for months, and the two bitbags diverged down
 * to his eye color. fishlamp's is the version that shipped, so it is the one
 * folded back in here — see the `dock` notes below and `DEFAULT_THEME`.)
 *
 * - `stage`: he IS the page (bitbag.ai). He is summoned — the composer stays
 *   shut while a status line cycles "bitbag summoned, success unlikely..." and
 *   he waits to be reached for. Making you wait for him is the joke.
 * - `dock`: he is a fixture in the corner of a page about something else (the
 *   shared footer). He arrives already connected and folds down to a single
 *   entry line when idle. A fixture that won't answer until it has finished
 *   performing is just broken, so the summoning theater is dropped here.
 */
export type BitbagVariant = 'stage' | 'dock'

export interface BitbagChatProps {
  /** The toolkit theme that skins the chat. */
  theme: ThemeKey
  /** How he occupies the page — see BitbagVariant. Defaults to `stage`. */
  variant?: BitbagVariant
  /**
   * The chat backend driving the conversation. Defaults to bitbag's built-in
   * scripted mock (`BitbagBackend`), so consumers that omit it are unchanged;
   * pass a real `ChatBackend` to talk to a live service.
   */
  backend?: ChatBackend
  /** Reports a deliberate expression hint up to the driver; null hands control back to his reflexes. */
  onExpressionHint?: (hint: BitbagExpression | null) => void
  /** Reports where bitbag should look; null hands his gaze back to his reflexes. */
  onGazeHint?: (gaze: GazeVector | null) => void
  /** bitbag's latest utterance, echoed transiently in the idle status line. */
  utterance?: { text: string; id: number } | null
  /** Reports when bitbag should be muted, so the status holds the spinner, not his chatter. */
  onMute?: (mute: boolean) => void
  /**
   * The avatar element he is measured against: his eyes track the caret relative
   * to this frame's horizontal centre, and on the `stage` it also caps the chat's
   * height at the element's bottom so the transcript never rises over him. (In the
   * `dock` he sits directly above his chat, so the cap comes from the viewport
   * instead — an element-offset there would leave the transcript no room at all.)
   */
  anchorRef?: RefObject<HTMLElement | null>
  /** Extra classes on the theme-scope root — the host's positioning wrapper. */
  className?: string
  /**
   * Whether the chat is unfolded, when the host takes that over from the chat's own
   * focus / tap-away / Escape tracking — the dock does, so that hiding his chat also
   * folds it. Only the `dock` variant folds at all (`inactive: minimal`); the stage
   * is always open, so there it means nothing.
   */
  engaged?: boolean
  /**
   * Reports each unfold and fold as it happens — the typed signal the dock closes
   * on, rather than reading the chat's classes back off the DOM. Dock variant only,
   * for the same reason.
   */
  onEngagedChange?: (engaged: boolean) => void
}

export function BitbagChat({
  theme,
  variant = 'stage',
  backend: backendProp,
  onExpressionHint,
  onGazeHint,
  utterance,
  onMute,
  anchorRef,
  className,
  engaged,
  onEngagedChange,
}: BitbagChatProps) {
  const isDock = variant === 'dock'
  // Default to the built-in scripted mock so existing consumers are byte-for-byte
  // behavior-identical; a supplied backend takes over verbatim.
  const backend = useMemo(() => backendProp ?? new BitbagBackend(), [backendProp])
  const wrapperRef = useRef<HTMLDivElement>(null)
  // No welcome message — the connect ritual types it in instead.
  const session = useChatSession({ backend, persona: PERSONA })

  // One ritual, two arrivals. On the stage he is summoned: the wait lines cycle
  // until the reader reaches for him. In the dock he arrives already connected
  // (`engageOn: 'mount'`), so it runs straight through — welcome, beat, greeting,
  // composer open — and the summoning lines are never shown.
  const { inputDisabled, connected, engagedByUser, statusLine } = useConnectRitual({
    say: session.say,
    welcome: WELCOME,
    greeting: GREETING,
    waitLines: isDock ? undefined : SUMMON_SEQUENCE,
    stallLines: isDock ? undefined : NEGOTIATION,
    connectingLine: CONNECTING,
    connectedLine: CONNECTED,
    engageOn: isDock ? 'mount' : 'pointer',
  })

  // "The reader has deliberately reached for him" — which on the stage the ritual
  // already tracks (being reached for is what summons him: `engagedByUser`, NOT
  // `engaged`, which the 30s give-up timeout also sets without the reader having
  // touched anything). In the dock it is a DIFFERENT fact from arriving: he
  // connects at mount there, so the ritual sees no reach at all. The dock watches
  // for it itself.
  const [dockEngaged, setDockEngaged] = useState(false)
  useEffect(() => {
    const el = wrapperRef.current
    if (!isDock || !el || dockEngaged) return
    const onEngage = (): void => setDockEngaged(true)
    el.addEventListener('pointerdown', onEngage)
    el.addEventListener('focusin', onEngage)
    return () => {
      el.removeEventListener('pointerdown', onEngage)
      el.removeEventListener('focusin', onEngage)
    }
  }, [isDock, dockEngaged])
  const reached = isDock ? dockEngaged : engagedByUser

  // He's "responding" both while awaiting the reply AND while it streams out.
  const streaming = session.messages.some((m) => m.isStreaming)
  const responding = session.isTyping || streaming

  // Detect the user composing.
  const [userTyping, setUserTyping] = useState(false)
  useEffect(() => {
    const input = wrapperRef.current?.querySelector<HTMLInputElement>(CHAT_INPUT_SELECTOR)
    if (!input) return
    const onInput = () => setUserTyping(input.value.trim().length > 0)
    const onBlur = () => setUserTyping(false)
    input.addEventListener('input', onInput)
    input.addEventListener('blur', onBlur)
    return () => {
      input.removeEventListener('input', onInput)
      input.removeEventListener('blur', onBlur)
    }
  }, [])
  // Once a reply is in flight the message has been sent — drop "typing".
  useEffect(() => {
    if (session.isTyping) setUserTyping(false)
  }, [session.isTyping])

  // Gated on having been reached for, not merely on the composer being open. The
  // reclaim's first act is to focus the input, and the input taking focus is what
  // the sizing hook reads as engagement — so in the dock, enabling it the instant
  // he finished greeting would have him seize the caret and hold himself open
  // over the page. He greets from the corner and folds back down. (On the stage
  // this is the same condition as before: being reached for is what starts the
  // ritual, so the composer never opens before `reached`.)
  useInputFocusReclaim(wrapperRef, reached && !inputDisabled)

  const sentCount = session.messages.reduce((n, m) => n + (m.isPersona ? 0 : 1), 0)
  const placeholder = useRotatingPhrase(PLACEHOLDERS, sentCount)
  const { echo, idleIndex } = useTransientEcho(utterance)
  const idleWord = useRotatingPhrase(IDLE_WORDS, idleIndex)

  const { mood, beat } = usePersonaMood<BitbagExpression>({
    responding,
    composing: userTyping,
    flightMoods: FLIGHT_MOODS,
    typingMoods: TYPING_MOODS,
    answerBeat: ANSWER_BEAT,
  })
  useEffect(() => {
    onExpressionHint?.(mood)
  }, [mood, onExpressionHint])

  // Hold his random utterances until well after he connects.
  const [quietStart, setQuietStart] = useState(true)
  useEffect(() => {
    if (!connected) return
    const id = setTimeout(() => setQuietStart(false), QUIET_START_MS)
    return () => clearTimeout(id)
  }, [connected])
  useEffect(() => {
    onMute?.(responding || beat || inputDisabled || quietStart)
  }, [responding, beat, inputDisabled, quietStart, onMute])

  // His two gaze sources — cursor-follow before he's reached for, caret-follow
  // once he has been — arbitrated by one toolkit hook, so both mountings share a
  // single correct implementation of the switch. onGazeHint's own null, when the
  // box empties, hands his gaze back to his idle reflexes.
  usePersonaGaze(wrapperRef, anchorRef, reached, (g: GazeVector | null) => onGazeHint?.(g))
  const caretBox = useBlockCursor(wrapperRef, theme === TERMINAL_THEME, sentCount)

  // On the stage the transcript grows up until it reaches bitbag's bottom edge,
  // so it never rises over him, and it is always open. In the dock he rides
  // directly above his chat — an element-offset there would leave the transcript
  // no room — so it caps against the viewport instead, and folds away to just the
  // composer bar when idle (`inactive: minimal`), which is also how he sits on
  // load: collapsed, waiting to be reached for.
  const sizing: InlineChatSizing = useMemo(
    () =>
      isDock
        ? {
            active: { mode: 'content-hugging', maxHeight: { kind: 'css', value: DOCK_MAX_HEIGHT } },
            inactive: { mode: 'minimal' },
            transition: 'animated',
          }
        : {
            active: {
              mode: 'content-hugging',
              maxHeight: anchorRef
                ? { kind: 'element-offset', ref: anchorRef, gapPx: 24 }
                : { kind: 'viewport-offset', topOffsetPx: 80 },
            },
          },
    [isDock, anchorRef],
  )

  const rootClass = [THEME_SCOPE, className].filter(Boolean).join(' ')

  return (
    <div ref={wrapperRef} className={rootClass}>
      <ThemeStyle theme={theme} scope={`.${THEME_SCOPE}`} />
      <InlineChatView
        session={session}
        placeholder={inputDisabled ? DISABLED_PLACEHOLDER : placeholder}
        thinkingLabels={THINKING_WORDS}
        thinkingFrames={THINKING_GLYPH}
        thinkingDoneGlyph={THINKING_GLYPH_DONE}
        thinkingColorful
        statusWhileStreaming={!inputDisabled}
        idlePhrase={inputDisabled ? undefined : `waiting to ${idleWord}`}
        /* The status line is the stage's — it is how the summoning is PERFORMED,
         * and the dock has no summoning. The dock's ritual runs at mount, so
         * showing it here would flash "bitbag connecting, brace for mediocrity..."
         * → "bitbag connected, against my better judgment." in the corner of
         * someone else's page, unprompted, before anyone had asked him anything.
         * `statusLine` is null in the dock's steady state anyway; what this
         * removes is the two frames on the way there. */
        statusUtterance={isDock ? echo : inputDisabled ? statusLine : echo}
        inputDisabled={inputDisabled}
        fadeOlder
        sizing={sizing}
        engaged={engaged}
        onEngagedChange={onEngagedChange}
      />
      {/* Block cursor. left/top/width/height are viewport coords from
          caretMetrics — position:fixed (set in the theme CSS) resolves them
          against the viewport. */}
      {caretBox && (
        <span
          className="pc-input-caret"
          aria-hidden="true"
          style={{
            left: caretBox.x,
            top: caretBox.top,
            width: caretBox.width,
            height: caretBox.height,
          }}
        />
      )}
    </div>
  )
}
