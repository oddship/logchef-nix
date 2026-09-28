#!/usr/bin/env bash
set -euo pipefail

site_dir="$(mktemp -d)"
trap 'rm -rf -- "$site_dir"' EXIT

go run github.com/oddship/moat@v0.6.2 build docs/ "$site_dir/"
python3 scripts/finalize-docs.py \
  "$site_dir" \
  "https://oddship.github.io/logchef-nix"
python3 tests/check-built-docs.py \
  "$site_dir" \
  "/logchef-nix" \
  "https://oddship.github.io/logchef-nix"
