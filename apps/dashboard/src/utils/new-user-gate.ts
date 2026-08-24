export const NEW_USER_CUTOFF = "2026-04-20T00:00:00.000Z";

/**
 * Sunset gate for Midday's hosted product.
 *
 * Upstream blocked any account created on or after NEW_USER_CUTOFF and showed
 * a "You're on the waitlist" screen instead, because the SaaS stopped taking
 * new sign-ups while winding down. On a self-hosted instance there is no
 * waitlist and no sign-up queue — every account you create is a new one, so
 * this gate locks you out of your own deployment.
 *
 * Disabled by default. Set NEXT_PUBLIC_ENFORCE_NEW_USER_CUTOFF=true to restore
 * the upstream behaviour.
 */
export function isBlockedNewUser(createdAt: string | null | undefined) {
  if (process.env.NEXT_PUBLIC_ENFORCE_NEW_USER_CUTOFF !== "true") {
    return false;
  }

  if (!createdAt) return false;
  return new Date(createdAt) >= new Date(NEW_USER_CUTOFF);
}
