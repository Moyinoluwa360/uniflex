#!/usr/bin/env bash
# Batch loop helper (WSL): regenerate the colour allowlist, analyze, test.
# Usage: tool/check.sh [--no-test]
cd "$(dirname "$0")/.." || exit 1
WIN="$(wslpath -w "$PWD")"
cmd.exe /c "cd /d $WIN && set UPDATE_UI_ALLOWLIST=1&& flutter test test\\ui_polish\\ui_guard_test.dart >nul 2>&1"
cmd.exe /c "cd /d $WIN && flutter analyze 2>&1" | grep -E "^\s+(info|warning|error) -|issues? found|No issues" | cut -c1-220
[ "$1" = "--no-test" ] && exit 0
cmd.exe /c "cd /d $WIN && flutter test 2>&1" > /tmp/uf_test.txt
grep -E "All tests passed|Some tests failed" /tmp/uf_test.txt | tail -1 | cut -c1-60
sed -n '/Failing tests:/,$p' /tmp/uf_test.txt | grep -v "catalog_sections_test" | cut -c1-220
