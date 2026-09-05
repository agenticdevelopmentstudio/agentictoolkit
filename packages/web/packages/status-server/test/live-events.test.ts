import { describe, it, expect, afterEach, vi } from 'vitest';
import {
  subscribeLive,
  publishSnapshot,
  recentSnapshot,
  liveSubscriberCount,
  resetLiveEvents,
} from '../src/live/live-events';
import type { LiveSnapshot } from '../src/monitor/live-types';
import { liveSnapshot } from './helpers/snapshot';

const snap = (generatedAt: string): LiveSnapshot => liveSnapshot({ generatedAt });

describe('live-events pub/sub', () => {
  afterEach(() => resetLiveEvents());

  it('fans one published snapshot out to every subscriber', () => {
    const a: LiveSnapshot[] = [];
    const b: LiveSnapshot[] = [];
    subscribeLive((s) => a.push(s));
    subscribeLive((s) => b.push(s));
    expect(liveSubscriberCount()).toBe(2);

    const s = snap('2026-06-30T00:00:00.000Z');
    publishSnapshot(s);

    // The SAME object reaches every subscriber — one build, N deliveries.
    expect(a).toEqual([s]);
    expect(b).toEqual([s]);
    expect(a[0]).toBe(s);
    expect(b[0]).toBe(s);
  });

  it('stops delivering after unsubscribe', () => {
    const got: LiveSnapshot[] = [];
    const off = subscribeLive((s) => got.push(s));
    publishSnapshot(snap('1'));
    off();
    publishSnapshot(snap('2'));
    expect(got.map((s) => s.generatedAt)).toEqual(['1']);
    expect(liveSubscriberCount()).toBe(0);
  });

  it('a throwing subscriber never blocks the fan-out to the others', () => {
    const got: string[] = [];
    subscribeLive(() => {
      throw new Error('boom');
    });
    subscribeLive((s) => got.push(s.generatedAt));
    publishSnapshot(snap('ok'));
    expect(got).toEqual(['ok']);
  });

  it('recentSnapshot serves the last published snapshot within the age window, else null', () => {
    vi.useFakeTimers();
    try {
      expect(recentSnapshot(1000)).toBeNull(); // nothing published yet
      const s = snap('2026-06-30T00:00:00.000Z');
      publishSnapshot(s);
      expect(recentSnapshot(1000)).toBe(s); // fresh
      vi.advanceTimersByTime(1500);
      expect(recentSnapshot(1000)).toBeNull(); // aged out
    } finally {
      vi.useRealTimers();
    }
  });
});
