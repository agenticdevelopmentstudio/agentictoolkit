'use client'

import { useCallback, useEffect, useRef, useState, type KeyboardEvent } from 'react'
import type { ChatBackend, GazeVector } from '@agenticdevelopertoolkit/chat'
import type { ThemeKey } from '@agenticdevelopertoolkit/themes'
import { useKeyboardInset } from '@agenticdevelopertoolkit/viewport'
import { BitbagChat } from './BitbagChat'
import { BitbagInfo } from './BitbagInfo'
import { Bitbag, type BitbagExpression } from './avatar'
import { DEFAULT_THEME } from './voice'

export interface BitbagDockProps {
  /** The toolkit theme that skins his chat. Defaults to the adh house style. */
  theme?: ThemeKey
  /**
   * The chat backend driving his conversation. Defaults to bitbag's built-in
   * scripted mock; pass a real `ChatBackend` to wire him to a live service.
   */
  backend?: ChatBackend
  /** Pixel width of bitbag himself. Default 132 — he rides above his own chat. */
  size?: number
  /** Extra classes on the dock column — the host's positioning wrapper. */
  className?: string
  /**
   * What he looks like while nobody is talking to him.
   *
   * - `'entry'` (default) — his chat folds to a single entry line and he dozes on
   *   top of it. fishlamp's rig: there the dock is the page's only chrome on the
   *   bottom edge, so an always-visible composer is an invitation, not clutter.
   * - `'avatar'` — his face alone, at half size, with no entry line under him.
   *   For a host whose bottom edge is already a bar of its own (the adh footer):
   *   a 560px composer across the middle of it covered the bar's links and made
   *   every page reserve room for it. Tapping him opens his chat under him, with
   *   the caret in it; when the chat folds (a tap away, Escape) he goes back to
   *   being just a face.
   */
  rest?: 'entry' | 'avatar'
}

/**
 * bitbag as a FIXTURE: his face riding just above his chat, in a column that
 * hugs whatever edge the host parks it on. Idle he folds down to a single entry
 * line and dozes at half size; reach for him and he wakes and grows upward.
 *
 * The sibling of `BitbagStage`, and the difference between them is only how he
 * occupies the page. The stage is for a site where bitbag IS the page and being
 * summoned is the joke; the dock is for the corner of a page about something
 * else, where he arrives already connected because a fixture that won't answer
 * until it has finished performing just reads as broken. Both drive the same
 * `BitbagChat` (see `BitbagVariant`), so his voice and reflexes can't fork.
 *
 * WHERE HE PARKS IS PART OF HIM: the column fixes itself to the bottom of the
 * viewport, centred, riding above the on-screen keyboard when one opens. That
 * used to be left to the host, and the result was that every host invented its
 * own — fishlamp.com's fixed rig against the adh footer's absolute strip — which
 * is drift in the one dimension the two mountings were supposed to share. The
 * geometry now lives in `bitbag-dock.css` next to the scrim that dims the page
 * behind him, because the two only make sense together. A host that genuinely
 * needs him elsewhere overrides `.bb-dock` from its own stylesheet.
 *
 * The column ignores the pointer while its children take their own clicks, so
 * the empty air around him never eats a scroll or tap meant for the page behind.
 */
export function BitbagDock({
  theme = DEFAULT_THEME,
  backend,
  size = 132,
  className,
  rest = 'entry',
}: BitbagDockProps) {
  // The wiring between his chat and his face: the chat reports how the
  // conversation is going and the avatar reacts. His expression follows the
  // chat's mood hints, his eyes follow the caret, and his idle chatter is muted
  // while he's working so the status line holds the thinking spinner, not his
  // asides.
  // He sits on the bottom edge, which is exactly where a phone keyboard opens.
  // The hook publishes the keyboard's height as `--kb-inset` and the dock's CSS
  // rides its `bottom` on it, so tapping his composer lifts him clear instead of
  // burying him under the keys.
  useKeyboardInset()

  const [chatHint, setChatHint] = useState<BitbagExpression | null>(null)
  const [gaze, setGaze] = useState<GazeVector | null>(null)
  const [utterance, setUtterance] = useState<{ text: string; id: number } | null>(null)
  const [mute, setMute] = useState(false)
  // The avatar element the chat measures gaze against — his eyes track the caret
  // relative to this frame's horizontal centre.
  const bitbagRef = useRef<HTMLDivElement>(null)
  const utterId = useRef(0)

  const onHint = useCallback((hint: BitbagExpression | null) => setChatHint(hint), [])
  const onGaze = useCallback((g: GazeVector | null) => setGaze(g), [])
  const onMute = useCallback((m: boolean) => setMute(m), [])
  const onSpeak = useCallback((text: string) => {
    utterId.current += 1
    setUtterance({ text, id: utterId.current })
  }, [])

  // The avatar-only rest. `open` is whether his chat is shown at all; whether it is
  // ENGAGED stays the chat's own fact (`.pc-collapsed`, owned by its sizing hook), and
  // this only follows it: the fold that ends a conversation is what puts him back to
  // rest, so there is one "done talking" signal rather than a second one to drift.
  const avatarRest = rest === 'avatar'
  const [open, setOpen] = useState(false)
  const rootRef = useRef<HTMLDivElement>(null)
  // Read at pointerdown, before the chat's own document listener folds it: a tap on
  // him while he is talking is that fold, and the click that follows must close, not
  // reopen. Closing explicitly as well covers the one case the fold does not — a chat
  // opened while its composer was still disabled, which never engaged to fold back.
  const openAtPress = useRef(false)

  useEffect(() => {
    if (!avatarRest || !open) return
    const root = rootRef.current
    if (!root) return
    // Opening shows a chat that is still folded; the caret going in is what engages
    // it. So "folded" alone cannot mean "done" — only folded AFTER having been
    // engaged does, or he would shut the instant he opened.
    let engaged = false
    const sync = (): void => {
      const chat = root.querySelector('.persona-chat')
      if (!chat) return
      if (!chat.classList.contains('pc-collapsed')) engaged = true
      else if (engaged) setOpen(false)
    }
    const observer = new MutationObserver(sync)
    observer.observe(root, { subtree: true, attributes: true, attributeFilter: ['class'] })
    root.querySelector<HTMLInputElement>('.pc-input')?.focus()
    sync()
    return () => observer.disconnect()
  }, [avatarRest, open])

  const onAvatarClick = (): void => {
    const wasOpen = openAtPress.current
    openAtPress.current = false
    setOpen(!wasOpen)
  }
  const onAvatarKey = (e: KeyboardEvent<HTMLDivElement>): void => {
    if (e.key !== 'Enter' && e.key !== ' ') return
    e.preventDefault()
    setOpen((o) => !o)
  }

  // Resting, he is laid out at half width rather than scaled to it: a transform leaves
  // the full-size box in place, and that invisible box would sit over the host bar's
  // own controls taking their clicks.
  const resting = avatarRest && !open
  const rootClass = [
    'bb-dock',
    avatarRest && 'bb-dock--rest-avatar',
    resting && 'bb-dock--resting',
    className,
  ]
    .filter(Boolean)
    .join(' ')

  return (
    <div ref={rootRef} className={rootClass}>
      <div
        ref={bitbagRef}
        className="bb-dock__avatar"
        style={{ width: resting ? size / 2 : size }}
        {...(avatarRest
          ? {
              role: 'button',
              tabIndex: 0,
              'aria-label': open ? 'bitbag' : 'Chat with bitbag',
              'aria-expanded': open,
              onPointerDown: () => {
                openAtPress.current = open
              },
              onClick: onAvatarClick,
              onKeyDown: onAvatarKey,
            }
          : {})}
      >
        <Bitbag expression={chatHint ?? undefined} gaze={gaze} onSpeak={onSpeak} mute={mute} />
      </div>
      {/* The panel is the frame his chat and his `i` share: it fixes the box's
          width (the column itself is viewport-wide, so the chat can't set it)
          and gives the `i` a corner to hang off. */}
      <div className="bb-dock__panel" hidden={resting}>
        <BitbagChat
          className="bb-dock__chat"
          variant="dock"
          theme={theme}
          backend={backend}
          anchorRef={bitbagRef}
          onExpressionHint={onHint}
          onGazeHint={onGaze}
          utterance={utterance}
          onMute={onMute}
        />
        <BitbagInfo />
      </div>
    </div>
  )
}
