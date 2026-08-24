# Telemetry & phone-home removal

This fork has had Midday's telemetry and its hardcoded calls back to
Midday-operated infrastructure removed, so the app can be run and evaluated
without reporting to anyone.

Scope: **only** analytics and Midday-owned endpoints. Ordinary third-party
integrations (Plaid, Teller, GoCardless, OpenAI, Gemini, Mistral, Anthropic,
Trigger.dev, Resend, Polar/Stripe, Typesense, Plain, Exa) were deliberately left
alone — none of them fire without their API keys, and enabling them is a
deliberate choice.

---

## 1. OpenPanel analytics — removed

Upstream mounted `<OpenPanelComponent>` in both the dashboard and website root
layouts. The event *sending* was gated on `NODE_ENV === "production"`, but the
SDK renders `<Script src="https://openpanel.dev/op1.js">` with **no `clientId`
guard**, so the third-party script loaded on every page even with the client ID
blank. Server-side events posted to `https://api.openpanel.dev`.

`@openpanel/nextjs` also pulls in `@openpanel/web` → **`rrweb`** (session
recording).

| File | Change |
|---|---|
| `packages/events/src/client.tsx` | `Provider` → renders `null`; `track()` → no-op; added a no-op `useOpenPanel()` shim |
| `packages/events/src/server.ts` | `setupAnalytics()` → returns a no-op `track` |
| `packages/events/package.json` | dropped `@openpanel/nextjs` |
| `apps/dashboard/src/app/[locale]/layout.tsx` | removed `<Analytics />` + import |
| `apps/website/src/app/layout.tsx` | removed `<Analytics />` + import |
| `apps/dashboard/src/**` (37 files) | imported `useOpenPanel` **directly** from `@openpanel/nextjs`, bypassing the wrapper — repointed to `@midday/events/client` |
| `apps/website/package.json` | dropped `@openpanel/nextjs` and the unused `@openstatus/react` |
| `.env-example` / `.env-template` | removed `NEXT_PUBLIC_OPENPANEL_CLIENT_ID`, `OPENPANEL_SECRET_KEY` |

`@openpanel/*` and `rrweb` are gone from `bun.lock` and `node_modules`.

The `LogEvents` constants and all ~65 `track(...)` call sites were left in place
so the diff stays small and reviewable — they now call into a no-op.

## 2. Bank-logo CDN — made local by default

`cdn-engine.midday.ai` was hardcoded, so every dashboard render sent the
viewer's IP plus the institution IDs of their connected banks to Midday's CDN.

- `packages/banking/src/utils/logo.ts` — exports `LOGO_CDN_PREFIX`, driven by
  `BANK_LOGO_CDN_URL`. Unset → `/bank-logos/`, served locally.
- `packages/banking/src/sync-logos.ts` — uses the shared prefix.
- `apps/dashboard/src/components/bank-logo.tsx` — both remote `default.jpg`
  fallbacks replaced with locally-rendered initials.

To host logos yourself: set `BANK_LOGO_CDN_URL` to your own R2/S3 origin and run
`syncInstitutionLogos()`, which downloads them from the banking providers.

## 3. Desktop app — SaaS shell and auto-updater removed

The desktop app was a Tauri shell around **Midday's hosted product**, not a
self-hosted instance, and would install updates signed by Midday's key.

- `tauri.conf.json` — removed the entire `updater` block: the
  `https://api.midday.ai/desktop/update` endpoint, Midday's minisign `pubkey`,
  and `dangerousInsecureTransportProtocol: true`. `createUpdaterArtifacts` → `false`.
- `src-tauri/src/lib.rs` — `get_app_url()` now reads `MIDDAY_APP_URL` (default
  `http://localhost:3001`); it no longer falls back to `app.midday.ai` /
  `beta.midday.ai`. Updater plugin registration, `silent_update_check` body, and
  `prompt_and_install_update` removed; `check_for_updates` reports that
  auto-update is disabled.
- `capabilities/desktop.json` + `Cargo.toml` — dropped `updater:*` permissions
  and `tauri-plugin-updater`.

> Not rebuilt — no Rust toolchain was run against this. `cargo check` before
> trusting the desktop app specifically.

## 4. Hardcoded `*.midday.ai` fallbacks — repointed local

`packages/utils/src/envs.ts` resolved `getAppUrl()` / `getApiUrl()` /
`getEmailUrl()` / `getCdnUrl()` to Midday production hosts whenever
`NODE_ENV === "production"` and no override was set — so a misconfigured
self-hosted deploy quietly pointed at Midday. All four now fall back to
localhost and log a warning in production builds. New env vars: `DASHBOARD_URL`,
`API_URL`, `EMAIL_URL`, `CDN_URL`.

Inline `process.env.X || "https://api.midday.ai"` fallbacks were also repointed
in: the dashboard invoice payment modal, `apps/api` (11 files: OpenAPI server
metadata, OAuth callbacks, MCP, well-known, invoice-payments, chat, bot runtime),
and `packages/cli/src/utils/env.ts`.

Other specifics:

- `apps/api/src/mcp/tools/invoices.ts` — the logo-fetch SSRF allowlist was
  pinned to `https://service.midday.ai/`; now follows `SUPABASE_URL`, and denies
  everything (skipping the fetch) when that's unset.
- `apps/api/src/trpc/routers/oauth-applications.ts` — submitting an OAuth app
  for review emailed your **team name and account email to `pontus@midday.ai`**.
  Now routed to `APP_REVIEW_EMAIL` and skipped entirely when unset.
- `apps/api/src/bot/runtime.ts` — contact card fetched from `cdn.midday.ai`;
  now skipped unless `BOT_CONTACT_CARD_URL` is set.
- Dashboard OG-image routes (3 files) fetched fonts from `cdn.midday.ai` at
  render time; now driven by `CDN_URL` / `NEXT_PUBLIC_CDN_URL`.
- Slack links hardcoded to `app.midday.ai` in 5 files → `MIDDAY_DASHBOARD_URL`.
- `packages/email` — 7 `go.midday.ai/*` click-tracking shortlinks (including the
  "Reconnect" CTAs in the connection-expiry emails) → configured app/website URL.

## 5. Found by actually running it

Three things static analysis missed, caught on the first boot of `apps/website`:

- **`<link rel="preconnect" href="https://cdn.midday.ai">`** (plus `dns-prefetch`)
  in `apps/website/src/app/layout.tsx`. A preconnect opens a real TCP+TLS
  connection to Midday's CDN on every page load whether or not any asset from it
  is used. Both hints removed.
- **Turborepo telemetry was enabled** and phoned home to Vercel during the dev
  run — build-toolchain telemetry, entirely outside the application source I had
  been grepping. Disabled via `turbo telemetry disable`. Note this is a
  **global** setting (`~/Library/Application Support/turborepo/telemetry.json`),
  not per-repo; re-enable with `turbo telemetry enable`.
- **`next/font/google`** (both layouts) fetches the Hedvig font files from
  Google at *build* time and self-hosts them. The browser never contacts Google,
  so this is benign and was left alone — noted here so the `1e100.net`
  connections in a network capture aren't mistaken for a runtime beacon.

### Still reaching Midday's CDN on the marketing site

`apps/website` is Midday's own advertising material and is welded to their asset
hosts. Its homepage still pulls a hero poster from `cdn.midday.ai` via
`<link rel="preload" as="image">`, and preloads **192 integration logos from
`logos.composio.dev`**. Neither is telemetry — they're image CDNs — but both
leak the visitor's IP to a third party.

This was left as-is because the marketing site isn't needed to run Midday as an
app. If you ever do serve it publicly, vendor those assets first.

## 6. README

Removed the **Repobeats tracking pixel** (`repobeats.axiom.co`) and the Supabase
badge wrapped in a `go.midday.ai` referral redirect.

---

## Deliberately left alone

- **Sentry** (`apps/dashboard/sentry.*.config.ts`, `apps/{api,worker}/src/instrument.ts`)
  — reports to *your* DSN, not Midday's, and is inert while `SENTRY_DSN` /
  `NEXT_PUBLIC_SENTRY_DSN` are unset. If you ever enable it, note the dashboard
  config turns on **session replay** (10% of sessions, 100% of error sessions)
  and the api/worker configs set **`sendDefaultPii: true`**.
- **Marketing copy on `apps/website`** — the `mcp-*.tsx` / `sdks.tsx` components
  display `https://api.midday.ai/mcp` as setup instructions. Rendered strings,
  not requests. Wrong for a self-hosted instance but harmless.
- **Midday branding and outbound links** (`midday.ai` in footers, login page,
  terms) — plain anchors a user would have to click.
- `from:` addresses on transactional email are still `@midday.ai`; they need a
  domain you control before Resend will send anyway.

## Verification

`bun install` clean; `tsc --noEmit` passes for `apps/api`, `apps/dashboard`,
`packages/{utils,events,banking,cli,email,app-store}`. `apps/website` has 16
pre-existing type errors in files untouched here (both Next apps ship
`typescript.ignoreBuildErrors: true`).

`apps/website` was booted and its served HTML inspected: no `openpanel`,
`op1.js`, `rrweb`, `repobeats`, or `cdn-engine` references remain, and no
preconnect to any Midday host. A network monitor (`netwatch.local/`, gitignored)
watched all user-owned processes during the run — that's what caught the
Turborepo telemetry.

`apps/dashboard` has **not** been run: it needs a Supabase instance (auth +
storage) that upstream never shipped a local setup for. See below.
