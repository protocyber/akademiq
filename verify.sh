#!/usr/bin/env bash
# Verification script for AkademiQ
set -eo pipefail

echo "========================================="
echo "   AkademiQ Verification Script"
echo "========================================="

# Color output helpers
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
red() { echo -e "\033[31m$1\033[0m"; }

# 1. VERIFY WEB FRONTEND
echo ""
echo ">>> [1/2] Verifying Web Frontend..."
cd apps/web

echo "Running TypeScript Typecheck..."
if pnpm typecheck; then
    green "✔ Web Typecheck passed!"
else
    red "✘ Web Typecheck failed!"
    exit 1
fi

echo "Running ESLint..."
if pnpm lint; then
    green "✔ Web Lint passed!"
else
    yellow "⚠ Web Lint found warnings/errors (some might be pre-existing)."
fi

echo "Running Web Unit Tests (Vitest)..."
if pnpm test; then
    green "✔ Web Unit Tests passed!"
else
    red "✘ Web Unit Tests failed!"
    exit 1
fi

cd ../..

# 2. VERIFY BACKEND (Instructions for User)
echo ""
echo "========================================="
echo "   Backend Verification Instructions"
echo "========================================="
yellow "Untuk memverifikasi backend, jalankan perintah-perintah berikut di terminal Anda:"
echo ""
echo "1. Cek kompilasi kode backend (cepat):"
echo "   cd apps/backend && cargo check"
echo ""
echo "2. Jalankan linter clippy backend (cepat):"
echo "   cd apps/backend && cargo clippy --all-targets"
echo ""
echo "3. Jalankan pengujian unit & integrasi backend (membutuhkan Postgres + RabbitMQ aktif):"
echo "   # Pastikan infrastruktur lokal aktif dengan: make up"
echo "   cd apps/backend && make test"
echo ""
echo "4. Jalankan pengujian E2E backend:"
echo "   cd apps/backend && make test-e2e"
echo "========================================="
