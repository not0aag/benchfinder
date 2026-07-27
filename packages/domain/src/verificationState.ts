export const VERIFICATION_STATES = [
  'unconfirmed',
  'community',
  'confirmed',
  'verified',
  'disputed',
] as const;

export type VerificationState = (typeof VERIFICATION_STATES)[number];

// Enforcement lives in SECURITY DEFINER functions server-side; this map is the
// shared definition both the RPC layer and the UI reason against.
// Disputed is reachable from every state (2 independent "not there" reports),
// and moderation resolves a dispute to any state.
const ALLOWED_TRANSITIONS: Record<VerificationState, readonly VerificationState[]> = {
  unconfirmed: ['community', 'confirmed', 'verified', 'disputed'],
  community: ['confirmed', 'verified', 'disputed'],
  confirmed: ['verified', 'disputed'],
  verified: ['disputed'],
  disputed: ['unconfirmed', 'community', 'confirmed', 'verified'],
};

export function isVerificationState(value: string): value is VerificationState {
  return (VERIFICATION_STATES as readonly string[]).includes(value);
}

export function canTransitionVerification(from: VerificationState, to: VerificationState): boolean {
  return ALLOWED_TRANSITIONS[from].includes(to);
}
