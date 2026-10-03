/**
 * Fixed name for the Supabase auth cookie.
 *
 * By default supabase-js derives the storage key from the Supabase URL —
 * `sb-${hostname.split(".")[0]}-auth-token` — so `127.0.0.1` yields
 * `sb-127-auth-token` and `192.168.1.229` yields `sb-192-auth-token`.
 *
 * Locally the dashboard and Supabase are served from the *same host* on
 * different ports, and cookies are not port-scoped: every cookie the dashboard
 * sets is also sent to Kong on :54321. Changing NEXT_PUBLIC_SUPABASE_URL
 * therefore leaves the old cookie behind and starts a second one, and the two
 * together exceed the realtime server's MAX_HEADER_LENGTH (4096) — the
 * WebSocket upgrade is answered with 431 and realtime silently stops working.
 *
 * Pinning the name keeps it at one cookie regardless of which host the URL
 * points at. See LOCAL-DEV.md → "Realtime".
 */
export const AUTH_COOKIE_NAME = "sb-midday-auth-token";
