#!/usr/bin/env bash

set -euo pipefail

version="$(sed -nE 's/^[[:space:]]*version = "([^"]+)";/\1/p' package.nix | head -n1)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "could not read a stable Logchef version from package.nix" >&2
  exit 1
fi

if ! grep -Fq "The flake pins Logchef **v${version}**" README.md; then
  echo "README.md does not identify Logchef v${version} as the pinned release" >&2
  exit 1
fi

if ! grep -Fq "The package is built from Logchef v${version}." docs/01-getting-started/01-install.md; then
  echo "installation docs do not identify Logchef v${version} as the packaged release" >&2
  exit 1
fi
