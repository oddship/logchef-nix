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
