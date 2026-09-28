#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-update

set -euo pipefail

# Refresh the release version, source hash, and Go dependency hash.
nix-update --flake logchef

# Refresh the fixed-output Bun dependency tree separately.
nix-update --flake logchef --subpackage nodeModules
