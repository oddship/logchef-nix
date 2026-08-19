# logchef-nix

Native Nix packaging and a hardened NixOS service for [Logchef](https://github.com/mr-karan/logchef).

This project builds Logchef from its tagged source release, exposes it as a Nix package, and provides a service module with persistent SQLite state. Configuration that belongs in the Nix store is declarative; credentials stay in runtime files or systemd credentials.

## Start here

- [[Install]] — build the package or add the flake to a NixOS host.
- [[NixOS module]] — configure the service and its network boundary.
- [[Runtime secrets]] — choose an environment file or systemd credentials without placing secrets in the store.
- [[External integrations]] — connect an existing ClickHouse and ZITADEL installation.
- [[Release checklist]] — update, test, and review a new upstream release.

## Scope

Logchef, ClickHouse, and ZITADEL are separate pieces. This repository packages and runs Logchef; it does not provision the database or identity provider.

The documentation site is plain Markdown and TOML for [Moat](https://github.com/oddship/moat). It is intentionally separate from the Nix build, so installing the package never pulls in a site generator.
