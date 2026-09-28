---
title: External integrations
description: Connect Logchef to ClickHouse, VictoriaLogs, and an OIDC identity provider without storing secrets in Nix.
---

# External integrations

Logchef is the application layer. ClickHouse or VictoriaLogs stores log data,
and an identity provider such as ZITADEL can provide OIDC identity. Keep these
services on their own lifecycle and make their network endpoints explicit in
Logchef configuration.

## ClickHouse

Use an existing ClickHouse native endpoint or let Logchef reconcile a source through its provisioning document. Keep the password in a credential and refer to it with `secret_ref`:

```nix
services.logchef = {
  settings.provisioning = {
    manage_sources = true;
    manage_teams = true;
    prune = false;
    dry_run = true;
    sources = [
      {
        name = "Production logs";
        source_type = "clickhouse";
        secret_ref = "LOGCHEF_CH_PROD_PASSWORD";
        connection = {
          host = "clickhouse.internal:9000";
          username = "logchef";
          database = "logs";
          table_name = "otel_logs";
        };
      }
    ];
  };
  credentialFiles.LOGCHEF_CH_PROD_PASSWORD =
    "/run/secrets/logchef-clickhouse-password";
};
```

Begin with `dry_run = true`. Once the proposed changes are understood, switch
it to `false` and choose whether pruning belongs in production. This inline
document is safe to keep in `settings` because the password comes from
`secret_ref`; use `provisioningCredentialFile` only when the document itself
contains a secret.

## VictoriaLogs

VictoriaLogs uses its HTTP API and `_time` timestamp field. A bearer token can
be supplied with the same `secret_ref` pattern:

```nix
services.logchef = {
  settings.provisioning = {
    manage_sources = true;
    dry_run = true;
    sources = [
      {
        name = "Production VictoriaLogs";
        source_type = "victorialogs";
        meta_ts_field = "_time";
        meta_severity_field = "level";
        secret_ref = "LOGCHEF_VL_PROD_TOKEN";
        connection = {
          base_url = "https://victorialogs.example.com";
          auth.mode = "bearer";
          tenant = {
            account_id = "12";
            project_id = "34";
          };
          scope.query = ''{app="payments"} kubernetes.namespace:="prod"'';
        };
      }
    ];
  };
  credentialFiles.LOGCHEF_VL_PROD_TOKEN =
    "/run/secrets/logchef-victorialogs-token";
};
```

Omit `auth`, `tenant`, and `scope` when the endpoint does not use them. Account
and project IDs must be configured together for a multi-tenant VictoriaLogs
endpoint. The immutable scope is applied server-side to queries, histograms,
field discovery, live tail, and alerts.

## ZITADEL / OIDC

Create a confidential Web OIDC application in ZITADEL. For issuer `https://id.example.com`, the authorization and token endpoints are:

```nix
services.logchef.settings.oidc = {
  provider_url = "https://id.example.com";
  auth_url = "https://id.example.com/oauth/v2/authorize";
  token_url = "https://id.example.com/oauth/v2/token";
  client_id = "YOUR_ZITADEL_CLIENT_ID";
  redirect_url = "https://logs.example.com/api/v1/auth/callback";
  scopes = [ "openid" "email" "profile" ];
};
services.logchef.credentialFiles.LOGCHEF_OIDC__CLIENT_SECRET =
  "/run/secrets/logchef-oidc-client-secret";
```

Register the callback exactly, and use the same externally reachable HTTPS origin for `redirect_url` and Logchef's frontend URL. If ZITADEL is behind a reverse proxy, configure its external domain and TLS mode there as well.
