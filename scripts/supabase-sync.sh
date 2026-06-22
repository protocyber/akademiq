#!/usr/bin/env bash
# =============================================================================
# AcademiQ — Supabase sync (prod → dev, schema-per-service)
# =============================================================================
# Dumps each service schema from a Supabase PROD database and restores it into
# a Supabase DEV database. Both databases use the schema-per-service layout
# (iam, billing, academic_config, academic_ops, grading).
#
# Safety model:
#   - Existing dev schema is RENAMED (not dropped) to <schema>_backup_<ts>
#     before restore, so you can roll back manually if something goes wrong.
#   - Backups are NEVER auto-purged. Clean them up manually once you are happy:
#       psql "$DEV_DB_URL" -c 'DROP SCHEMA iam_backup_20260622_143000 CASCADE;'
#   - pg_dump/pg_restore use --no-owner --no-acl so role/ownership differences
#     between Supabase projects do not cause failures.
#
# Usage:
#   # Preferred: direct connection (requires IPv6 or Supabase Dedicated IPv4 add-on)
#   PROD_DB_URL=postgres://postgres.<prod-ref>:PASS@db.<prod-ref>.supabase.co:5432/postgres \
#   DEV_DB_URL=postgres://postgres.<dev-ref>:PASS@db.<dev-ref>.supabase.co:5432/postgres \
#   ./scripts/supabase-sync.sh
#
#   # Fallback: session pooler, IPv4-compatible (copy from Supabase dashboard)
#   PROD_DB_URL=postgres://postgres.<prod-ref>:PASS@aws-1-<region>.pooler.supabase.com:5432/postgres \
#   DEV_DB_URL=postgres://postgres.<dev-ref>:PASS@aws-1-<region>.pooler.supabase.com:5432/postgres \
#   ./scripts/supabase-sync.sh
#
# Flags:
#   --dry-run          Show what would happen without touching either DB.
#   --schema NAME      Sync only one schema (may be repeated).
#   --skip-verify      Skip post-restore row-count comparison.
#   --keep-dumps       Keep the .dump files in ${DUMP_DIR} (default: /tmp).
#   --help, -h         Show this help.
#
# Exit codes:
#   0  all requested schemas synced (or dry-run printed)
#   1  pre-flight failure (missing tools, no connection, bad args)
#   2  one or more schemas failed to sync (others may have succeeded)
#
# Requires: pg_dump, pg_restore, psql (>= 14). The host tools can be newer
# than the server (pg_dump 16 works against a Supabase PG 15 server).
#
# Connection mode:
#   Preferred: Supabase DIRECT host (db.<project-ref>.supabase.co:5432).
#              Direct hosts use IPv6 by default; IPv4 direct access requires
#              Supabase's paid Dedicated IPv4 add-on.
#   Fallback:  Supavisor/session pooler (*.pooler.supabase.com:5432) if your
#              network cannot reach IPv6 and you do not use the IPv4 add-on.
#   Forbidden: Transaction pooler port 6543 — pg_dump/pg_restore and SQLx named
#              prepared statements are not compatible with transaction mode.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

DEFAULT_SCHEMAS=("iam" "billing" "academic_config" "academic_ops" "grading")

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
DRY_RUN=0
SKIP_VERIFY=0
KEEP_DUMPS=0
SCHEMAS=()

usage() {
  # Print the leading comment block (lines starting with '# ' up to the first
  # line that is not a comment), stripping the '# ' prefix.
  sed -n '3,${ /^#/!q; s/^# \?//; p; }' "$0"
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)      DRY_RUN=1; shift ;;
    --skip-verify)  SKIP_VERIFY=1; shift ;;
    --keep-dumps)   KEEP_DUMPS=1; shift ;;
    --schema)
      [ $# -ge 2 ] || { echo "ERROR: --schema requires an argument." >&2; exit 1; }
      SCHEMAS+=("$2"); shift 2 ;;
    --schema=*)     SCHEMAS+=("${1#--schema=}"); shift ;;
    --help|-h)      usage ;;
    *) echo "ERROR: unknown argument: $1 (try --help)" >&2; exit 1 ;;
  esac
done

if [ ${#SCHEMAS[@]} -eq 0 ]; then
  SCHEMAS=("${DEFAULT_SCHEMAS[@]}")
fi

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
PROD_DB_URL="${PROD_DB_URL:-}"
DEV_DB_URL="${DEV_DB_URL:-}"
DUMP_DIR="${DUMP_DIR:-/tmp}"

if [ -z "$PROD_DB_URL" ]; then
  echo -e "${RED}ERROR${RESET} PROD_DB_URL is not set." >&2
  echo    "  # Preferred: direct connection (IPv6 or paid Dedicated IPv4 add-on)" >&2
  echo    "  PROD_DB_URL=postgres://postgres.<prod-ref>:PASS@db.<prod-ref>.supabase.co:5432/postgres \\" >&2
  echo    "  DEV_DB_URL=postgres://postgres.<dev-ref>:PASS@db.<dev-ref>.supabase.co:5432/postgres \\" >&2
  echo    "  ./scripts/supabase-sync.sh" >&2
  echo    "" >&2
  echo    "  # Fallback: session pooler :5432 for IPv4-only networks" >&2
  echo    "  PROD_DB_URL=postgres://postgres.<prod-ref>:PASS@aws-1-<region>.pooler.supabase.com:5432/postgres \\" >&2
  echo    "  DEV_DB_URL=postgres://postgres.<dev-ref>:PASS@aws-1-<region>.pooler.supabase.com:5432/postgres \\" >&2
  echo    "  ./scripts/supabase-sync.sh" >&2
  exit 1
fi
if [ -z "$DEV_DB_URL" ]; then
  echo -e "${RED}ERROR${RESET} DEV_DB_URL is not set." >&2
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()     { printf "${BLUE}[INFO]${RESET} %s\n" "$*"; }
ok()      { printf "${GREEN}[ OK ]${RESET} %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${RESET} %s\n" "$*"; }
err()     { printf "${RED}[ERR ]${RESET} %s\n" "$*" >&2; }
section() { printf "\n${BOLD}${BLUE}━━━ %s ━━━${RESET}\n" "$*"; }

require() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Required tool missing: $cmd"
    case "$(uname -s)" in
      Darwin) echo "  brew install postgresql@" "16" 2>/dev/null || echo "  brew install libpq" ;;
      Linux)  echo "  Debian/Ubuntu: sudo apt-get install postgresql-client-16" ;;
    esac
    exit 1
  fi
}

# Run psql -c against a URL, swallowing output unless verbose.
psql_c() { psql "$1" -v ON_ERROR_STOP=1 -tAc "$2"; }

# Count rows in every table of a schema (schema-qualified, quoted).
# Prints "<table>|<count>" lines, sorted by table name.
count_rows() {
  local url="$1" schema="$2"
  psql "$url" -v ON_ERROR_STOP=1 -tA <<SQL
SELECT format('%I', relname) || '|' || n_live_tup
FROM pg_stat_user_tables
WHERE schemaname = '${schema}'
ORDER BY relname;
SQL
}

connection_mode() {
  local url="$1"
  if [[ "$url" == *":6543"* ]]; then
    printf 'transaction-pooler'
  elif [[ "$url" == *".pooler.supabase.com"* ]]; then
    printf 'session-pooler'
  elif [[ "$url" == *"@db."*".supabase.co"* ]] || [[ "$url" == *"@db."*".supabase.com"* ]]; then
    printf 'direct'
  else
    printf 'custom'
  fi
}

validate_connection_mode() {
  local label="$1" url="$2" mode
  mode="$(connection_mode "$url")"
  case "$mode" in
    direct)
      ok "$label connection mode: direct Supabase host (preferred for pg_dump/pg_restore)"
      warn "$label direct host requires IPv6 unless Supabase Dedicated IPv4 add-on is enabled."
      ;;
    session-pooler)
      warn "$label connection mode: session pooler fallback (*.pooler.supabase.com:5432)."
      warn "  This is IPv4-compatible, but less ideal for long pg_dump/pg_restore jobs than direct."
      ;;
    transaction-pooler)
      err "$label uses transaction pooler port 6543. This is not supported."
      err "  Use direct db.<ref>.supabase.co:5432, or session pooler *.pooler.supabase.com:5432."
      exit 1
      ;;
    custom)
      warn "$label connection mode: custom/unrecognized host. Continuing, but ensure it is not transaction pooler 6543."
      ;;
  esac
}

connection_failure_hint() {
  local label="$1" url="$2" mode
  mode="$(connection_mode "$url")"
  case "$mode" in
    direct)
      err "Cannot connect to $label. Direct Supabase hosts use IPv6 by default."
      err "  If this network is IPv4-only, either enable Supabase Dedicated IPv4 add-on (paid)"
      err "  or use the session pooler URL (*.pooler.supabase.com:5432) as fallback."
      ;;
    session-pooler)
      err "Cannot connect to $label via session pooler. Check username, password, region, and project ref."
      err "  Ensure this is port 5432, not transaction pooler port 6543."
      ;;
    *)
      err "Cannot connect to $label. Check the URL, credentials, network, and IP allow-list."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
section "Pre-flight"

require pg_dump
require pg_restore
require psql

pg_dump_ver="$(pg_dump --version | awk '{print $3}' | cut -d. -f1)"
if [ "$pg_dump_ver" -lt 14 ]; then
  err "pg_dump major version $pg_dump_ver is too old (need >= 14)."
  exit 1
fi
ok "pg_dump $(pg_dump --version | awk '{print $2,$3}')"

if ! mkdir -p "$DUMP_DIR" 2>/dev/null; then
  err "Cannot create DUMP_DIR: $DUMP_DIR"
  exit 1
fi

validate_connection_mode "PROD_DB_URL" "$PROD_DB_URL"
validate_connection_mode "DEV_DB_URL" "$DEV_DB_URL"

# Test connections + read server versions (does not write).
log "Testing PROD connection..."
prod_ok=1
prod_server_ver="$(psql_c "$PROD_DB_URL" 'SHOW server_version;' 2>/dev/null || true)"
if [ -z "$prod_server_ver" ]; then
  connection_failure_hint "PROD_DB_URL" "$PROD_DB_URL"
  prod_ok=0
else
  ok "PROD reachable (PG server $prod_server_ver)"
fi

log "Testing DEV connection..."
dev_ok=1
dev_server_ver="$(psql_c "$DEV_DB_URL" 'SHOW server_version;' 2>/dev/null || true)"
if [ -z "$dev_server_ver" ]; then
  connection_failure_hint "DEV_DB_URL" "$DEV_DB_URL"
  dev_ok=0
else
  ok "DEV reachable (PG server $dev_server_ver)"
fi

if [ "$prod_ok" -eq 0 ] || [ "$dev_ok" -eq 0 ]; then
  err "Pre-flight connection check failed. Aborting."
  exit 1
fi

# Warn (not fail) on version mismatch: pg_dump must be >= server major.
prod_major="$(printf '%s' "$prod_server_ver" | cut -d. -f1)"
if [ "$pg_dump_ver" -lt "$prod_major" ]; then
  warn "pg_dump $pg_dump_ver is older than PROD server $prod_major — dump may be incomplete or fail. Upgrade postgresql-client."
fi

# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------
section "Plan"
log "PROD  → DEV"
log "Schemas: ${SCHEMAS[*]}"
log "Mode:   rename existing dev schema → <schema>_backup_${TS}, then restore"
if [ "$DRY_RUN" -eq 1 ]; then
  printf "${BLUE}[INFO]${RESET} ${BOLD}DRY-RUN${RESET} — no changes will be made.\n"
fi
if [ "$SKIP_VERIFY" -eq 1 ]; then
  log "Post-restore verification: ${YELLOW}skipped${RESET}"
else
  log "Post-restore verification: row count per table"
fi
if [ "$KEEP_DUMPS" -eq 1 ]; then
  log "Dump files kept in: $DUMP_DIR"
fi

# ---------------------------------------------------------------------------
# Sync loop
# ---------------------------------------------------------------------------
failures=0
total=${#SCHEMAS[@]}
idx=0

for schema in "${SCHEMAS[@]}"; do
  idx=$((idx + 1))
  section "[$idx/$total] Schema: $schema"

  dump_file="$DUMP_DIR/akademiq-${schema}-${TS}.dump"

  # ---- 1. Verify schema exists in prod -----------------------------------
  prod_has="$(psql_c "$PROD_DB_URL" \
    "SELECT 1 FROM information_schema.schemata WHERE schema_name = '${schema}';" 2>/dev/null || true)"
  if [ "$prod_has" != "1" ]; then
    err "Schema '$schema' does not exist in PROD. Skipping."
    failures=$((failures + 1))
    continue
  fi

  # ---- 2. Row counts from prod (for verify) ------------------------------
  if [ "$SKIP_VERIFY" -eq 0 ]; then
    log "Capturing prod row counts for verification..."
    prod_counts="$(count_rows "$PROD_DB_URL" "$schema" 2>/dev/null || true)"
  fi

  # ---- 3. Dump prod schema -----------------------------------------------
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: pg_dump --schema=$schema --format=custom → $dump_file"
  else
    log "Dumping '$schema' from prod..."
    if ! pg_dump "$PROD_DB_URL" \
        --schema="$schema" \
        --no-owner --no-acl \
        --format=custom \
        --file="$dump_file"; then
      err "pg_dump failed for schema '$schema'. Skipping."
      failures=$((failures + 1))
      [ -f "$dump_file" ] && [ "$KEEP_DUMPS" -eq 0 ] && rm -f "$dump_file"
      continue
    fi
    size="$(du -h "$dump_file" | cut -f1)"
    ok "Dumped → $dump_file ($size)"
  fi

  # ---- 4. Handle existing dev schema (rename or note absence) ------------
  dev_has="$(psql_c "$DEV_DB_URL" \
    "SELECT 1 FROM information_schema.schemata WHERE schema_name = '${schema}';" 2>/dev/null || true)"

  backup_name="${schema}_backup_${TS}"

  if [ "$dev_has" = "1" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "DRY-RUN: ALTER SCHEMA $schema RENAME TO $backup_name"
    else
      log "Renaming dev schema '$schema' → '$backup_name'"
      if ! psql "$DEV_DB_URL" -v ON_ERROR_STOP=1 -c \
          "ALTER SCHEMA \"${schema}\" RENAME TO \"${backup_name}\";"; then
        err "Rename failed for dev schema '$schema'. Aborting this schema."
        failures=$((failures + 1))
        [ -f "$dump_file" ] && [ "$KEEP_DUMPS" -eq 0 ] && rm -f "$dump_file"
        continue
      fi
      ok "Old schema preserved as '$backup_name'"
    fi
  else
    warn "Dev schema '$schema' does not exist — no backup to rename."
  fi

  # ---- 5. Create fresh schema + restore ----------------------------------
  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: CREATE SCHEMA \"$schema\"; then pg_restore --schema=$schema"
  else
    log "Creating fresh schema '$schema' in dev..."
    if ! psql "$DEV_DB_URL" -v ON_ERROR_STOP=1 -c \
        "CREATE SCHEMA \"${schema}\";"; then
      err "CREATE SCHEMA failed for '$schema'. The backup '$backup_name' is intact."
      failures=$((failures + 1))
      continue
    fi

    log "Restoring into dev schema '$schema'..."
    # pg_restore with --schema restores only that schema's objects. Because the
    # dump was produced with --schema, all TOC entries are already scoped.
    # We pipe through psql using --data-only=false via pg_restore direct connect.
    if ! pg_restore "$dump_file" \
        --dbname="$DEV_DB_URL" \
        --schema="$schema" \
        --no-owner --no-acl \
        --exit-on-error; then
      err "pg_restore failed for schema '$schema'."
      err "  Backup intact: '$backup_name'. To roll back:"
      err "    psql \"$DEV_DB_URL\" -c 'DROP SCHEMA \"${schema}\" CASCADE; ALTER SCHEMA \"${backup_name}\" RENAME TO \"${schema}\";'"
      failures=$((failures + 1))
      continue
    fi
    ok "Restore complete"
  fi

  # ---- 6. Verify row counts ----------------------------------------------
  if [ "$SKIP_VERIFY" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    log "Verifying row counts..."
    dev_counts="$(count_rows "$DEV_DB_URL" "$schema" 2>/dev/null || true)"

    mismatches=0
    # Compare prod vs dev using the prod list as source of truth.
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      tbl="${line%%|*}"
      prod_n="${line##*|}"
      dev_n="$(printf '%s\n' "$dev_counts" | grep "^${tbl}|" | head -n1 | cut -d'|' -f2 || true)"
      dev_n="${dev_n:-0}"
      if [ "$prod_n" != "$dev_n" ]; then
        warn "  $tbl: prod=$prod_n dev=$dev_n ${RED}MISMATCH${RESET}"
        mismatches=$((mismatches + 1))
      fi
    done <<< "$prod_counts"

    tbl_count="$(printf '%s\n' "$prod_counts" | grep -c '|' || true)"
    if [ "$mismatches" -eq 0 ]; then
      ok "Verified: $tbl_count tables, all row counts match."
    else
      warn "Verified: $tbl_count tables, $mismatches mismatch(es)."
      warn "  This can happen if tables have no live-tuple stats yet (ANALYZE pending)."
      warn "  Run: psql \"$DEV_DB_URL\" -c 'ANALYZE;' and re-sync to recheck."
    fi
  fi

  # ---- 7. Cleanup dump ----------------------------------------------------
  if [ "$DRY_RUN" -eq 0 ] && [ "$KEEP_DUMPS" -eq 0 ] && [ -f "$dump_file" ]; then
    rm -f "$dump_file"
    log "Removed temp dump: $dump_file"
  fi

  ok "Schema '$schema' done."
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "Summary"
if [ "$failures" -eq 0 ]; then
  ok "All $total schema(s) synced successfully."
  if [ "$DRY_RUN" -eq 0 ]; then
    log "Old dev schemas preserved as <schema>_backup_${TS}. Clean up manually:"
    log "  psql \"$DEV_DB_URL\" -c 'DROP SCHEMA iam_backup_${TS} CASCADE;'"
    log "  # ...repeat for each schema you are happy with"
  fi
  exit 0
else
  succeeded=$((total - failures))
  err "$succeeded/$total schema(s) synced. $failures failed."
  err "Check the errors above. Failed schemas may have their backup intact."
  exit 2
fi
