-- =============================================================================
-- AkademiQ — Backfill Evaluation Weights (100%) + Recompute Report Scores
-- =============================================================================
-- Tenant-scoped maintenance script that:
--   1. Auto-creates an evaluation (code=SAS) for teaching assignments that
--      have none (defensive; normally zero rows).
--   2. Inserts report_formula rows with weight=100 for every evaluation that
--      belongs to a (homeroom, subject, year, term) with EXACTLY ONE
--      evaluation. Subjects with 2+ evaluations are SKIPPED.
--   3. Recomputes the live subject_report_score for every active student in
--      every touched homeroom (missing grade → score 0).
--   4. Refreshes the frozen report_subject_score + summary JSON for every
--      Draft report_card, replicating recompute_subject_live_scores_batch.
--
-- Scope: ONLY tenant "TPQ BAITUR ROCHMAN" (hardcoded below).
-- Report type: resolved dynamically by code 'SAS' within that tenant+year.
--
-- Idempotent: safe to run multiple times. All writes use ON CONFLICT clauses
-- and the recompute is set-oriented.
--
-- Usage:
--   Dry-run (default — rollback + print summary):
--     psql "$DB_URL" -v DRY_RUN=true  -f scripts/backfill_evaluation_weights.sql
--   Live run:
--     pql "$DB_URL" -v DRY_RUN=false -f scripts/backfill_evaluation_weights.sql
--
-- The $DB_URL must route to the grading schema. When using Supabase pooler:
--   "postgres://USER:PASS@HOST:5432/postgres?sslmode=require\
--     &options=-c%20search_path%3Dgrading"
--
-- NOTE: psql \set variables are interpolated by psql before the server sees
-- the query, so they work in plain SQL and CTEs but NOT inside dollar-quoted
-- DO bodies. This script uses SET LOCAL + current_setting() for values needed
-- inside procedural blocks, and \set/\if for DRY_RUN branching.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Section 0 — Configuration
-- ----------------------------------------------------------------------------
-- DRY_RUN defaults to true (safe). Override on the command line with
--   -v DRY_RUN=false   to actually commit.
\if :{?DRY_RUN}
\else
\set DRY_RUN true
\endif

-- Target tenant (TPQ BAITUR ROCHMAN).
\set TARGET_TENANT_ID 'cbd5f3ea-2cfd-4e59-b66e-438b6baad214'

-- The single report type this tenant uses (SAS / Sumatif Akhir).
\set TARGET_RT_CODE 'SAS'

-- Evaluation template for auto-created rows.
\set NEW_EVAL_CODE 'SAS'
\set NEW_EVAL_NAME 'Sumatif Akhir Semester'

BEGIN;

-- Publish variables to the server so DO blocks can read them.
SELECT set_config('bk.target_tenant', :'TARGET_TENANT_ID', false);
SELECT set_config('bk.target_rt_code', :'TARGET_RT_CODE', false);
SELECT set_config('bk.new_eval_code',  :'NEW_EVAL_CODE',  false);
SELECT set_config('bk.new_eval_name',  :'NEW_EVAL_NAME',  false);

-- ----------------------------------------------------------------------------
-- Section 0b — Tenant guard
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    verified_name text;
    tid uuid := current_setting('bk.target_tenant')::uuid;
BEGIN
    SELECT school_name INTO verified_name
    FROM billing.tenant
    WHERE tenant_id = tid;

    IF verified_name IS NULL THEN
        RAISE EXCEPTION 'Tenant % not found in billing.tenant — aborting.', tid;
    END IF;

    IF verified_name <> 'TPQ BAITUR ROCHMAN' THEN
        RAISE EXCEPTION 'Tenant name mismatch: expected "TPQ BAITUR ROCHMAN", got "%".', verified_name;
    END IF;

    RAISE NOTICE 'Tenant verified: % (%).', verified_name, tid;
END $$;

-- ----------------------------------------------------------------------------
-- Section 1 — Resolve report type & academic context
-- ----------------------------------------------------------------------------

CREATE TEMP TABLE _rt_ctx ON COMMIT DROP AS
SELECT rt.report_type_id,
       rt.tenant_id,
       rt.academic_year_id,
       rt.term_id
FROM grading.report_type rt
WHERE rt.tenant_id = :'TARGET_TENANT_ID'::uuid
  AND rt.code = :'TARGET_RT_CODE';

DO $$
DECLARE
    n int;
    rtcode text := current_setting('bk.target_rt_code');
BEGIN
    SELECT COUNT(*) INTO n FROM _rt_ctx;
    IF n = 0 THEN
        RAISE EXCEPTION 'No report_type with code "%" for this tenant. Create it first via the UI.', rtcode;
    END IF;
    IF n > 1 THEN
        RAISE EXCEPTION 'Multiple report_type rows with code "%" for this tenant (%). Resolve ambiguity first.', rtcode, n;
    END IF;
    RAISE NOTICE 'Report type resolved: code=%, rows=%.', rtcode, n;
END $$;

-- ----------------------------------------------------------------------------
-- Section 2 — Auto-create evaluations for assignments without one
--             (defensive — expected 0 rows for this tenant today)
-- ----------------------------------------------------------------------------

WITH ctx AS (SELECT * FROM _rt_ctx),
assignments_without_eval AS (
    SELECT ta.tenant_id,
           ta.homeroom_id,
           ta.subject_id,
           ta.academic_year_id,
           c.term_id
    FROM grading.teaching_authz ta
    CROSS JOIN ctx c
    WHERE ta.tenant_id = :'TARGET_TENANT_ID'::uuid
      AND ta.academic_year_id = c.academic_year_id
      AND NOT EXISTS (
          SELECT 1
          FROM grading.evaluation e
          WHERE e.tenant_id = ta.tenant_id
            AND e.homeroom_id = ta.homeroom_id
            AND e.subject_id = ta.subject_id
            AND e.academic_year_id = ta.academic_year_id
            AND e.term_id = c.term_id
      )
)
INSERT INTO grading.evaluation
    (evaluation_id, tenant_id, homeroom_id, subject_id, academic_year_id,
     term_id, code, name, position)
SELECT gen_random_uuid(),
       awe.tenant_id,
       awe.homeroom_id,
       awe.subject_id,
       awe.academic_year_id,
       awe.term_id,
       :'NEW_EVAL_CODE',
       :'NEW_EVAL_NAME',
       1
FROM assignments_without_eval awe
ON CONFLICT (tenant_id, homeroom_id, subject_id, academic_year_id, term_id, code)
    DO NOTHING;

-- ----------------------------------------------------------------------------
-- Section 3 — Insert report_formula rows (weight=100) for single-evaluation
--             subjects only. Multi-evaluation subjects are SKIPPED.
-- ----------------------------------------------------------------------------

-- 3a. Identify evaluations eligible for the 100% weight.
CREATE TEMP TABLE _single_eval ON COMMIT DROP AS
SELECT e.evaluation_id,
       e.homeroom_id,
       e.subject_id,
       e.academic_year_id,
       e.term_id,
       e.tenant_id
FROM grading.evaluation e
CROSS JOIN _rt_ctx c
WHERE e.tenant_id = c.tenant_id
  AND e.academic_year_id = c.academic_year_id
  AND e.term_id = c.term_id
  AND e.homeroom_id IN (
      SELECT DISTINCT homeroom_id
      FROM grading.teaching_authz
      WHERE tenant_id = c.tenant_id
        AND academic_year_id = c.academic_year_id
  )
  AND NOT EXISTS (
      SELECT 1
      FROM grading.report_formula rf
      WHERE rf.evaluation_id = e.evaluation_id
        AND rf.report_type_id = c.report_type_id
  )
  AND e.subject_id IN (
      SELECT e2.subject_id
      FROM grading.evaluation e2
      WHERE e2.tenant_id = e.tenant_id
        AND e2.homeroom_id = e.homeroom_id
        AND e2.academic_year_id = e.academic_year_id
        AND e2.term_id = e.term_id
      GROUP BY e2.subject_id
      HAVING COUNT(*) = 1
  );

-- 3b. Warn about multi-evaluation subjects (skipped).
DO $$
DECLARE
    skipped_count int;
    tid uuid := current_setting('bk.target_tenant')::uuid;
BEGIN
    SELECT COUNT(*) INTO skipped_count
    FROM (
        SELECT e.subject_id, e.homeroom_id, COUNT(*) AS cnt
        FROM grading.evaluation e
        CROSS JOIN _rt_ctx c
        WHERE e.tenant_id = c.tenant_id
          AND e.academic_year_id = c.academic_year_id
          AND e.term_id = c.term_id
        GROUP BY e.subject_id, e.homeroom_id
        HAVING COUNT(*) > 1
    ) m;
    IF skipped_count > 0 THEN
        RAISE NOTICE 'WARNING: % (homeroom, subject) pairs have 2+ evaluations — SKIPPED (manual formula needed).', skipped_count;
    ELSE
        RAISE NOTICE 'No multi-evaluation subjects found — all eligible.';
    END IF;
END $$;

-- 3c. Insert weight=100 rows (idempotent).
INSERT INTO grading.report_formula (report_type_id, evaluation_id, weight)
SELECT c.report_type_id, se.evaluation_id, 100.0
FROM _single_eval se
CROSS JOIN _rt_ctx c
ON CONFLICT (report_type_id, evaluation_id) DO NOTHING;

-- 3d. Notice: total formula rows for this report type.
DO $$
DECLARE
    total_formula int;
    tid uuid := current_setting('bk.target_tenant')::uuid;
BEGIN
    SELECT COUNT(*) INTO total_formula
    FROM grading.report_formula rf
    JOIN grading.evaluation e ON e.evaluation_id = rf.evaluation_id
    WHERE rf.report_type_id = (SELECT report_type_id FROM _rt_ctx)
      AND e.tenant_id = tid;
    RAISE NOTICE 'Total report_formula rows for report type after backfill: %.', total_formula;
END $$;

-- ----------------------------------------------------------------------------
-- Section 4 — Recompute live subject_report_score
--             Replicates compute_subject_score: score × weight / 100.
--             Missing grade → 0. Only for subjects whose formula sums to 100.
-- ----------------------------------------------------------------------------

-- 4a. Build the set of (student, evaluation, weight, score).
CREATE TEMP TABLE _recompute_grid ON COMMIT DROP AS
SELECT es.student_id,
       e.subject_id,
       e.homeroom_id,
       es.tenant_id,
       c.academic_year_id,
       c.report_type_id,
       e.evaluation_id,
       rf.weight,
       COALESCE(g.score, 0.0) AS raw_score
FROM grading.enrolled_student es
CROSS JOIN _rt_ctx c
JOIN grading.evaluation e
  ON e.tenant_id = es.tenant_id
 AND e.homeroom_id = es.homeroom_id
 AND e.academic_year_id = c.academic_year_id
 AND e.term_id = c.term_id
JOIN grading.report_formula rf
  ON rf.evaluation_id = e.evaluation_id
 AND rf.report_type_id = c.report_type_id
LEFT JOIN grading.grade g
  ON g.evaluation_id = e.evaluation_id
 AND g.student_id = es.student_id
WHERE es.tenant_id = :'TARGET_TENANT_ID'::uuid
  AND es.status = 'active'
  AND es.academic_year_id = c.academic_year_id;

-- 4b. Aggregate per (student, subject). formula_is_valid gate: Σweight = 100.
CREATE TEMP TABLE _live_scores ON COMMIT DROP AS
SELECT g.student_id,
       g.subject_id,
       g.homeroom_id,
       g.tenant_id,
       g.academic_year_id,
       g.report_type_id,
       SUM(g.raw_score * g.weight / 100.0) AS score
FROM _recompute_grid g
GROUP BY g.student_id, g.subject_id, g.homeroom_id, g.tenant_id,
         g.academic_year_id, g.report_type_id
HAVING SUM(g.weight) = 100.0;

-- 4c. Upsert live scores (idempotent).
INSERT INTO grading.subject_report_score
    (tenant_id, academic_year_id, homeroom_id, subject_id, student_id,
     report_type_id, score, updated_at)
SELECT ls.tenant_id,
       ls.academic_year_id,
       ls.homeroom_id,
       ls.subject_id,
       ls.student_id,
       ls.report_type_id,
       ls.score,
       NOW()
FROM _live_scores ls
ON CONFLICT (report_type_id, subject_id, student_id)
DO UPDATE SET score      = EXCLUDED.score,
              tenant_id  = EXCLUDED.tenant_id,
              academic_year_id = EXCLUDED.academic_year_id,
              homeroom_id = EXCLUDED.homeroom_id,
              updated_at = NOW();

DO $$
DECLARE
    n int;
BEGIN
    SELECT COUNT(*) INTO n FROM _live_scores;
    RAISE NOTICE 'Live subject_report_score rows recomputed: %.', n;
END $$;

-- ----------------------------------------------------------------------------
-- Section 5 — Refresh frozen report_subject_score + summary for Draft cards
--             Replicates the Draft-card refresh in
--             recompute_subject_live_scores_batch.
-- ----------------------------------------------------------------------------

-- 5a. Refresh frozen report_subject_score for Draft cards.
CREATE TEMP TABLE _draft_cards ON COMMIT DROP AS
SELECT rc.report_card_id, rc.student_id, rc.report_type_id
FROM grading.report_card rc
WHERE rc.tenant_id = :'TARGET_TENANT_ID'::uuid
  AND rc.status = 'Draft';

-- Delete existing frozen rows for Draft cards, then reinsert from live scores.
DELETE FROM grading.report_subject_score rss
USING _draft_cards dc
WHERE rss.report_card_id = dc.report_card_id;

INSERT INTO grading.report_subject_score (report_card_id, subject_id, final_score, computed_at)
SELECT dc.report_card_id, ls.subject_id, ls.score, NOW()
FROM _draft_cards dc
JOIN _live_scores ls
  ON ls.report_type_id = dc.report_type_id
 AND ls.student_id = dc.student_id
ON CONFLICT (report_card_id, subject_id)
DO UPDATE SET final_score = EXCLUDED.final_score, computed_at = NOW();

-- 5b. Recompute summary JSON for Draft cards (derive_report_summary replica).
CREATE TEMP TABLE _policy ON COMMIT DROP AS
SELECT minimum_passing_score
FROM grading.grading_policy_projection
WHERE tenant_id = :'TARGET_TENANT_ID'::uuid
  AND academic_year_id = (SELECT academic_year_id FROM _rt_ctx);

WITH frozen_per_card AS (
    SELECT rss.report_card_id,
           jsonb_agg(
               jsonb_build_object(
                   'subject_id', rss.subject_id,
                   'final_score', rss.final_score,
                   'passed', rss.final_score >= (SELECT minimum_passing_score FROM _policy)
               )
               ORDER BY rss.subject_id
           ) AS subjects,
           COUNT(*) AS total_subjects,
           SUM(CASE WHEN rss.final_score >= (SELECT minimum_passing_score FROM _policy) THEN 1 ELSE 0 END) AS pass_count,
           AVG(rss.final_score) AS average_score
    FROM grading.report_subject_score rss
    JOIN grading.report_card rc ON rc.report_card_id = rss.report_card_id
    WHERE rc.tenant_id = :'TARGET_TENANT_ID'::uuid
      AND rc.status = 'Draft'
    GROUP BY rss.report_card_id
)
UPDATE grading.report_card rc
SET summary = CASE
        WHEN fpc.total_subjects = 0 THEN
            jsonb_build_object(
                'subjects', '[]'::jsonb,
                'average_score', NULL,
                'pass_count', 0,
                'total_subjects', 0,
                'incomplete', true
            )
        ELSE
            jsonb_build_object(
                'subjects', fpc.subjects,
                'average_score', fpc.average_score,
                'pass_count', fpc.pass_count,
                'total_subjects', fpc.total_subjects,
                'incomplete', false
            )
    END,
    updated_at = NOW()
FROM frozen_per_card fpc
WHERE rc.report_card_id = fpc.report_card_id;

DO $$
DECLARE
    n int;
    tid uuid := current_setting('bk.target_tenant')::uuid;
BEGIN
    SELECT COUNT(*) INTO n
    FROM grading.report_card
    WHERE tenant_id = tid AND status = 'Draft';
    RAISE NOTICE 'Draft report_card summaries refreshed: %.', n;
END $$;

-- ----------------------------------------------------------------------------
-- Section 6 — Transaction control
-- ----------------------------------------------------------------------------

\if :DRY_RUN
\echo '=== DRY RUN — rolling back all changes. Re-run with -v DRY_RUN=false to commit. ==='
ROLLBACK;
\else
\echo '=== LIVE RUN — changes committed. ==='
COMMIT;
\endif

-- ----------------------------------------------------------------------------
-- Post-execution verification (read-only, runs after the transaction above).
-- ----------------------------------------------------------------------------

\echo '=== Verification (read-only) ==='

SELECT 'formula_rows' AS metric, COUNT(*) AS value
FROM grading.report_formula rf
JOIN grading.evaluation e ON e.evaluation_id = rf.evaluation_id
WHERE e.tenant_id = :'TARGET_TENANT_ID'::uuid
  AND rf.report_type_id = (
      SELECT report_type_id FROM grading.report_type
      WHERE tenant_id = :'TARGET_TENANT_ID'::uuid AND code = :'TARGET_RT_CODE'
  );

SELECT 'live_score_rows' AS metric, COUNT(*) AS value
FROM grading.subject_report_score
WHERE tenant_id = :'TARGET_TENANT_ID'::uuid;

SELECT 'draft_cards' AS metric, COUNT(*) AS value
FROM grading.report_card
WHERE tenant_id = :'TARGET_TENANT_ID'::uuid AND status = 'Draft';

SELECT report_card_id,
       summary->>'total_subjects' AS subjects,
       summary->>'average_score'  AS avg_score,
       summary->>'pass_count'     AS passed
FROM grading.report_card
WHERE tenant_id = :'TARGET_TENANT_ID'::uuid
  AND status = 'Draft'
ORDER BY report_card_id;
