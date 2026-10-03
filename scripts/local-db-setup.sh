#!/usr/bin/env bash
#
# Rebuild the local Supabase database for development.
#
# Upstream ships no local-dev setup, and a few objects the app needs live only
# in Midday's hosted Supabase project. This recreates the schema plus those
# objects. Idempotent — safe to re-run.
#
# Requires: supabase local stack already running (`supabase start`).
#
# Usage:
#   ./scripts/local-db-setup.sh          # create/refresh schema, keep data
#   ./scripts/local-db-setup.sh --reset  # DROP the public schema first
#
set -euo pipefail

CONTAINER="${SUPABASE_DB_CONTAINER:-supabase_db_midday}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESET=0
[[ "${1:-}" == "--reset" ]] && RESET=1

psql_c() { docker exec -i "$CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=0 "$@"; }

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
  echo "error: container '$CONTAINER' is not running. Start it with:" >&2
  echo "  ./node_modules/supabase/bin/supabase start" >&2
  exit 1
fi

if [[ $RESET -eq 1 ]]; then
  echo "==> dropping public + private schemas"
  psql_c -q -c "
    DROP SCHEMA IF EXISTS public CASCADE;
    DROP SCHEMA IF EXISTS private CASCADE;
    CREATE SCHEMA public;
    GRANT ALL ON SCHEMA public TO postgres, anon, authenticated, service_role;" >/dev/null
fi

echo "==> extensions"
psql_c -q -c "CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS pg_trgm;" >/dev/null

echo "==> helper functions (extract_product_names, generate_inbox_fts, ...)"
# The two "permission denied for schema auth" errors are expected: that file
# stubs auth.uid()/auth.jwt() for bare Postgres, and real Supabase already
# provides them.
docker cp "$ROOT/packages/db/src/test/helpers/setup-test-db.sql" "$CONTAINER:/tmp/setup.sql" >/dev/null
psql_c -f /tmp/setup.sql >/dev/null 2>&1 || true

echo "==> generating schema SQL from drizzle"
# `drizzle-kit push` is NOT usable here: it emits the users primary key both
# inline and as a separate statement and dies on "users_pkey already exists".
GEN_DIR="$(mktemp -d)"
# --casing=snake_case is REQUIRED and easy to lose: these CLI flags bypass
# packages/db/drizzle.config.ts entirely. The runtime clients all use
# casing: "snake_case", so without it every column declared without an explicit
# name (transactions.baseAmount, bank_accounts.availableBalance, ...) is created
# camelCase and then queried snake_case -> "Failed query" on the overview,
# connection status and team deletion.
(cd "$ROOT" && bunx drizzle-kit generate \
  --dialect=postgresql \
  --casing=snake_case \
  --schema=packages/db/src/schema.ts \
  --out="$GEN_DIR" --name=full >/dev/null 2>&1)

echo "==> applying schema"
docker cp "$GEN_DIR/0000_full.sql" "$CONTAINER:/tmp/full.sql" >/dev/null
psql_c -f /tmp/full.sql > /tmp/local-db-apply.log 2>&1 || true
ERRORS="$(grep -c '^ERROR' /tmp/local-db-apply.log || true)"
rm -rf "$GEN_DIR"

echo "==> objects that live in Midday's hosted project, not the repo"
psql_c <<'SQL' >/dev/null 2>&1
-- drizzle can't create a dotted "auth.users" table name, so this FK collapses
-- onto public.users itself. Repoint it at Supabase's real auth.users.
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_id_fkey;
ALTER TABLE public.users ADD CONSTRAINT users_id_fkey
  FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- Without this trigger, signup creates an auth.users row with no matching
-- public.users row and the API returns "User not found".
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

-- schema.ts introspected two hosted defaults as string *literals*:
--   teams.inbox_id   text default 'generate_inbox(10)'
--   user_invites.code text default 'nanoid(24)'
-- Both columns are UNIQUE, so every row gets the same literal and the SECOND
-- team (or invite) dies on a duplicate-key error. Define the functions and
-- repoint the defaults at real calls.
CREATE OR REPLACE FUNCTION public.nanoid(size integer DEFAULT 21)
RETURNS text LANGUAGE plpgsql VOLATILE AS $fn$
DECLARE
  alphabet text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  bytes bytea;
  result text := '';
  i integer;
BEGIN
  IF size IS NULL OR size < 1 THEN
    RAISE EXCEPTION 'nanoid: size must be >= 1';
  END IF;
  bytes := gen_random_bytes(size);
  FOR i IN 0..size - 1 LOOP
    -- 64-char alphabet, so a masked byte is an unbiased index
    result := result || substr(alphabet, (get_byte(bytes, i) & 63) + 1, 1);
  END LOOP;
  RETURN result;
END; $fn$;

CREATE OR REPLACE FUNCTION public.generate_inbox(size integer DEFAULT 10)
RETURNS text LANGUAGE plpgsql VOLATILE AS $fn$
DECLARE
  -- lowercase alphanumeric only: this becomes the local part of an email address
  alphabet text := 'abcdefghijklmnopqrstuvwxyz0123456789';
  result text := '';
  i integer;
BEGIN
  IF size IS NULL OR size < 1 THEN
    RAISE EXCEPTION 'generate_inbox: size must be >= 1';
  END IF;
  FOR i IN 1..size LOOP
    result := result || substr(alphabet, floor(random() * 36)::int + 1, 1);
  END LOOP;
  RETURN result;
END; $fn$;

ALTER TABLE public.teams        ALTER COLUMN inbox_id SET DEFAULT public.generate_inbox(10);
ALTER TABLE public.user_invites ALTER COLUMN code     SET DEFAULT public.nanoid(24);

-- Rows created before the defaults were fixed carry the literal string.
UPDATE public.teams SET inbox_id = public.generate_inbox(10)
WHERE inbox_id IS NULL OR inbox_id = 'generate_inbox(10)';
UPDATE public.user_invites SET code = public.nanoid(24)
WHERE code IS NULL OR code = 'nanoid(24)';

-- setup-test-db.sql (applied above, for bare Postgres) defines this as a STUB
-- that returns no rows: "SELECT '000...'::uuid LIMIT 0". 45 RLS policies call
-- it, so with the stub in place every one of them is effectively deny-all. That
-- goes unnoticed because the API connects as `postgres` and bypasses RLS — but
-- the browser talks to storage/PostgREST directly with the user's JWT, where it
-- silently denies everything (e.g. the invoice logo upload).
--
-- SECURITY DEFINER is required: users_on_team itself has RLS enabled, and
-- policies on that table call this function — without it, the lookup either
-- returns nothing or recurses.
CREATE OR REPLACE FUNCTION private.get_teams_for_authenticated_user()
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT team_id FROM public.users_on_team WHERE user_id = auth.uid()
$$;

-- 'avatars' is public: the upload helper returns getPublicUrl(), and the invoice
-- logo / company logo / user avatar are rendered as plain <img src>.
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('vault','vault',false,52428800),
       ('apps','apps',true,52428800),
       ('avatars','avatars',true,52428800)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS policies live in Midday's hosted Supabase project, not this repo,
-- so storage.objects comes up with RLS enabled and *zero* policies. Uploads to
-- 'avatars' happen browser-side with the user's JWT (not the service role), so
-- without a policy every one is denied — surfacing as the generic
-- "Something went wrong, please try again." toast.
--
-- First path segment is the owning id: <teamId>/<file>, <teamId>/invoice/<file>,
-- or <userId>/<file>. Allow a user to write under their own id or any team they
-- belong to. Reads need no policy — the bucket is public.
DROP POLICY IF EXISTS "avatars_owner_write" ON storage.objects;
CREATE POLICY "avatars_owner_write" ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'avatars' AND (
      (storage.foldername(name))[1] = (SELECT auth.uid())::text
      OR (storage.foldername(name))[1] IN (
        SELECT t::text FROM private.get_teams_for_authenticated_user() AS t
      )
    )
  )
  WITH CHECK (
    bucket_id = 'avatars' AND (
      (storage.foldername(name))[1] = (SELECT auth.uid())::text
      OR (storage.foldername(name))[1] IN (
        SELECT t::text FROM private.get_teams_for_authenticated_user() AS t
      )
    )
  );

-- Backfill anyone who signed up before the trigger existed.
INSERT INTO public.users (id, email)
SELECT id, email FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- fullName is non-nullable in the API response schema; a null 500s /users/me.
UPDATE public.users SET full_name = split_part(email, '@', 1)
WHERE full_name IS NULL;
SQL

echo "==> realtime publication"
# drizzle-kit generate never emits publication membership, so supabase_realtime
# comes up EMPTY and no postgres_changes event is ever delivered — the channel
# still reports SUBSCRIBED, so it fails silently. useRealtime() also filters on
# team_id, a non-PK column, which UPDATE/DELETE only carry under REPLICA
# IDENTITY FULL. Tables from the useRealtime() call sites in apps/dashboard.
psql_c -q <<'SQL' >/dev/null 2>&1
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['activities','customers','documents','inbox','transactions'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
  END LOOP;
END $$;
SQL

echo "==> hosted-only search functions"
docker cp "$ROOT/scripts/hosted-search-functions.sql" "$CONTAINER:/tmp/search.sql" >/dev/null
psql_c -f /tmp/search.sql >/dev/null 2>&1

TABLES="$(docker exec "$CONTAINER" psql -U postgres -d postgres -tAc \
  "select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE';" | tr -d ' ')"
USERS="$(docker exec "$CONTAINER" psql -U postgres -d postgres -tAc \
  "select count(*) from public.users;" | tr -d ' ')"

echo
echo "done. tables=$TABLES  users=$USERS  apply-errors=$ERRORS"
[[ "$ERRORS" != "0" ]] && echo "  (see /tmp/local-db-apply.log)"
exit 0
