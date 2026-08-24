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
- **Placeholder credentials** in `apps/api/.env` — `packages/banking/src/env.ts`
  requires every bank provider credential via t3-env, and
  `packages/bot/src/instance.ts` eagerly constructs the WhatsApp/Telegram/Slack/
  Sendblue adapters at import time. All are `unused-local`; nothing is
  transmitted.
- **`[analytics] enabled = false`** in `supabase/config.toml` — the Logflare and
  vector containers mount the Docker socket, which fails under Colima.

## Rebuilding the database from scratch

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

Then the two things upstream's hosted DB provides:

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

## Stopping

```bash
./node_modules/supabase/bin/supabase stop
docker stop midday-redis
# then kill the two dev servers
```
