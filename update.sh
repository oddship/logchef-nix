#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-update

set -euo pipefail

version_args=()
if (( $# > 1 )); then
  echo "usage: $0 [VERSION]" >&2
  exit 2
elif (( $# == 1 )); then
  if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "invalid stable release version: $1" >&2
    exit 2
  fi
  version_args=("--version=$1")
fi

# Refresh the release version, source hash, and Go dependency hash.
nix-update --flake "${version_args[@]}" logchef

# Refresh the fixed-output Bun dependency tree separately.
nix-update --flake "${version_args[@]}" logchef --subpackage nodeModules

version="$(sed -nE 's/^[[:space:]]*version = "([^"]+)";/\1/p' package.nix | head -n1)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "could not read a stable Logchef version from package.nix" >&2
  exit 1
fi

# Keep user-facing version references synchronized with the package pin.
sed -i -E \
  "s/(The flake pins Logchef \*\*v)[0-9]+\.[0-9]+\.[0-9]+(\*\*)/\1${version}\2/" \
  README.md
sed -i -E \
  "s/(The package is built from Logchef v)[0-9]+\.[0-9]+\.[0-9]+/\1${version}/" \
  docs/01-getting-started/01-install.md
sed -i -E \
  "s|(mr-karan/logchef/blob/v)[0-9]+\.[0-9]+\.[0-9]+/|\1${version}/|g" \
  README.md docs/*.md docs/*/*.md

bash tests/check-version-docs.sh
