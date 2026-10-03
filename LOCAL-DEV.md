# Running Midday locally

Upstream never shipped a local-dev setup (their README says the docs are "in
progress"), so this is assembled from the schema and env usage. It works, with
the caveats at the bottom.

Everything runs on your machine. Supabase here is the local Docker stack, not
the hosted service — no account, nothing leaves the network.

## Start

```bash
# 1. Supabase (Postgres 17 + auth + storage + Mailpit)
./node_modules/supabase/bin/supabase start

# 2. Redis
docker start midday-redis   # or: docker run -d --name midday-redis -p 6379:6379 redis:7-alpine

# 3. API  (port 3003)
cd apps/api && bun run dev

# 4. Dashboard  (port 3001)
cd apps/dashboard && bun run dev
```

| Service | URL |
|---|---|
| Dashboard | http://localhost:3001 |
| API | http://localhost:3003 |
| Supabase Studio | http://127.0.0.1:54323 |
| **Mailpit (OTP codes land here)** | **http://127.0.0.1:54324** |
| Postgres | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |

## Logging in

Use the **email** option, not Google/Microsoft — no OAuth provider is
configured locally. On the login screen click **Show other options**; the email
field is below the Microsoft and GitHub buttons.

Enter your address, hit Continue, then read the 6-digit code from **Mailpit**
(http://127.0.0.1:54324). No mail is actually sent.

## Accessing over the LAN

Next 16 blocks cross-origin requests to `/_next/*` dev resources. Without
`allowedDevOrigins`, a LAN visit renders the server HTML but silently blocks
`webpack-hmr`, so **React never hydrates and nothing on the page is clickable** —
buttons look fine and do nothing.

`ALLOWED_DEV_ORIGINS` in `apps/dashboard/.env` handles this. If your LAN IP
changes, update it along with the browser-side URLs in the same file
(`NEXT_PUBLIC_URL`, `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_SUPABASE_URL` — these
are fetched *by the browser*, so `localhost` resolves to the visiting machine,
not this one) and the redirect URLs in `supabase/config.toml`. Restart both the
dashboard and Supabase after changing the latter.

## Things that had to be patched to run outside Midday's infrastructure

- **`apps/dashboard/src/utils/new-user-gate.ts`** — upstream blocks any account
  created after `2026-04-20` and shows "You're on the waitlist", because the
  hosted product stopped taking sign-ups while winding down. Every account on a
  self-hosted instance is newer than that, so this locked you out of your own
  deployment. Disabled by default; set
  `NEXT_PUBLIC_ENFORCE_NEW_USER_CUTOFF=true` to restore it.
- **`handle_new_user` trigger** — lives in Midday's hosted database, not the
  repo. Without it, signup creates an `auth.users` row with no matching
  `public.users` row and the API returns *"User not found"*. Created manually
  (see below).
- **`users_id_fkey`** — `drizzle-kit` can't create a dotted `auth.users` table
  name, so the FK collapsed onto `public.users` itself. Repointed at Supabase's
  real `auth.users`.
- **`generate_inbox` / `nanoid`** — `packages/db/src/schema.ts` introspected two
  hosted defaults as string *literals* rather than function calls
  (`teams.inbox_id` → `'generate_inbox(10)'`, `user_invites.code` →
  `'nanoid(24)'`), and the functions themselves don't exist in this repo either.
  Both columns are `UNIQUE`, so every row got the *same* literal string: the
  first team saved fine and the **second one failed** with `duplicate key value
  violates unique constraint "teams_inbox_id_key"`, surfacing in the UI as a
  generic "something went wrong". The same trap sits on the second team
  *invite*. Both functions are now created and the defaults repointed by
  `scripts/local-db-setup.sh`.
- **Placeholder credentials** in `apps/api/.env` — `packages/banking/src/env.ts`
  requires every bank provider credential via t3-env, and
  `packages/bot/src/instance.ts` eagerly constructs the WhatsApp/Telegram/Slack/
  Sendblue adapters at import time. All are `unused-local`; nothing is
  transmitted.
- **`[analytics] enabled = false`** in `supabase/config.toml` — the Logflare and
  vector containers mount the Docker socket, which fails under Colima.

## CORS: `ALLOWED_API_ORIGINS` is mandatory

`apps/api/src/index.ts` does:

```ts
origin: process.env.ALLOWED_API_ORIGINS?.split(",") ?? []
```

Unset means an **empty allowlist** — every browser request from the dashboard to
the API is blocked with a CORS error, which surfaces in the UI as vague failures
like *"unable to create team"*. It's in `apps/api/.env-template` but easy to miss
when assembling an env by hand, and `curl` testing won't catch it because curl
ignores CORS.

List every origin the dashboard is served from:

```
ALLOWED_API_ORIGINS=http://localhost:3001,http://127.0.0.1:3001,http://192.168.1.229:3001
```

## Missing database functions

Several Postgres functions the app calls are defined **nowhere in this repo** —
they exist only in Midday's hosted Supabase project, like `handle_new_user`.
Each one surfaces as a `TRPCClientError: Failed query` and, on a page that
renders inside an error boundary, as the generic **"Something went wrong"**.

Reimplemented in `scripts/hosted-search-functions.sql` (applied by
`scripts/local-db-setup.sh`), reconstructed from their call sites:

| Function | Called from | Was breaking |
|---|---|---|
| `global_search` | `queries/search.ts:95` | "Find anything" + Overview (prefetched with an empty term) |
| `get_team_bank_accounts_balances` | `queries/bank-accounts.ts:158` | Overview balance widgets |
| `get_bank_account_currencies` | `queries/bank-accounts.ts:170` | Currency selector |
| `get_assigned_users_for_project` | `queries/tracker-projects.ts:204,460` | Tracker project list |
| `total_duration` | `queries/tracker-projects.ts:100` | Tracker project list |
| `get_project_total_amount` | `queries/tracker-projects.ts:104` | Tracker project list |
| `match_similar_documents_by_title` | `queries/documents.ts:243` | Related documents |

Two differ deliberately from upstream: `match_similar_documents_by_title` uses
`pg_trgm` title similarity instead of embeddings (no API key needed), and
`get_assigned_users_for_project` derives assignees from logged time entries.

Still unimplemented: **`global_semantic_search`**. It needs embeddings, and it is
unreachable anyway — `apps/api/src/trpc/routers/search.ts:46` only calls it after
`generateLLMFilters()`, which requires `OPENAI_API_KEY`.

`private.get_teams_for_authenticated_user()` (referenced by 45 RLS policies)
exists locally via `setup-test-db.sql` — but **it was a stub returning no rows**
(`SELECT '000…'::uuid LIMIT 0`), which silently made all 45 policies deny-all.
That went unnoticed because the API connects as `postgres` and bypasses RLS; it
only bites where the **browser** talks to storage or PostgREST directly with the
user's JWT. `local-db-setup.sh` now replaces it with a real `SECURITY DEFINER`
implementation (required — `users_on_team` has RLS of its own, and policies on
that table call this same function).

## Storage buckets

The app uses three buckets; the hosted project has them, the repo doesn't.
`local-db-setup.sh` creates all three:

| Bucket | Public | Used by |
|---|---|---|
| `vault` | no | documents |
| `apps` | yes | app assets |
| `avatars` | **yes** | invoice logo, company logo, user avatar |

`avatars` must be **public**: `packages/supabase/src/utils/storage.ts` returns
`getPublicUrl()` after upload and the result is rendered as a plain `<img src>`.

**Symptom when it's missing:** picking an invoice logo fails with the generic
*"Something went wrong, please try again."* toast — the only error the component
raises (`components/invoice/logo.tsx:37`). Underneath it is
`{"statusCode":"404","error":"Bucket not found"}`, or once the bucket exists but
the policy is missing, `new row violates row-level security policy`.

These uploads run **browser-side with the user's JWT**, not through the API, so
they are subject to storage RLS — and `storage.objects` comes up with RLS enabled
and zero policies. The script adds an `avatars_owner_write` policy keyed on the
first path segment, which is the owning id in all three call sites
(`<teamId>/<file>`, `<teamId>/invoice/<file>`, `<userId>/<file>`).

## `packages/db/migrations/` is not a working migration path

The folder holds 39 numbered `.sql` files, but `meta/_journal.json` lists **one**
entry (`0000_silly_sage`), and nothing in the repo runs `drizzle-kit migrate` —
so the journal and the folder are already out of sync before you touch anything.
`drizzle-kit generate` therefore drops into an interactive rename prompt and
cannot be used non-interactively here.

Schema changes in this fork go in `packages/db/src/schema.ts`, which is the real
source of truth: `local-db-setup.sh` regenerates the full schema from it. Apply
the change to a running database by hand as well — the script only rebuilds.

## Realtime

`drizzle-kit generate` never emits publication membership, so `supabase_realtime`
comes up **empty** and no `postgres_changes` event is ever delivered. This fails
*silently* — the channel still reports `SUBSCRIBED`, so nothing in the UI
complains; live-updating tables just never update. `local-db-setup.sh` now adds
the five tables `useRealtime()` subscribes to (`activities`, `customers`,
`documents`, `inbox`, `transactions`) and sets `REPLICA IDENTITY FULL`, which
UPDATE/DELETE need because the hook filters on `team_id` rather than the PK.

### `[Realtime] Channel error for user-notifications: undefined`

**Resolved 2026-08-25.** The stale-cookie hunch was the right one; `MalformedJWT`
was a red herring from an earlier session. This is a **431 on the WebSocket
upgrade**, visible in the Kong access log:

```
GET /realtime/v1/websocket?apikey=…&vsn=2.0.0 HTTP/1.1" 431 0
```

431 is *Request Header Fields Too Large*. The upgrade never reaches the realtime
container (its log shows only `/api/ping`), so the socket dies at the transport
layer — hence a stack trace that bottoms out in `onConnError`, and an `err`
argument of `undefined`: there is no join reply to carry an error.

The rejection comes from **realtime itself**, not Kong — the 431 carries
`X-Kong-Upstream-Latency`, so Kong proxied it and the upstream answered.
`supabase_realtime_midday` runs with `MAX_HEADER_LENGTH=4096`, and requests start
failing at roughly 5.2 KB of `Cookie`.

Why the jar gets that big: **cookies are not port-scoped**. The dashboard and
Supabase share a host and differ only by port, so every cookie the dashboard sets
on `192.168.1.229:3001` is also sent to Kong on `:54321`. And supabase-js derives
its storage key from the Supabase URL — `` `sb-${hostname.split(".")[0]}-auth-token` ``
— so `127.0.0.1` gives `sb-127-auth-token` while `192.168.1.229` gives
`sb-192-auth-token`. Changing `NEXT_PUBLIC_SUPABASE_URL` (which the LAN section
above tells you to do) leaves the old cookie in place and starts a second one.
One session is ~2.8 KB and fits; two is ~5.6 KB and does not. Only the browser is
affected — a host client sends no cookies, which is why this never reproduced
outside it.

Both halves are fixed:

- `packages/supabase/src/client/cookie-name.ts` pins the cookie to
  `sb-midday-auth-token` across all three clients (browser, server, middleware),
  so the name no longer moves with the Supabase URL host and a second cookie is
  never created.
- **Clear cookies for the dashboard host once** (Firefox: padlock → Clear cookies
  and site data) and log in again. The fix prevents new strays; it cannot delete
  ones already in the browser.

If it returns, check header size before suspecting auth:

```bash
docker logs supabase_kong_midday --tail 50 | grep realtime   # look for 431
```

`GOTRUE_JWT_ISSUER` is still `http://127.0.0.1:54321/auth/v1` while the browser
talks to `192.168.1.229`. That is unrelated — a real user JWT subscribes to
`postgres_changes` without complaint once the socket is established.

## Patched dependency: `next@16.2.1`

`patches/next@16.2.1.patch` (applied by bun via `patchedDependencies` in
`package.json`) fixes an upstream bug in the React RSC dev tracing that Next
vendors. Symptom, on every page load:

```
TypeError: Performance.measure: Given attribute end cannot be negative
  at flushComponentPerformance (react-server-dom-turbopack-client.browser.development.js)
```

In `flushComponentPerformance`, `childrenEndTime` is initialised to `-Infinity`
and stays there when a component has no child reporting a finite end time. Three
`performance.measure()` calls clamp `start` (`0 > startTime ? 0 : startTime`)
but pass `end` raw, so `end: -Infinity` throws. Sibling call sites in the same
file already guard with `supportsUserTiming && 0 < endTime`, so the invariant is
upstream's own — these three branches just omit it. The patch clamps `end` the
same way `start` is clamped, in the browser/edge/node client dev bundles.

It fires from the branch that renders an *errored* component (`color: "error"`,
`… " Errored"`), and the component involved is Next's internal `NotFound`
boundary (its name carries a zero-width-space marker), which is present in every
route tree but never rendered — hence no finite timing.

Dev-only: `flushComponentPerformance` appears in the `.development.js` bundles
and in **none** of the `.production.js` ones, so a production build was never
affected. Re-check this patch on any Next upgrade; if upstream has fixed it,
drop the patch and the `patchedDependencies` entry.

## ⚠️ Never `supabase stop --no-backup`

`--no-backup` **discards the database volume**. The schema, your account, the
storage buckets and the `handle_new_user` trigger all go with it. The symptom is
confusing rather than obvious: login still *succeeds* (GoTrue keeps working),
then every query fails and the app bounces you straight back to `/login`.

Use plain `supabase stop`. If you do wipe it, run `./scripts/local-db-setup.sh`
to rebuild.

## Rebuilding the database from scratch

```bash
./scripts/local-db-setup.sh           # create/refresh schema, keep data
./scripts/local-db-setup.sh --reset   # drop public schema first
```

The script is idempotent and handles everything below. Manual equivalent:

```bash
docker exec supabase_db_midday psql -U postgres -d postgres -c \
  "DROP SCHEMA IF EXISTS public CASCADE; DROP SCHEMA IF EXISTS private CASCADE;
   CREATE SCHEMA public;
   GRANT ALL ON SCHEMA public TO postgres, anon, authenticated, service_role;"

docker exec supabase_db_midday psql -U postgres -d postgres -c \
  "CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS pg_trgm;"

# helper functions the schema depends on (extract_product_names, etc.)
docker cp packages/db/src/test/helpers/setup-test-db.sql supabase_db_midday:/tmp/setup.sql
docker exec supabase_db_midday psql -U postgres -d postgres -f /tmp/setup.sql
# the two "permission denied for schema auth" errors are expected —
# those are bare-Postgres stubs and real Supabase already provides them

# generate + apply the schema. Use generate, NOT `drizzle-kit push`:
# push emits the users primary key twice and dies on "users_pkey already exists"
bunx drizzle-kit generate --dialect=postgresql \
  --schema=packages/db/src/schema.ts --out=/tmp/mdgen --name=full
docker cp /tmp/mdgen/0000_full.sql supabase_db_midday:/tmp/full.sql
docker exec supabase_db_midday psql -U postgres -d postgres -f /tmp/full.sql
```

Then the things upstream's hosted DB provides (the script does these too):

```sql
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_id_fkey;
ALTER TABLE public.users ADD CONSTRAINT users_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, avatar_url)
  VALUES (NEW.id, NEW.email,
          COALESCE(NEW.raw_user_meta_data->>'full_name',
                   NEW.raw_user_meta_data->>'name'),
          NEW.raw_user_meta_data->>'avatar_url')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('vault','vault',false,52428800), ('apps','apps',true,52428800)
ON CONFLICT (id) DO NOTHING;
```

## What doesn't work

No API keys are set, by design. Bank connections (Plaid/Teller/GoCardless), AI
features (OpenAI/Gemini), outbound email, and payments are all inert. Invoicing,
the tracker, transactions, vault, and customers work with manually entered data.

### The worker isn't running

`apps/worker` is deliberately not in the start sequence above — it has no `.env`,
only a `.env-template`. It consumes the BullMQ queues in Redis, so **any job the
API enqueues just accumulates there** and whatever the UI shows meanwhile never
resolves. Inspect the backlog with:

```bash
docker exec midday-redis redis-cli --scan --pattern 'bull:*:wait'
docker exec midday-redis redis-cli LLEN bull:customers:wait
```

### Customer enrichment is off

Creating a customer with a website or email used to queue an `enrich-customer`
job and set `enrichment_status = 'pending'`, which renders as a perpetual
"Enriching" spinner in the customers table — the job had no worker to run it,
and would have had nothing to do anyway: enrichment is a paid third-party
lookup against `api.companyenrich.com`, gated on `COMPANY_ENRICH_API_KEY`.

`apps/api/src/utils/enrichment.ts` now gates both trigger sites (auto-trigger on
create, and the manual "Enrich company" action) on that key being present, so
nothing is queued that cannot finish. With no key set, no request is made and no
customer data leaves the machine — `lookupCompany()` returns before any fetch.

The "Enrich company" menu item is still shown in the UI; it now fails with a
`PRECONDITION_FAILED` toast rather than hanging. Hiding it would need the flag
plumbed to the client.

## Stopping

```bash
./node_modules/supabase/bin/supabase stop
docker stop midday-redis
# then kill the two dev servers
```
