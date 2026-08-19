# NixOS module

The module writes non-secret settings to a generated TOML file and supplies the operational values that must remain stable: the listen address, port, SQLite path, administrator emails, and local-auth mode.

SQLite lives at `/var/lib/logchef/logchef.db`. systemd creates the state directory with mode `0700`; the service runs as a dynamic user with a read-only system filesystem, no capabilities, a private `/tmp`, device and namespace isolation, and syscall filtering.

The module asserts that an administrator email and `LOGCHEF_AUTH__API_TOKEN_SECRET` are available at runtime. It also rejects common secret-bearing keys such as `client_secret`, `password`, `api_key`, and `dsn` inside `services.logchef.settings`.

## Useful options

| Option | Purpose |
| --- | --- |
| `services.logchef.package` | Override the Logchef package. |
| `services.logchef.listenAddress` / `port` | Set the bind address and port. |
| `services.logchef.openFirewall` | Open the configured TCP port. Defaults to `false`. |
| `services.logchef.settings` | Store non-secret upstream TOML settings. |
| `services.logchef.environmentFile` | Read runtime `LOGCHEF_*` assignments. |
| `services.logchef.credentialFiles` | Load secret files through `LoadCredential=`. |
| `services.logchef.credentialNames` | Reference credentials supplied by a unit override. |
| `services.logchef.provisioningCredentialFile` | Load a complete provisioning document as a credential. |

The module owns `server.host`, `server.port`, `sqlite.path`, administrator emails, and local-auth enablement. Those values cannot be changed accidentally through the free-form settings attrset.
