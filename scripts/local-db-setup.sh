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
(cd "$ROOT" && bunx drizzle-kit generate \
  --dialect=postgresql \
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

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('vault','vault',false,52428800), ('apps','apps',true,52428800)
ON CONFLICT (id) DO NOTHING;

-- Backfill anyone who signed up before the trigger existed.
INSERT INTO public.users (id, email)
SELECT id, email FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- fullName is non-nullable in the API response schema; a null 500s /users/me.
UPDATE public.users SET full_name = split_part(email, '@', 1)
WHERE full_name IS NULL;
SQL

TABLES="$(docker exec "$CONTAINER" psql -U postgres -d postgres -tAc \
  "select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE';" | tr -d ' ')"
USERS="$(docker exec "$CONTAINER" psql -U postgres -d postgres -tAc \
  "select count(*) from public.users;" | tr -d ' ')"

echo
echo "done. tables=$TABLES  users=$USERS  apply-errors=$ERRORS"
[[ "$ERRORS" != "0" ]] && echo "  (see /tmp/local-db-apply.log)"
exit 0
