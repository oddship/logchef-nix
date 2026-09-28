---
title: Troubleshooting
description: Diagnose Logchef NixOS evaluation, startup, credentials, OIDC, proxy, and concurrency failures.
---

# Troubleshooting

Start with the unit status and current-boot logs:

```console
systemctl status logchef --no-pager
journalctl -u logchef -b --no-pager -n 200
```

The module catches store-safety and required-option mistakes during NixOS
evaluation. Logchef performs deeper validation, including authentication and
upstream configuration, when the service starts.

## NixOS evaluation fails

Run a non-activating build to see all assertions safely:

```console
sudo nixos-rebuild dry-build --flake .#logs
```

Common causes are an empty `adminEmails` list, a missing
`LOGCHEF_AUTH__API_TOKEN_SECRET`, a secret-bearing key under `settings`, a
secret file path inside `/nix/store`, or configuring both provisioning file
options at once.

## The service exits at startup

- Enable `localAuth.enable` or provide the complete OIDC configuration. The
  OIDC provider, authorization and token URLs, client ID, and redirect URL are
  required when local login is disabled.
- A bootstrap `localAuth.adminEmail` requires
  `LOGCHEF_AUTH__LOCAL__ADMIN_PASSWORD`, and the password must contain at least
  10 characters.
- Check every source path in `credentialFiles`. PID 1 must be able to read the
  source file when it prepares the service credential.
- Validate the API-token secret file is non-empty. Generate a fresh value with
  `openssl rand -hex 32` for a new installation; changing it later invalidates
  existing API tokens.
- If provisioning validation fails, set `dry_run = true`, confirm the v2 nested
  `connection` shape, and inspect the named source and team in the log message.

Use this to inspect the effective unit without printing secret contents:

```console
systemctl cat logchef
systemctl show logchef -p EnvironmentFiles -p LoadCredential
```

## Login or OIDC callback fails

The browser-facing origin must match `settings.server.frontend_url`, and the
OIDC provider must register the exact callback ending in
`/api/v1/auth/callback`. Check scheme, hostname, port, path, and trailing slash.

For HTTPS, use `secure_cookie = true`. For a temporary direct HTTP bootstrap,
use `false`; otherwise the browser correctly refuses to send the secure session
cookie over HTTP. Verify the OIDC client secret is supplied as
`LOGCHEF_OIDC__CLIENT_SECRET`, not in `settings`.

## The proxy reports errors or the client IP is wrong

Confirm Logchef itself responds before debugging the public proxy:

```console
curl --fail http://127.0.0.1:8125/
```

Add only the proxy's address to `server.trusted_proxies`, and make the proxy
overwrite `X-Forwarded-For` from incoming requests. For live tail through
Nginx, disable response buffering. See [[Reverse proxy and TLS]] for complete
examples.

## Queries return HTTP 429

Logchef separately limits per-user and global concurrency for preview queries,
exports, live tail, and dashboard cache fills. A histogram and its adjacent log
query consume different preview-class slots. Wait for existing work to finish,
cancel abandoned browser requests, or tune the relevant non-secret upstream
settings after measuring backend capacity.

Do not solve a 429 by indiscriminately raising every limit: ClickHouse or
VictoriaLogs may already be the constrained component. Correlate the Logchef
journal with backend latency and resource usage first.

## SQLite or state permissions fail

The service sees `/var/lib/logchef`, while the administrator sees the protected
host path `/var/lib/private/logchef`. Let `StateDirectory=logchef` manage it.
When restoring a database manually, follow [[Backup and upgrade]] so the file
has the ownership and mode expected by the dynamic service user.
