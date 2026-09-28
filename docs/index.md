---
title: Overview
description: Native Nix packaging, a hardened NixOS module, and operations guidance for Logchef.
---

# logchef-nix

Native Nix packaging and a hardened NixOS service for [Logchef](https://github.com/mr-karan/logchef).

This project builds Logchef from its tagged source release, exposes it as a Nix package, and provides a service module with persistent SQLite state. Configuration that belongs in the Nix store is declarative; credentials stay in runtime files or systemd credentials.

## Start here

- [[Install]] — deploy a working local-auth instance or build the package.
- [[NixOS module]] — configure the service and its network boundary.
- [[Runtime secrets]] — choose an environment file or systemd credentials without placing secrets in the store.
- [[External integrations]] — connect ClickHouse, VictoriaLogs, or an OIDC provider.
- [[Reverse proxy and TLS]] — publish Logchef safely with Caddy or Nginx.
- [[Backup and upgrade]] — protect SQLite state and verify upgrades.
- [[Troubleshooting]] — diagnose startup, authentication, proxy, and query failures.
- [[Release checklist]] — update, test, and review a new upstream release.

## Scope

Logchef, ClickHouse, and ZITADEL are separate pieces. This repository packages and runs Logchef; it does not provision the database or identity provider.

The documentation site is plain Markdown and TOML for [Moat](https://github.com/oddship/moat). It is intentionally separate from the Nix build, so installing the package never pulls in a site generator.
