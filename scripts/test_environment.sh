#!/usr/bin/env bash

set -e

echo "== Aegis Harness Environment Validation =="

echo ""
echo "[Node]"
node --version

echo ""
echo "[npm]"
npm --version

echo ""
echo "[TypeScript]"
tsc --version

echo ""
echo "[ESLint]"
eslint --version

echo ""
echo "[AST-Grep]"
ast-grep --version || sg --version

echo ""
echo "[Python]"
python3 --version

echo ""
echo "[Git]"
git --version

echo ""
echo "Environment validation complete."
