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

Your consuming configuration's `flake.lock` records the exact revision of this
flake. An upstream release or a merge to `master` does not change that pin.
Updating the input and deploying the resulting configuration can change the
Logchef binary and run database migrations at service startup. `master`
tracks reviewed upstream releases and can include breaking upstream changes.

Keep the lock file under version control. To stay on the current version,
leave its Logchef pin unchanged. To select a published release explicitly,
use its Git tag in the input URL (`github:oddship/logchef-nix/<tag>`), then
review the resulting lock diff. Check the repository's GitHub Releases page
for tags that have actually been published.

NixOS `system.stateVersion` does not pin this package or prevent upstream
migrations. Rolling back a NixOS generation restores the old binary, not the
old database schema. Keep a matching database backup and configuration lock.

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

## Upgrading from v2.6.1 to v2.7.0

Back up metadata before deploying. Startup applies SQLite migrations 000039,
000040 and 000041, or Postgres migrations 000013, 000014 and 000015. The
backup procedure above covers the module's SQLite deployment. If you manage
a Postgres metadata store separately, take and verify a Postgres backup.

Review these compatibility changes before updating the input:

- Collection links become `pin` or `managed`. Some existing shared links lose
  delegated edit permission. Run the read-only audit query in the upstream
  upgrade notes before deploying. After upgrading, admins can review **Library
  > All queries > Links that lost delegation** and restore intended delegation.
- Save dashboard edits before deployment and reload open browser tabs
  afterward. Dashboard update scripts must send the current `revision`.
  Schema 2 clients must declare their supported schema and features, and
  scripts must fetch individual dashboards to read panel blobs.
- CLI variables are typed and rendered by the server. Remove pre-quotes from
  values, for example change `--var "d='2026-11-12'"` to
  `--var d=2026-11-12`. Built-in macro names are reserved.
- ClickHouse alerts with settings that allow partial results now fail
  evaluation. Review those queries and apply the safe settings described by
  upstream before relying on alert delivery after the upgrade.

Read the [complete upstream v2.7.0 upgrade notes](https://github.com/mr-karan/logchef/blob/v2.7.0/CHANGELOG.md#270---2026-11-15)
for the audit SQL, API changes, alert settings, and multi-replica rollout
behavior. After deployment, check login, queries, dashboard saves, collection
permissions, and affected alerts. A package build and a fresh-database VM
smoke test do not validate an existing deployment's migration or scripts.

## Upgrading from v2.7.0 to v2.8.x

Plan downtime and take a consistent metadata backup. Stop every old replica
before starting the first new one: Alerting v2 does not support a rolling
upgrade. Startup applies 18 migrations per metadata store, SQLite 000042
through 000059 or Postgres 000016 through 000033. Treat them as forward-only.
The alert migrations move rule targets into destinations, and down migrations
do not restore the old targets. Rollback requires the old binary, matching
configuration lock, and the pre-upgrade database backup.

The v2.8.1 and v2.8.2 patch releases add no further migrations over v2.8.0;
upgrading directly from v2.7.0 still runs the v2.8.0 migrations.

Before deploying, review these changes:

- Alert API clients must replace `recipient_user_ids` and `webhook_urls`
  with `destination_ids`, and use notification-destination routes for webhook
  tests. Pending delivery retries are dropped during migration. Existing
  webhooks keep payload version 1, but receivers should deduplicate the new
  `Logchef-Delivery-Id` because delivery is at least once.
- Remove `alerts.evaluation_interval` and
  `LOGCHEF_ALERTS__EVALUATION_INTERVAL`. At least one replica needs
  `jobs.enabled = true` and `alerts.enabled = true` for evaluations and
  notifications. A stored `alerts.enabled` setting overrides the file and
  environment at startup. Verify SMTP in the admin settings if sending email.
- Every query is recorded with its full text in the audit log and, by
  default, a JSON server log line. Review query privacy and log shipping.
  Audit retention defaults to 30 days and 1,000,000 rows; configure bounds
  for your query volume. `audit.log_events = false` disables the JSON log
  line, not storage of the event in the metadata database.
- Reissue scoped tokens as needed for saved views, destinations, and reports;
  OAuth clients may need to authenticate again. Reading audit events requires
  a global admin with the appropriate access. Query Activity API scripts
  must handle the new payload; the old `/admin/query-activity` route is removed.
- Exported custom source headers now refer to environment variables through
  `header_secret_refs`. Supply every referenced secret at runtime. Missing
  values prevent provisioning startup. Keep provisioning and credentials out
  of the Nix store using the module's runtime secret options.
- A Loki source grants linked teams access to the whole tenant; its default
  selector is not an access restriction. Review source access and shared
  dashboard edit permissions, and reload browser tabs after deployment.

Read the [complete upstream v2.8 upgrade notes](https://github.com/mr-karan/logchef/blob/v2.8.2/CHANGELOG.md#upgrade-notes)
and the v2.8.1/v2.8.2 fixes before deploying. Verify login, queries, alerts,
notification delivery, reports, provisioning, and token access after startup.
Package and fresh-database VM checks do not establish that a production
database upgrade or existing integrations will succeed.

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
