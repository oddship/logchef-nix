# External integrations

Logchef is the application layer. ClickHouse stores log data, and ZITADEL can provide OIDC identity. Keep both services on their own lifecycle and make their network endpoints explicit in Logchef configuration.

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

Begin with `dry_run = true`. When the proposed changes are understood, move the document to `provisioningCredentialFile` and choose whether reconciliation and pruning belong in production.

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
