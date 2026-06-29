#!/usr/bin/env bash
# =============================================================================
# AkademiQ — confirm
# =============================================================================
# Interactive guard for SLOW / EXPENSIVE make targets (Docker image builds,
# full test suites, cargo clean). Prints a cost warning and asks before
# proceeding.
#
# Usage: bash scripts/confirm.sh "<label>" "<cost description>"
#   exit 0 → proceed   |   exit 1 → user declined (caller aborts)
#
# Auto-proceeds (no prompt) when ANY of these hold, so CI / scripts never hang:
#   • YES is set         (e.g. `make build YES=1`, or a parent make delegating)
#   • CI is set          (GitHub Actions etc.)
#   • stdin is not a TTY  (piped / non-interactive)
# =============================================================================
set -euo pipefail

YELLOW='\033[0;33m'
RESET='\033[0m'

label="${1:-this command}"
cost="${2:-this is a slow / expensive operation}"

if [ -n "${YES:-}" ] || [ -n "${CI:-}" ] || [ ! -t 0 ]; then
  exit 0
fi

printf "${YELLOW}\n"
printf "  ⚠️  %s is SLOW\n" "$label"
printf "     %s\n" "$cost"
printf "${RESET}"
printf "  Proceed? [y/N] "
read -r ans
case "$ans" in
  [yY] | [yY][eE][sS]) exit 0 ;;
  *) echo ">> aborted (skip this guard with:  YES=1 make <target>)"; exit 1 ;;
esac
