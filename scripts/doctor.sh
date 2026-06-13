#!/usr/bin/env bash
# =============================================================================
# AcademiQ — doctor
# =============================================================================
# Checks that all required and optional dev tools are present and prints
# install hints for anything missing.
#
# Exit code: 0 if all required tools are present, 1 otherwise.
#
# Called by: make doctor (root repo)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

BACKEND_DIR="${BACKEND_DIR:-apps/backend}"
WEB_DIR="${WEB_DIR:-apps/web}"

fail=0

check_required() {
  local label="$1" cmd="$2" hint="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "  ${GREEN}✓${RESET} %s\n" "$label"
  else
    printf "  ${RED}✗${RESET} %s — missing. %s\n" "$label" "$hint"
    fail=1
  fi
}

check_optional() {
  local label="$1" cmd="$2" hint="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf "  ${GREEN}✓${RESET} %s\n" "$label"
  else
    printf "  ${YELLOW}·${RESET} %s — optional, not found. %s\n" "$label" "$hint"
  fi
}

check_openssl_dev() {
  if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists openssl; then
    printf "  ${GREEN}✓${RESET} OpenSSL development files (%s)\n" "$(pkg-config --modversion openssl)"
    return
  fi

  printf "  ${RED}✗${RESET} OpenSSL development files — pkg-config cannot find openssl.\n"

  case "$(uname -s)" in
    Darwin)
      printf "    Install: brew install pkg-config openssl@3\n"
      printf "    If still missing: export PKG_CONFIG_PATH=\"$(brew --prefix openssl@3 2>/dev/null || printf /opt/homebrew/opt/openssl@3)/lib/pkgconfig:\${PKG_CONFIG_PATH:-}\"\n"
      ;;
    Linux)
      printf "    Debian/Ubuntu: sudo apt-get install pkg-config libssl-dev\n"
      printf "    Fedora:        sudo dnf install pkgconf openssl-devel\n"
      printf "    Arch:          sudo pacman -S pkgconf openssl\n"
      ;;
    *)
      printf "    Install pkg-config plus OpenSSL headers/libs, or set OPENSSL_DIR.\n"
      ;;
  esac

  fail=1
}

echo "Required tooling:"

check_required "git"            "git"     "Install via your OS package manager."
check_required "docker"         "docker"  "Install Docker Desktop >= 4.24 (https://www.docker.com/)."

if command -v docker >/dev/null 2>&1; then
  cv=$(docker compose version --short 2>/dev/null || echo 0.0.0)
  if [ "$(printf "2.22.0\n%s\n" "$cv" | sort -V | head -n1)" = "2.22.0" ]; then
    printf "  ${GREEN}✓${RESET} docker compose plugin (%s) >= 2.22\n" "$cv"
  else
    printf "  ${RED}✗${RESET} docker compose plugin too old (%s) — need >= 2.22 for compose --watch.\n" "$cv"
    fail=1
  fi
fi

check_required "node"           "node"    "Install Node 20 LTS via nvm (https://github.com/nvm-sh/nvm)."
check_required "corepack"       "corepack" "Run: corepack enable (bundled with Node >= 16.13)."
check_required "rustc (stable)" "rustc"   "Install via rustup (https://rustup.rs/)."
check_required "cargo"          "cargo"   "Bundled with rustup."
check_openssl_dev

if command -v node >/dev/null 2>&1; then
  nv=$(node --version | sed 's/^v//')
  if [ "$(printf "20.0.0\n%s\n" "$nv" | sort -V | head -n1)" = "20.0.0" ]; then
    printf "  ${GREEN}✓${RESET} node (%s) >= 20\n" "$nv"
  else
    printf "  ${YELLOW}·${RESET} node version (%s) is below 20 LTS — nvm use should pick up apps/web/.nvmrc.\n" "$nv"
  fi
fi

echo ""
echo "Optional tooling:"

check_optional "mprocs (primary, used by make dev)" "mprocs" "brew install mprocs   (or  cargo install mprocs)"
check_optional "tmux (used by make dev-tmux)"       "tmux"   "brew install tmux"

# Host dev loop (make dev-host): cargo-watch reruns on save; clang + mold give
# the fast linker injected via RUSTFLAGS. Missing mold/clang only matters for
# the host loop — CI and Docker image builds do NOT use mold.
check_optional "cargo-watch (host dev loop)" "cargo-watch" "cargo install cargo-watch"
check_optional "clang (host dev loop linker)" "clang" "Debian/Ubuntu: sudo apt-get install clang   |   macOS: ships with Xcode CLT"
check_optional "mold (host dev loop linker)"  "mold"  "Debian/Ubuntu: sudo apt-get install mold    |   macOS: brew install mold"

if [ -d "${WEB_DIR}/node_modules/@playwright" ]; then
  printf "  ${GREEN}✓${RESET} Playwright browsers (apps/web/node_modules/@playwright present)\n"
else
  printf "  ${YELLOW}·${RESET} Playwright not installed yet — run: cd %s && pnpm install && pnpm exec playwright install\n" "$WEB_DIR"
fi

echo ""
echo ".env files:"

for f in .env "${BACKEND_DIR}/.env" "${WEB_DIR}/.env"; do
  if [ -f "$f" ]; then
    printf "  ${GREEN}✓${RESET} %s\n" "$f"
  else
    printf "  ${YELLOW}·${RESET} %s missing — run: cp %s.example %s\n" "$f" "$f" "$f"
  fi
done

echo ""

if [ "$fail" -ne 0 ]; then
  echo "Doctor: required tools missing. Fix the items marked ✗ above."
  exit 1
else
  echo "Doctor: all required tools present."
fi
