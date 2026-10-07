---
title: NixOS module
description: Reference for every logchef-nix NixOS service option and its security boundary.
---

# NixOS module

The module writes non-secret settings to a generated TOML file and supplies the operational values that must remain stable: the listen address, port, SQLite path, administrator emails, and local-auth mode.

SQLite lives at `/var/lib/logchef/logchef.db`. systemd creates the state directory with mode `0700`; the service runs as a dynamic user with a read-only system filesystem, no capabilities, a private `/tmp`, device and namespace isolation, and syscall filtering.

The module asserts that an administrator email and `LOGCHEF_AUTH__API_TOKEN_SECRET` are available at runtime. It also rejects common secret-bearing keys such as `client_secret`, `password`, `api_key`, and `dsn` inside `services.logchef.settings`.

## Useful options

| Option | Purpose |
| --- | --- |
| `services.logchef.package` | Override the Logchef package. |
| `services.logchef.listenAddress` | Bind address. Defaults to `127.0.0.1`. |
| `services.logchef.port` | TCP port. Defaults to `8125`. |
| `services.logchef.openFirewall` | Open the configured TCP port. Defaults to `false`. |
| `services.logchef.adminEmails` | Required list of addresses granted global administrator access. |
| `services.logchef.localAuth.enable` | Enable built-in email/password login. Defaults to `false`. |
| `services.logchef.localAuth.adminEmail` | Optional bootstrap administrator; requires local auth and its password credential. |
| `services.logchef.settings` | Store non-secret upstream TOML settings. |
| `services.logchef.environmentFile` | Read runtime `LOGCHEF_*` assignments. |
| `services.logchef.credentialFiles` | Load secret files through `LoadCredential=`. |
| `services.logchef.credentialNames` | Reference credentials supplied by a unit override. |
| `services.logchef.provisioningFile` | Reference a runtime provisioning document already readable by the service. |
| `services.logchef.provisioningCredentialFile` | Load a complete provisioning document as a credential. |

The module owns `server.host`, `server.port`, `sqlite.path`, administrator emails, and local-auth enablement. Those values cannot be changed accidentally through the free-form settings attrset.

`settings` accepts the remaining non-secret keys from the upstream
[`config.toml`](https://github.com/mr-karan/logchef/blob/v2.2.0/config.toml).
Use nested Nix attributes for TOML sections and underscores for upstream key
names. Secrets are rejected recursively, so supply them through one of the
runtime mechanisms instead.

## Provisioning files

Inline, non-secret provisioning can stay under `settings.provisioning`. A
source's `secret_ref` names an environment variable supplied through
`credentialFiles`, `credentialNames`, or `environmentFile`; it does not make
the provisioning document secret.

Use `provisioningFile` when an external secret manager already creates a
runtime document readable by the dynamic service user. Use
`provisioningCredentialFile` when systemd should copy the complete document
into its private credential directory, especially when the document contains
passwords or tokens. Configure only one of these two options.
