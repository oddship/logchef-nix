---
title: Runtime secrets
description: Keep Logchef API, OIDC, datasource, and local-auth credentials out of the Nix store.
---

# Runtime secrets

Nix evaluates module settings into the store. Treat every value placed in `services.logchef.settings` as public. Do not use `builtins.toFile`, `pkgs.writeText`, or a quoted Nix string for a password, token, DSN, or OIDC client secret.

## Runtime environment file

Use a file created by sops-nix, agenix, or another secret manager:

```nix
services.logchef.environmentFile = "/run/secrets/logchef.env";
```

The file can contain ordinary systemd assignments:

```text
LOGCHEF_AUTH__API_TOKEN_SECRET=replace-me
LOGCHEF_OIDC__CLIENT_SECRET=replace-me
```

The path must not be in `/nix/store`.

## File-backed systemd credentials

`credentialFiles` maps a Logchef environment variable to a runtime file. The module gives the file a private credential name and exports its contents only in the service process:

```nix
services.logchef.credentialFiles = {
  LOGCHEF_AUTH__API_TOKEN_SECRET = "/run/secrets/logchef-api-token-secret";
  LOGCHEF_OIDC__CLIENT_SECRET = "/run/secrets/logchef-oidc-client-secret";
};
```

## Encrypted credentials

For credentials supplied by systemd or an external provisioning layer, use `credentialNames` and define the matching `LoadCredentialEncrypted` entries in a service override:

```nix
services.logchef.credentialNames.LOGCHEF_AUTH__API_TOKEN_SECRET =
  "logchef-api-token-secret";

systemd.services.logchef.serviceConfig.LoadCredentialEncrypted = [
  "logchef-api-token-secret:/etc/credstore.encrypted/logchef-api-token-secret"
];
```

The service reads credentials through `$CREDENTIALS_DIRECTORY`; secret values do not appear in the generated TOML or the Nix store.

## Local authentication

For a bootstrap account, enable local auth and provide the password through the same runtime mechanisms:

```nix
services.logchef.localAuth = {
  enable = true;
  adminEmail = "admin@example.com";
};
services.logchef.credentialFiles.LOGCHEF_AUTH__LOCAL__ADMIN_PASSWORD =
  "/run/secrets/logchef-local-admin-password";
```
