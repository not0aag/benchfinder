import { describe, expect, it } from 'vitest';

import {
  VERIFICATION_STATES,
  canTransitionVerification,
  isVerificationState,
} from './verificationState.js';

describe('canTransitionVerification', () => {
  it('allows confirmation from unconfirmed and community', () => {
    expect(canTransitionVerification('unconfirmed', 'confirmed')).toBe(true);
    expect(canTransitionVerification('community', 'confirmed')).toBe(true);
  });

  it('allows disputing from every state', () => {
    for (const from of VERIFICATION_STATES) {
      if (from === 'disputed') continue;
      expect(canTransitionVerification(from, 'disputed')).toBe(true);
    }
  });

  it('never allows demotion of verified except to disputed', () => {
    expect(canTransitionVerification('verified', 'unconfirmed')).toBe(false);
    expect(canTransitionVerification('verified', 'community')).toBe(false);
    expect(canTransitionVerification('verified', 'confirmed')).toBe(false);
  });

  it('never allows a self-transition', () => {
    for (const state of VERIFICATION_STATES) {
      expect(canTransitionVerification(state, state)).toBe(false);
    }
  });

  it('lets moderation resolve a dispute to any other state', () => {
    for (const to of VERIFICATION_STATES) {
      if (to === 'disputed') continue;
      expect(canTransitionVerification('disputed', to)).toBe(true);
    }
  });
});

describe('isVerificationState', () => {
  it('accepts every known state and rejects unknown strings', () => {
    for (const state of VERIFICATION_STATES) {
      expect(isVerificationState(state)).toBe(true);
    }
    expect(isVerificationState('published')).toBe(false);
    expect(isVerificationState('')).toBe(false);
  });
});
