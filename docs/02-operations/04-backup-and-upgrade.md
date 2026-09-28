---
title: Backup and upgrade
description: Back up and restore Logchef SQLite state, deploy flake updates, and verify migrations safely.
---

# Backup and upgrade

Log data remains in ClickHouse or VictoriaLogs. Logchef's SQLite database holds
application metadata such as users, teams, sources, saved queries, dashboards,
and settings, so protect it before an upgrade.

## Understand the state path

The module configures `/var/lib/logchef/logchef.db` inside the service. Because
the unit uses `DynamicUser=true` and `StateDirectory=logchef`, the same state is
visible to the host administrator at:

```text
/var/lib/private/logchef/logchef.db
```

Do not change `services.logchef.settings.sqlite.path`; the module owns it.

## Create a consistent backup

Stopping Logchef briefly is the simplest way to make a consistent file backup:

```console
sudo systemctl stop logchef
sudo install -d -m 0700 /var/backups/logchef
sudo install -m 0600 /var/lib/private/logchef/logchef.db \
  /var/backups/logchef/logchef.db-YYYY-MM-DD
sudo systemctl start logchef
systemctl is-active logchef
```

Copy the backup to storage with an independent failure domain and test restores
periodically. The runtime secret files are not part of SQLite; back up their
encrypted source through the secret manager that owns them.

## Upgrade

Review the generated upstream-update pull request and release notes first. On
the NixOS configuration repository that consumes this flake:

```console
nix flake lock --update-input logchef
sudo nixos-rebuild dry-build --flake .#logs
```

Create the SQLite backup, then deploy and inspect the new boot's logs:

```console
sudo nixos-rebuild switch --flake .#logs
systemctl status logchef --no-pager
journalctl -u logchef -b --no-pager -n 100
curl --fail http://127.0.0.1:8125/
```

Exercise login and one query against each datasource. A successful HTTP fetch
proves that the UI is served, but not that OIDC, credentials, migrations, or
backend queries work.

## Restore

First roll the NixOS configuration and its flake lock back to the version that
created the backup. Then stop Logchef and restore the database while preserving
the ownership expected by a dynamic user:

```console
sudo systemctl stop logchef
sudo install -o nobody -g nogroup -m 0600 \
  /var/backups/logchef/logchef.db-YYYY-MM-DD \
  /var/lib/private/logchef/logchef.db
sudo systemctl start logchef
journalctl -u logchef -b --no-pager -n 100
```

Keep the failed database under a different filename until the restore is
verified. Do not restore an older schema underneath a newer binary unless the
upstream release notes explicitly say that downgrade is supported.
