import { describe, expect, it } from 'vitest'
import {
  SWIPE_EDGE_GUTTER,
  SWIPE_MAX_DURATION_MS,
  SWIPE_MIN_DISTANCE,
  classifySwipe,
} from '../SwipeHistory'

const WIDTH = 390
const at = (x: number, y = 300, t = 0) => ({ x, y, t })

describe('classifySwipe', () => {
  it('a rightward flick is back, a leftward one forward', () => {
    expect(classifySwipe(at(100), at(100 + SWIPE_MIN_DISTANCE + 1, 300, 200), WIDTH)).toBe('back')
    expect(classifySwipe(at(300), at(300 - SWIPE_MIN_DISTANCE - 1, 300, 200), WIDTH)).toBe('forward')
  })

  it('ignores travel shorter than the minimum', () => {
    expect(classifySwipe(at(100), at(100 + SWIPE_MIN_DISTANCE - 1, 300, 100), WIDTH)).toBeNull()
  })

  it('ignores a slow drag', () => {
    expect(classifySwipe(at(100), at(250, 300, SWIPE_MAX_DURATION_MS + 1), WIDTH)).toBeNull()
  })

  it('ignores a mostly-vertical scroll that drifts sideways', () => {
    expect(classifySwipe(at(100, 100), at(200, 260, 200), WIDTH)).toBeNull()
  })

  it('leaves edge swipes to the browser, which already navigates on them', () => {
    expect(classifySwipe(at(SWIPE_EDGE_GUTTER - 1), at(250, 300, 200), WIDTH)).toBeNull()
    expect(classifySwipe(at(WIDTH - SWIPE_EDGE_GUTTER + 1), at(100, 300, 200), WIDTH)).toBeNull()
  })
})
