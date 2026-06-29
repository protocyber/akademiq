#!/usr/bin/env bash
# =============================================================================
# AkademiQ — DB sync (prod Supabase → local dev Postgres)
# =============================================================================
# Dumps each service schema from the production Supabase database and restores it
# into the local development Postgres database. Both sides use one database with
# one schema per service (iam, billing, academic_config, academic_ops, grading).
#
# Safety model:
#   - Existing local schema is RENAMED to <schema>_backup_<ts> before restore.
#   - Backups are NEVER auto-purged.
#   - pg_dump/pg_restore use --no-owner --no-acl.
#
# Usage:
#   PROD_DB_URL=postgres://postgres.<prod-ref>:PASS@db.<prod-ref>.supabase.co:5432/postgres \
#   ./scripts/db-sync.sh
#
#   PROD_DB_URL=postgres://postgres.<prod-ref>:PASS@aws-1-<region>.pooler.supabase.com:5432/postgres \
#   LOCAL_DB_URL=postgres://akademiq:akademiq_dev@127.0.0.1:54320/akademiq \
#   ./scripts/db-sync.sh
#
# Flags:
#   --dry-run          Show what would happen without touching either DB.
#   --schema NAME      Sync only one schema (may be repeated).
#   --skip-verify      Skip post-restore row-count comparison.
#   --keep-dumps       Keep the .dump files in ${DUMP_DIR} (default: /tmp).
#   --help, -h         Show this help.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

DEFAULT_SCHEMAS=("iam" "billing" "academic_config" "academic_ops" "grading")
DRY_RUN=0
SKIP_VERIFY=0
KEEP_DUMPS=0
SCHEMAS=()

usage() {
  sed -n '3,${ /^#/!q; s/^# \?//; p; }' "$0"
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --skip-verify) SKIP_VERIFY=1; shift ;;
    --keep-dumps) KEEP_DUMPS=1; shift ;;
    --schema)
      [ $# -ge 2 ] || { echo "ERROR: --schema requires an argument." >&2; exit 1; }
      SCHEMAS+=("$2"); shift 2 ;;
    --schema=*) SCHEMAS+=("${1#--schema=}"); shift ;;
    --help|-h) usage ;;
    *) echo "ERROR: unknown argument: $1 (try --help)" >&2; exit 1 ;;
  esac
done

if [ ${#SCHEMAS[@]} -eq 0 ]; then
  SCHEMAS=("${DEFAULT_SCHEMAS[@]}")
fi

PROD_DB_URL="${PROD_DB_URL:-}"
DUMP_DIR="${DUMP_DIR:-/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="${BACKEND_DIR:-$REPO_ROOT/apps/backend}"

local_env_value() {
  local key="$1"
  if [ -f "$BACKEND_DIR/.env" ]; then
    grep "^${key}=" "$BACKEND_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true
  fi
}

POSTGRES_USER="${POSTGRES_USER:-$(local_env_value POSTGRES_USER)}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(local_env_value POSTGRES_PASSWORD)}"
POSTGRES_PORT="${POSTGRES_PORT:-$(local_env_value POSTGRES_PORT)}"
POSTGRES_USER="${POSTGRES_USER:-akademiq}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-akademiq_dev}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
LOCAL_DB_URL="${LOCAL_DB_URL:-postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${POSTGRES_PORT}/akademiq}"

log() { printf "${BLUE}[INFO]${RESET} %s\n" "$*"; }
ok() { printf "${GREEN}[ OK ]${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${RESET} %s\n" "$*"; }
err() { printf "${RED}[ERR ]${RESET} %s\n" "$*" >&2; }
section() { printf "\n${BOLD}${BLUE}━━━ %s ━━━${RESET}\n" "$*"; }

require() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Required tool missing: $cmd"
    exit 1
  fi
}

psql_c() { psql "$1" -v ON_ERROR_STOP=1 -tAc "$2"; }

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

validate_prod_connection_mode() {
  local mode
  mode="$(connection_mode "$PROD_DB_URL")"
  case "$mode" in
    direct)
      ok "PROD_DB_URL connection mode: direct Supabase host"
      warn "PROD direct host requires IPv6 unless Dedicated IPv4 is enabled."
      ;;
    session-pooler)
      warn "PROD_DB_URL connection mode: session pooler fallback."
      ;;
    transaction-pooler)
      err "PROD_DB_URL uses transaction pooler port 6543. This is not supported."
      exit 1
      ;;
    custom)
      warn "PROD_DB_URL connection mode: custom/unrecognized host."
      ;;
  esac
}

if [ -z "$PROD_DB_URL" ]; then
  err "PROD_DB_URL is not set."
  echo "  PROD_DB_URL=postgres://postgres.<prod-ref>:PASS@db.<prod-ref>.supabase.co:5432/postgres ./scripts/db-sync.sh" >&2
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"

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

mkdir -p "$DUMP_DIR"
validate_prod_connection_mode

log "Testing PROD connection..."
prod_server_ver="$(psql_c "$PROD_DB_URL" 'SHOW server_version;' 2>/dev/null || true)"
if [ -z "$prod_server_ver" ]; then
  err "Cannot connect to PROD_DB_URL."
  exit 1
fi
ok "PROD reachable (PG server $prod_server_ver)"

log "Testing local connection..."
local_server_ver="$(psql_c "$LOCAL_DB_URL" 'SHOW server_version;' 2>/dev/null || true)"
if [ -z "$local_server_ver" ]; then
  err "Cannot connect to LOCAL_DB_URL. Is local Postgres up?"
  err "  Try: make up"
  exit 1
fi
ok "Local reachable (PG server $local_server_ver)"

prod_major="$(printf '%s' "$prod_server_ver" | cut -d. -f1)"
if [ "$pg_dump_ver" -lt "$prod_major" ]; then
  warn "pg_dump $pg_dump_ver is older than PROD server $prod_major."
fi

section "Plan"
log "PROD Supabase → local Postgres"
log "Schemas: ${SCHEMAS[*]}"
log "Mode: rename existing local schema → <schema>_backup_${TS}, then restore"
if [ "$DRY_RUN" -eq 1 ]; then
  printf "${BLUE}[INFO]${RESET} ${BOLD}DRY-RUN${RESET} — no changes will be made.\n"
fi

failures=0
total=${#SCHEMAS[@]}
idx=0

for schema in "${SCHEMAS[@]}"; do
  idx=$((idx + 1))
  section "[$idx/$total] Schema: $schema"
  dump_file="$DUMP_DIR/akademiq-local-${schema}-${TS}.dump"

  prod_has="$(psql_c "$PROD_DB_URL" "SELECT 1 FROM information_schema.schemata WHERE schema_name = '${schema}';" 2>/dev/null || true)"
  if [ "$prod_has" != "1" ]; then
    err "Schema '$schema' does not exist in PROD. Skipping."
    failures=$((failures + 1))
    continue
  fi

  if [ "$SKIP_VERIFY" -eq 0 ]; then
    log "Capturing prod row counts for verification..."
    prod_counts="$(count_rows "$PROD_DB_URL" "$schema" 2>/dev/null || true)"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: pg_dump --schema=$schema --format=custom → $dump_file"
  else
    log "Dumping '$schema' from prod..."
    if ! pg_dump "$PROD_DB_URL" --schema="$schema" --no-owner --no-acl --format=custom --file="$dump_file"; then
      err "pg_dump failed for schema '$schema'. Skipping."
      failures=$((failures + 1))
      [ -f "$dump_file" ] && [ "$KEEP_DUMPS" -eq 0 ] && rm -f "$dump_file"
      continue
    fi
    ok "Dumped → $dump_file ($(du -h "$dump_file" | cut -f1))"
  fi

  local_has="$(psql_c "$LOCAL_DB_URL" "SELECT 1 FROM information_schema.schemata WHERE schema_name = '${schema}';" 2>/dev/null || true)"
  backup_name="${schema}_backup_${TS}"

  if [ "$local_has" = "1" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "DRY-RUN: ALTER SCHEMA $schema RENAME TO $backup_name"
    else
      log "Renaming local schema '$schema' → '$backup_name'"
      if ! psql "$LOCAL_DB_URL" -v ON_ERROR_STOP=1 -c "ALTER SCHEMA \"${schema}\" RENAME TO \"${backup_name}\";"; then
        err "Rename failed for local schema '$schema'."
        failures=$((failures + 1))
        [ -f "$dump_file" ] && [ "$KEEP_DUMPS" -eq 0 ] && rm -f "$dump_file"
        continue
      fi
      ok "Old schema preserved as '$backup_name'"
    fi
  else
    warn "Local schema '$schema' does not exist — no backup to rename."
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: CREATE SCHEMA \"$schema\"; then pg_restore --schema=$schema"
  else
    log "Creating fresh schema '$schema' locally..."
    if ! psql "$LOCAL_DB_URL" -v ON_ERROR_STOP=1 -c "CREATE SCHEMA \"${schema}\";"; then
      err "CREATE SCHEMA failed for '$schema'. Backup '$backup_name' is intact."
      failures=$((failures + 1))
      continue
    fi

    log "Restoring into local schema '$schema'..."
    if ! pg_restore "$dump_file" --dbname="$LOCAL_DB_URL" --schema="$schema" --no-owner --no-acl --exit-on-error; then
      err "pg_restore failed for schema '$schema'."
      err "  Backup intact: '$backup_name'."
      failures=$((failures + 1))
      continue
    fi
    ok "Restore complete"
  fi

  if [ "$SKIP_VERIFY" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    log "Verifying row counts..."
    local_counts="$(count_rows "$LOCAL_DB_URL" "$schema" 2>/dev/null || true)"
    mismatches=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      tbl="${line%%|*}"
      prod_n="${line##*|}"
      local_n="$(printf '%s\n' "$local_counts" | grep "^${tbl}|" | head -n1 | cut -d'|' -f2 || true)"
      local_n="${local_n:-0}"
      if [ "$prod_n" != "$local_n" ]; then
        warn "  $tbl: prod=$prod_n local=$local_n MISMATCH"
        mismatches=$((mismatches + 1))
      fi
    done <<< "$prod_counts"

    tbl_count="$(printf '%s\n' "$prod_counts" | grep -c '|' || true)"
    if [ "$mismatches" -eq 0 ]; then
      ok "Verified: $tbl_count tables, all row counts match."
    else
      warn "Verified: $tbl_count tables, $mismatches mismatch(es)."
      warn "  This can happen if pg_stat live-tuple stats are stale. Run ANALYZE and recheck."
    fi
  fi

  if [ "$DRY_RUN" -eq 0 ] && [ "$KEEP_DUMPS" -eq 0 ] && [ -f "$dump_file" ]; then
    rm -f "$dump_file"
    log "Removed temp dump: $dump_file"
  fi

  ok "Schema '$schema' done."
done

section "Summary"
if [ "$failures" -eq 0 ]; then
  ok "All $total schema(s) synced successfully."
  if [ "$DRY_RUN" -eq 0 ]; then
    log "Old local schemas preserved as <schema>_backup_${TS}. Clean them up manually when ready."
  fi
  exit 0
else
  succeeded=$((total - failures))
  err "$succeeded/$total schema(s) synced. $failures failed."
  exit 2
fi
