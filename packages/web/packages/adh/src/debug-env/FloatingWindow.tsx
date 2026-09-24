'use client'

import {
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import { createPortal } from 'react-dom'
import { X } from 'lucide-react'

import { Button } from '@agenticdevelopertoolkit/ui/components/button'
import { PHONE_SHEET_CLASSES } from '@agenticdevelopertoolkit/ui/components/dialog'
import { PHONE_MAX_WIDTH, useMediaQuery } from '@agenticdevelopertoolkit/ui/hooks/useMediaQuery'
import { useIsMounted } from '../hooks/useIsMounted'

// A macOS-style floating window: NO backdrop, so the live page stays visible behind
// it. Draggable by its title bar, resizable from the corner. Dismisses on Escape or the
// × button ONLY — clicking the page does NOT close it, so you can interact with the live
// page for preview while the window stays open. Portaled to <body> so nothing clips it.
//
// Size is UNCONTROLLED: the initial size is written to the element once (before paint)
// and `resize: both` owns it thereafter — React never re-applies width/height while it
// floats, so a user resize sticks across re-renders with no ResizeObserver and no
// per-frame churn.
// Only `pos` (drag) is React state; a viewport resize re-fits `pos` so the window stays
// whole on screen.
//
// On a PHONE (PHONE_MAX_WIDTH — Tailwind's `max-sm`, the line the shared dialog's phone sheet
// switches at too) it is a full-screen sheet instead: a floating, draggable window cannot
// fit — its 520px floor overflowed a 390px iPhone, putting the × off-screen — and there is no
// "page behind it" worth previewing at that width. Drag and the corner resize are off there;
// the × and Escape still close it. The sheet is the shared dialog's own (PHONE_SHEET_CLASSES,
// what `DialogContent sheetOnPhone` wears), sized by CSS, never in measured px.

type Point = { x: number; y: number }

// The furthest right and down the window's corner can sit with its whole box on screen.
// Read from the element's REAL box, not the size requested on open: the min-width/height
// floor can make it bigger than that, and a user resize can make it anything.
function roomFor(el: HTMLElement): Point {
  return { x: window.innerWidth - el.offsetWidth, y: window.innerHeight - el.offsetHeight }
}

// `p` moved left/up just far enough to fit that room, never past the viewport's top-left
// corner (a box bigger than the viewport is shrunk by its 100vw/100dvh caps, not moved off
// the far side). Returns `p` itself when it already fits, so React skips the re-render.
function fitInto(p: Point, room: Point): Point {
  const x = Math.max(0, Math.min(p.x, room.x))
  const y = Math.max(0, Math.min(p.y, room.y))
  return x === p.x && y === p.y ? p : { x, y }
}

export function FloatingWindow({
  open,
  onClose,
  title,
  children,
}: {
  open: boolean
  onClose: () => void
  title: ReactNode
  children: ReactNode
}) {
  const ref = useRef<HTMLDivElement>(null)
  const mounted = useIsMounted()
  const titleId = useId()
  const [pos, setPos] = useState<Point | null>(null)
  const initialSize = useRef<{ w: number; h: number } | null>(null)
  const dragTeardown = useRef<(() => void) | null>(null)
  const compact = useMediaQuery(PHONE_MAX_WIDTH)

  // Centered placement + initial size each time it opens, and again when the viewport
  // crosses the phone line (a phone rotating) — the floating geometry is recomputed for
  // whichever side it lands on. The sheet gets NO size here: a size measured once went
  // stale on the next change that stayed on the phone side (a 400px window widened to
  // 620px kept a 400px sheet with the live page beside it, since nothing re-renders for
  // a resize that does not cross the line). Its size is the shared sheet's classes instead,
  // which follow every change for free.
  useEffect(() => {
    if (!open) return
    if (compact) {
      initialSize.current = null
      setPos({ x: 0, y: 0 })
      return
    }
    const w = Math.min(1400, Math.round(window.innerWidth * 0.95))
    const h = Math.min(920, Math.round(window.innerHeight * 0.88))
    initialSize.current = { w, h }
    setPos({
      x: Math.round((window.innerWidth - w) / 2),
      y: Math.round((window.innerHeight - h) / 2),
    })
  }, [open, compact])

  // Apply the initial size to the element ONCE, before paint (no flash). After this
  // the native corner resize owns width/height; the floating window never sets them via
  // React style. Then fit the corner to the box that actually rendered — the centring
  // above used the REQUESTED size, and on a short screen (a landscape phone is wider than
  // the phone line, so it floats) the min-height floor makes the box taller than that,
  // which pushed its bottom edge off-screen.
  useLayoutEffect(() => {
    const el = ref.current
    if (!el || !initialSize.current) return
    el.style.width = `${initialSize.current.w}px`
    el.style.height = `${initialSize.current.h}px`
    initialSize.current = null
    const room = roomFor(el)
    setPos((p) => (p ? fitInto(p, room) : p))
  })

  // Re-fit on every viewport resize while floating. The box's 100vw/100dvh caps shrink a
  // window that no longer fits, but they cannot move its corner: a window opened at 2560px
  // (corner at x=580) and a browser narrowed to 1000px kept its corner at 580, and its ×
  // past the right edge. Shifting the corner first means it only shrinks once it is wider
  // than the viewport itself.
  useEffect(() => {
    if (!open || compact) return
    const onResize = () => {
      const el = ref.current
      if (!el) return
      const room = roomFor(el)
      setPos((p) => (p ? fitInto(p, room) : p))
    }
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [open, compact])

  // Dismiss the window on Escape only (the × button is the other way out). Clicking the
  // page does NOT close it — there's no backdrop, so the page stays live for preview. An
  // overlay opened from INSIDE the window (e.g. the Site-theme "Unsaved changes" prompt, a
  // base-ui Dialog) is portaled to <body>; while one is open, that Escape belongs to IT,
  // not us, so we must not tear the whole window down underneath it (else the prompt closes
  // AND our onClose fires → a fresh guarded close-prompt double-fires). base-ui stamps an
  // OPEN popup with `[data-open]`; a modal dialog popup also carries `role="dialog"`. The
  // window itself is a plain `role="dialog"` div with NO `data-open`, so we detect a nested
  // overlay as any OPEN dialog popup other than us. We SAMPLE that in the capture phase
  // (before base-ui processes the key) and only close in the bubble phase if none was open —
  // and a child that owns the key (a nested overlay, or a Monaco widget) stops propagation
  // before the bubble fires.
  useEffect(() => {
    if (!open) return
    // A base-ui overlay popup (Dialog/Menu/Select/Popover) is portaled to <body> and marked
    // `[data-open]` while visible; the window is `role="dialog"` with no `data-open`.
    const nestedOverlayOpen = () => !!document.querySelector('[data-open][role="dialog"]')
    let escapeBelongedToNested = false
    const onKeyCapture = (e: KeyboardEvent) => {
      if (e.key === 'Escape') escapeBelongedToNested = nestedOverlayOpen()
    }
    const onKeyBubble = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !escapeBelongedToNested) onClose()
    }
    window.addEventListener('keydown', onKeyCapture, true)
    window.addEventListener('keydown', onKeyBubble)
    return () => {
      window.removeEventListener('keydown', onKeyCapture, true)
      window.removeEventListener('keydown', onKeyBubble)
    }
  }, [open, onClose])

  // Tear down any in-flight drag listeners on unmount (e.g. closed mid-drag).
  useEffect(() => () => dragTeardown.current?.(), [])

  const onHeaderPointerDown = useCallback(
    (e: React.PointerEvent) => {
      if (!pos || compact || e.button !== 0) return
      const startX = e.clientX
      const startY = e.clientY
      const origin = { ...pos }
      const move = (ev: PointerEvent) => {
        const w = ref.current?.offsetWidth ?? 0
        // Keep the title bar reachable (don't let the window escape entirely).
        setPos({
          x: Math.max(120 - w, Math.min(origin.x + (ev.clientX - startX), window.innerWidth - 120)),
          y: Math.max(0, Math.min(origin.y + (ev.clientY - startY), window.innerHeight - 44)),
        })
      }
      const teardown = () => {
        window.removeEventListener('pointermove', move)
        window.removeEventListener('pointerup', teardown)
        dragTeardown.current = null
      }
      dragTeardown.current = teardown
      window.addEventListener('pointermove', move)
      window.addEventListener('pointerup', teardown)
    },
    [pos, compact],
  )

  if (!open || !mounted || !pos) return null

  // z-50 is the shared overlay tier (dialog/popover/dropdown all sit here). An overlay
  // opened from inside this window — e.g. the Site-theme "Unsaved changes" prompt, a
  // base-ui Dialog — is portaled to <body> at that same z-50, so it stacks above the
  // window by DOM order. An arbitrarily higher value (was z-[1000]) painted OVER those
  // overlays, hiding them behind the window while the modal trap blanked the rest of the
  // console — the popup looked dead. Stay in the tier.
  return createPortal(
    <div
      ref={ref}
      role="dialog"
      aria-labelledby={titleId}
      className={
        compact
          ? `fixed z-50 flex flex-col overflow-hidden bg-apt-surface text-apt-text ${PHONE_SHEET_CLASSES}`
          : 'fixed z-50 flex flex-col overflow-hidden rounded-xl border border-apt-border bg-apt-surface text-apt-text shadow-2xl'
      }
      style={
        compact
          ? // The sheet's geometry and its notch inset are the shared classes above. This style
            // only takes width and height back from the floating window, which wrote them in px
            // on this same element (a rotation across the line keeps the node): a style beats a
            // class, so left alone they would pin the sheet at the floating size. React clears a
            // property it is handed as '' — and, owning them, writes nothing more, so nothing
            // goes stale when the viewport changes without crossing the line.
            { width: '', height: '' }
          : {
              left: pos.x,
              top: pos.y,
              resize: 'both',
              // The floor never exceeds the viewport: CSS lets min-width beat max-width, so a
              // bare 520 x 360 floor overran the caps below on a narrow or short screen.
              minWidth: 'min(520px, 100vw)',
              minHeight: 'min(360px, 100dvh)',
              // Capped at the VIEWPORT: the size is fixed on open, so without a cap a window
              // opened at 1600px and a browser then narrowed to 700 kept its 1400px box running
              // off the right edge — and the HTDV inside fitted its lists to that off-screen
              // width, so nothing ever covered (item 23's sweep). The resize re-fit above moves
              // the corner so the capped box is on screen. NOT the room right of and below the
              // corner, as this once was: that cap moved with `pos`, so every drag RESIZED the
              // window, and the HTDV refitted its rails on each pointermove.
              maxWidth: '100vw',
              maxHeight: '100dvh',
            }
      }
    >
      <div
        onPointerDown={onHeaderPointerDown}
        className={
          compact
            ? 'flex shrink-0 select-none items-center justify-between border-b border-apt-border bg-apt-bg px-4 py-2'
            : 'flex shrink-0 cursor-move select-none items-center justify-between border-b border-apt-border bg-apt-bg px-5 py-3'
        }
      >
        <span id={titleId} className="font-mono text-sm text-apt-gold">
          {title}
        </span>
        <Button
          variant="ghost"
          size="icon-xs"
          aria-label="Close"
          onClick={onClose}
          className="text-apt-text-muted hover:text-apt-text"
        >
          <X className="size-4" />
        </Button>
      </div>
      <div className="flex min-h-0 flex-1 flex-col">{children}</div>
    </div>,
    document.body,
  )
}
