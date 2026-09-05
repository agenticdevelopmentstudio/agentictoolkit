import { describe, it, expect } from 'vitest';
import { commitFullMessage } from '../src/monitor/format';

describe('commitFullMessage', () => {
  it('returns null for empty input', () => {
    expect(commitFullMessage(null)).toBeNull();
    expect(commitFullMessage(undefined)).toBeNull();
    expect(commitFullMessage('')).toBeNull();
    expect(commitFullMessage('   \n  ')).toBeNull();
  });

  it('keeps the whole message including body newlines', () => {
    expect(commitFullMessage('subject')).toBe('subject');
    expect(commitFullMessage('subject\n\nbody line 1\nbody line 2')).toBe('subject\n\nbody line 1\nbody line 2');
  });

  it('strips trailing whitespace but not internal newlines', () => {
    expect(commitFullMessage('subject\n\nbody\n\n')).toBe('subject\n\nbody');
  });

  it('caps at max chars', () => {
    expect(commitFullMessage('x'.repeat(50), 10)).toBe('x'.repeat(10));
  });
});
