## 1. CLI — dependencies

- [x] 1.1 Add `reqwest` (with `json` and `rustls-tls` features) to `akademiq-cli/Cargo.toml`.
- [x] 1.2 Add `tokio` runtime attribute if not already present (it is — confirm `#[tokio::main]` exists).

## 2. CLI — command struct

- [x] 2.1 Add `SetSingleEvalWeights` variant to `GradingCommands` enum in `main.rs` with fields: `execute: bool`, `yes: bool`, `tenant: Option<Uuid>`, `term: Option<Uuid>`, `token: Option<String>`, `grading_url: Option<String>`.
- [x] 2.2 Wire `SetSingleEvalWeights` into the `run_grading` dispatch match arm.

## 3. CLI — discovery query (read-only SQL)

- [x] 3.1 Implement `find_single_eval_scopes(pool, tenant, term)` async fn: query `evaluation` grouped by `(tenant_id, homeroom_id, subject_id, term_id)` with `HAVING COUNT(*) = 1`, join to `report_type` on `term_id`, left-join to `report_formula` to filter out already-100 rows. Returns `Vec<SingleEvalScope { report_type_id, homeroom_id, subject_id, evaluation_id, tenant_id }>`.
- [x] 3.2 Confirm the query uses `GRADING_DATABASE_URL` via the existing `connect_grading(args)` pool helper.

## 4. CLI — HTTP write path

- [x] 4.1 Implement `set_formula_weight(client, base_url, token, scope)` async fn: `PUT {base_url}/api/v1/grading/report-types/{rt}/homerooms/{h}/formulas/{s}` with `Authorization: Bearer {token}` and body `{ "weights": { "<eval_id>": 100 } }`. Return `Ok(())` or a descriptive error.
- [x] 4.2 Resolve token: `--token` flag → `GRADING_AUTH_TOKEN` env → `anyhow::bail!("token required")`.
- [x] 4.3 Resolve base URL: `--grading-url` flag → `GRADING_BASE_URL` env → `http://127.0.0.1:8086`.
- [x] 4.4 Ensure the token is never printed; on HTTP 403 print "permission denied (check token and assignment)" not the raw response body.

## 5. CLI — dry-run / execute flow

- [x] 5.1 In dry-run mode: call `find_single_eval_scopes`, print each scope as `[DRY-RUN] homeroom={h} subject={s} report_type={rt} eval={e}`, print total count, exit zero.
- [x] 5.2 In execute mode: call `confirm()` (unless `--yes`), then loop over scopes calling `set_formula_weight`; print `[OK]` or `[ERR]` per scope; print final summary `{n} weights set, {m} errors`.
- [x] 5.3 If `find_single_eval_scopes` returns empty: `anyhow::bail!("nothing to change")` (exits non-zero).
- [x] 5.4 On any HTTP error in the loop: print the error and continue to the next scope (best-effort); exit non-zero at end if any errors occurred.

## 6. Verification

- [ ] 6.1 Run against dev Supabase database in dry-run mode; confirm the list of scopes matches a manual SQL check. _(skipped: backend verification against live DB — see Manual Backend Tests)_
- [ ] 6.2 Run with `--execute --yes` against a test tenant; confirm `report_formula.weight = 100` for affected rows and that live scores appear in the grading entry UI. _(skipped: backend verification against live grading service — see Manual Backend Tests)_
- [ ] 6.3 Re-run immediately after; confirm "nothing to change" exits non-zero. _(skipped: backend verification against live DB — see Manual Backend Tests)_
- [x] 6.4 Run `cargo clippy -p akademiq-cli` and fix any warnings.

## Manual Backend Tests

The following require a live grading database + running grading service and a
tenant-admin JWT; run them manually before archiving.

```sh
# 6.1 — dry-run discovery (set GRADING_DATABASE_URL to the dev DB, e.g. Supabase)
cd apps/backend && cargo run -q -p akademiq-cli -- grading set-single-eval-weights \
  --grading-database-url "$GRADING_DATABASE_URL"

# 6.2 — execute against a test tenant (obtain a tenant_admin JWT first)
cd apps/backend && cargo run -q -p akademiq-cli -- grading set-single-eval-weights \
  --grading-database-url "$GRADING_DATABASE_URL" \
  --token "$JWT" --tenant "$TENANT_ID" --execute --yes

# 6.3 — re-run immediately; expect "nothing to change" and a non-zero exit
cd apps/backend && cargo run -q -p akademiq-cli -- grading set-single-eval-weights \
  --grading-database-url "$GRADING_DATABASE_URL" \
  --token "$JWT" --tenant "$TENANT_ID" --execute --yes
```
