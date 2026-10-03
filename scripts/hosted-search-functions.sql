-- Functions that exist only in Midday's hosted Supabase project.
--
-- Reconstructed from their call sites, not from upstream source (there is
-- none in this repo). The contract each one has to satisfy:
--
--   global_search(search_term, team_id, language, max_results,
--                 items_per_table_limit, relevance_threshold)
--     -> (id, type, title, relevance, created_at, data)
--   packages/db/src/queries/search.ts:globalSearchQuery
--
-- `type` values and the shape of `data` are dictated by the renderer in
-- apps/dashboard/src/components/search/search.tsx:354-530 — each case reads
-- specific keys off item.data, so those key names are load-bearing.

CREATE OR REPLACE FUNCTION public.global_search(
  search_term           text    DEFAULT NULL,
  team_id               uuid    DEFAULT NULL,
  language              text    DEFAULT 'english',
  max_results           integer DEFAULT 30,
  items_per_table_limit integer DEFAULT 5,
  relevance_threshold   numeric DEFAULT 0.01
)
RETURNS TABLE (
  id         uuid,
  type       text,
  title      text,
  relevance  real,
  created_at timestamptz,
  data       jsonb
)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $fn$
#variable_conflict use_column
DECLARE
  cfg       regconfig;
  tq        tsquery;
  tokens    text[];
  per_table integer := GREATEST(COALESCE(items_per_table_limit, 5), 1);
  total     integer := GREATEST(COALESCE(max_results, 30), 1);
  threshold real     := COALESCE(relevance_threshold, 0.01)::real;
BEGIN
  IF team_id IS NULL THEN
    RETURN;
  END IF;

  BEGIN
    cfg := COALESCE(NULLIF(language, ''), 'english')::regconfig;
  EXCEPTION WHEN OTHERS THEN
    cfg := 'english'::regconfig;
  END;

  -- Prefix query, so "inv" matches "invoice" as you type. Punctuation is
  -- stripped rather than escaped: this backs a command palette, where a stray
  -- ':' or '&' should just narrow the search instead of raising a syntax error.
  SELECT array_agg(tok || ':*')
    INTO tokens
    FROM unnest(
           regexp_split_to_array(
             trim(regexp_replace(COALESCE(search_term, ''), '[^a-zA-Z0-9]+', ' ', 'g')),
             '\s+')
         ) AS tok
   WHERE tok <> '';

  IF tokens IS NOT NULL AND array_length(tokens, 1) > 0 THEN
    tq := to_tsquery(cfg, array_to_string(tokens, ' & '));
  ELSE
    -- Empty term: the modal prefetches on open, and the Overview page
    -- dehydrates that query. Return the most recent rows instead of erroring.
    tq := NULL;
  END IF;

  RETURN QUERY
  WITH hits AS (
    (
      SELECT t.id,
             'transaction'::text AS type,
             COALESCE(t.name, '') AS title,
             CASE WHEN tq IS NULL THEN 0::real ELSE ts_rank(t.fts_vector, tq) END AS relevance,
             t.created_at,
             jsonb_build_object(
               'name',     t.name,
               'amount',   t.amount,
               'currency', t.currency,
               'date',     t.date,
               'url',      '/transactions?transactionId=' || t.id::text
             ) AS data
        FROM transactions t
       WHERE t.team_id = global_search.team_id
         AND (tq IS NULL OR t.fts_vector @@ tq)
         AND (tq IS NULL OR ts_rank(t.fts_vector, tq) >= threshold)
       ORDER BY relevance DESC, t.created_at DESC
       LIMIT per_table
    )
    UNION ALL
    (
      SELECT i.id,
             'invoice'::text,
             COALESCE(i.invoice_number, ''),
             CASE WHEN tq IS NULL THEN 0::real ELSE ts_rank(i.fts, tq) END,
             i.created_at,
             jsonb_build_object(
               'invoice_number', i.invoice_number,
               'status',         i.status,
               'amount',         i.amount,
               'currency',       i.currency,
               'template',       i.template
             )
        FROM invoices i
       WHERE i.team_id = global_search.team_id
         AND (tq IS NULL OR i.fts @@ tq)
         AND (tq IS NULL OR ts_rank(i.fts, tq) >= threshold)
       ORDER BY 4 DESC, i.created_at DESC
       LIMIT per_table
    )
    UNION ALL
    (
      SELECT c.id,
             'customer'::text,
             COALESCE(c.name, ''),
             CASE WHEN tq IS NULL THEN 0::real ELSE ts_rank(c.fts, tq) END,
             c.created_at,
             jsonb_build_object('name', c.name, 'email', c.email)
        FROM customers c
       WHERE c.team_id = global_search.team_id
         AND (tq IS NULL OR c.fts @@ tq)
         AND (tq IS NULL OR ts_rank(c.fts, tq) >= threshold)
       ORDER BY 4 DESC, c.created_at DESC
       LIMIT per_table
    )
    UNION ALL
    (
      -- documents.fts is to_tsvector(title || ' ' || body) with no COALESCE,
      -- so it is NULL whenever either side is NULL. Fall back to the filename
      -- so an un-processed upload is still findable.
      SELECT d.id,
             'vault'::text,
             COALESCE(d.title, d.name, ''),
             CASE WHEN tq IS NULL THEN 0::real
                  ELSE ts_rank(COALESCE(d.fts, to_tsvector(cfg, COALESCE(d.name, ''))), tq)
             END,
             d.created_at,
             jsonb_build_object(
               'title',       d.title,
               'name',        d.name,
               'path_tokens', d.path_tokens,
               'metadata',    d.metadata
             )
        FROM documents d
       WHERE d.team_id = global_search.team_id
         AND (tq IS NULL OR COALESCE(d.fts, to_tsvector(cfg, COALESCE(d.name, ''))) @@ tq)
         AND (tq IS NULL OR ts_rank(COALESCE(d.fts, to_tsvector(cfg, COALESCE(d.name, ''))), tq) >= threshold)
       ORDER BY 4 DESC, d.created_at DESC
       LIMIT per_table
    )
    UNION ALL
    (
      SELECT b.id,
             'inbox'::text,
             COALESCE(b.display_name, b.file_name, ''),
             CASE WHEN tq IS NULL THEN 0::real ELSE ts_rank(b.fts, tq) END,
             b.created_at,
             jsonb_build_object(
               'display_name', b.display_name,
               'file_name',    b.file_name,
               'file_path',    b.file_path,
               'amount',       b.amount,
               'currency',     b.currency,
               'date',         b.date
             )
        FROM inbox b
       WHERE b.team_id = global_search.team_id
         AND (tq IS NULL OR b.fts @@ tq)
         AND (tq IS NULL OR ts_rank(b.fts, tq) >= threshold)
       ORDER BY 4 DESC, b.created_at DESC
       LIMIT per_table
    )
    UNION ALL
    (
      SELECT p.id,
             'tracker_project'::text,
             COALESCE(p.name, ''),
             CASE WHEN tq IS NULL THEN 0::real ELSE ts_rank(p.fts, tq) END,
             p.created_at,
             jsonb_build_object(
               'name',        p.name,
               'description', p.description,
               'status',      p.status,
               'currency',    p.currency
             )
        FROM tracker_projects p
       WHERE p.team_id = global_search.team_id
         AND (tq IS NULL OR p.fts @@ tq)
         AND (tq IS NULL OR ts_rank(p.fts, tq) >= threshold)
       ORDER BY 4 DESC, p.created_at DESC
       LIMIT per_table
    )
  )
  SELECT h.id, h.type, h.title, h.relevance, h.created_at, h.data
    FROM hits h
   ORDER BY h.relevance DESC, h.created_at DESC
   LIMIT total;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.global_search(text, uuid, text, integer, integer, numeric)
  TO postgres, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- get_team_bank_accounts_balances(team_id)
--   packages/db/src/queries/bank-accounts.ts:158 (overview balance widgets)
--   -> (id, currency, balance, name, logo_url)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_team_bank_accounts_balances(p_team_id uuid)
RETURNS TABLE (
  id       uuid,
  currency text,
  balance  numeric,
  name     text,
  logo_url text
)
LANGUAGE sql
STABLE
SET search_path = public
AS $fn$
  SELECT ba.id,
         ba.currency,
         COALESCE(ba.balance, 0) AS balance,
         ba.name,
         bc.logo_url
    FROM bank_accounts ba
    LEFT JOIN bank_connections bc ON bc.id = ba.bank_connection_id
   WHERE ba.team_id = p_team_id
     AND ba.enabled IS TRUE
   ORDER BY ba.created_at ASC;
$fn$;

-- ---------------------------------------------------------------------------
-- get_bank_account_currencies(team_id)
--   packages/db/src/queries/bank-accounts.ts:170 (currency selector)
--   -> (currency)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_bank_account_currencies(p_team_id uuid)
RETURNS TABLE (currency text)
LANGUAGE sql
STABLE
SET search_path = public
AS $fn$
  SELECT DISTINCT ba.currency
    FROM bank_accounts ba
   WHERE ba.team_id = p_team_id
     AND ba.currency IS NOT NULL
   ORDER BY 1;
$fn$;

-- ---------------------------------------------------------------------------
-- get_assigned_users_for_project(tracker_projects)
--   packages/db/src/queries/tracker-projects.ts:204,460
--   Takes a whole tracker_projects ROW and returns a JSON array shaped like
--   AssignedUser (tracker-projects.ts:27): user_id, full_name, avatar_url.
--   Derived from who has logged time entries against the project.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_assigned_users_for_project(p tracker_projects)
RETURNS json
LANGUAGE sql
STABLE
SET search_path = public
AS $fn$
  SELECT COALESCE(
           json_agg(
             json_build_object(
               'user_id',    u.id,
               'full_name',  u.full_name,
               'avatar_url', u.avatar_url
             )
             ORDER BY u.full_name
           ),
           '[]'::json
         )
    FROM (
      SELECT DISTINCT te.assigned_id
        FROM tracker_entries te
       WHERE te.project_id = p.id
         AND te.assigned_id IS NOT NULL
    ) assignees
    JOIN users u ON u.id = assignees.assigned_id;
$fn$;

-- ---------------------------------------------------------------------------
-- match_similar_documents_by_title(document_id, team_id, threshold, limit)
--   packages/db/src/queries/documents.ts:243 ("related documents")
--   Upstream is embedding-based; this uses pg_trgm similarity on the title,
--   which needs no API key and is a reasonable stand-in for related-by-name.
--   -> (id, name, metadata, path_tokens, tag, title, summary)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.match_similar_documents_by_title(
  p_document_id uuid,
  p_team_id     uuid,
  p_threshold   double precision DEFAULT 0.3,
  p_limit       integer          DEFAULT 10
)
RETURNS TABLE (
  id          uuid,
  name        text,
  metadata    jsonb,
  path_tokens text[],
  tag         text,
  title       text,
  summary     text
)
LANGUAGE sql
STABLE
SET search_path = public
AS $fn$
  WITH src AS (
    SELECT COALESCE(d.title, d.name, '') AS needle
      FROM documents d
     WHERE d.id = p_document_id
       AND d.team_id = p_team_id
  )
  SELECT d.id,
         d.name,
         d.metadata,
         d.path_tokens,
         d.tag,
         d.title,
         d.summary
    FROM documents d, src
   WHERE d.team_id = p_team_id
     AND d.id <> p_document_id
     AND src.needle <> ''
     AND similarity(COALESCE(d.title, d.name, ''), src.needle) >= p_threshold
   ORDER BY similarity(COALESCE(d.title, d.name, ''), src.needle) DESC,
            d.created_at DESC
   LIMIT GREATEST(COALESCE(p_limit, 10), 1);
$fn$;

GRANT EXECUTE ON FUNCTION public.get_team_bank_accounts_balances(uuid) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_account_currencies(uuid) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_assigned_users_for_project(tracker_projects) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.match_similar_documents_by_title(uuid, uuid, double precision, integer) TO postgres, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- total_duration(tracker_projects) / get_project_total_amount(tracker_projects)
--   packages/db/src/queries/tracker-projects.ts:100-105, 421
--   Both take a whole tracker_projects ROW and are also used as sort keys, so
--   they must return a value (not NULL) for a project with no entries.
--   duration is stored in seconds; the entry rate wins over the project rate.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.total_duration(p tracker_projects)
RETURNS bigint
LANGUAGE sql
STABLE
SET search_path = public
AS $fn$
  SELECT COALESCE(SUM(te.duration), 0)::bigint
    FROM tracker_entries te
   WHERE te.project_id = p.id;
$fn$;

CREATE OR REPLACE FUNCTION public.get_project_total_amount(p tracker_projects)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public
AS $fn$
  SELECT COALESCE(
           SUM((COALESCE(te.duration, 0)::numeric / 3600) * COALESCE(te.rate, p.rate, 0)),
           0
         )::numeric
    FROM tracker_entries te
   WHERE te.project_id = p.id;
$fn$;

GRANT EXECUTE ON FUNCTION public.total_duration(tracker_projects) TO postgres, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_project_total_amount(tracker_projects) TO postgres, anon, authenticated, service_role;
