# logchef-nix

A native Nix package and hardened NixOS service for
[Logchef](https://github.com/mr-karan/logchef). It runs the upstream server
directly; Docker, Podman, OCI images, and container runtimes are not involved.

The flake pins Logchef **v2.0.2** and a NixOS 26.05 Nixpkgs revision. The build
uses the upstream `bun.lock` to compile the Vite UI, embeds that UI in the Go
server, and uses the upstream `go.sum` for Go dependencies. The source and both
dependency trees have fixed hashes, so a build does not depend on a mutable
package registry.

The longer-form documentation lives in [`docs/`](./docs/). It is written for
[Moat](https://github.com/oddship/moat), a lightweight Markdown-to-static-site
generator with a built-in layout and search. Build it locally with:

```console
go install github.com/oddship/moat@v0.6.2
moat build docs/ _site/
```

The [Documentation workflow](./.github/workflows/docs.yml) invokes Moat's
reusable GitHub Pages workflow whenever `docs/` changes. It pins Moat v0.6.2,
publishes the generated site from `master`, and can be started with **Run
workflow** when a manual rebuild is needed.

The published project site is [oddship.github.io/logchef-nix](https://oddship.github.io/logchef-nix/).

## Outputs

- `packages.x86_64-linux.default` and `.logchef`
- `packages.aarch64-linux.default` and `.logchef`
- `nixosModules.default`
- `devShells.<system>.default`
- `formatter.<system>`
- package, module-evaluation, and x86_64 NixOS VM checks

Upstream publishes Linux server releases for amd64 and arm64, and its release
pipeline builds the same Go server for both. This flake therefore supports
`x86_64-linux` and `aarch64-linux`.

## NixOS usage

Add this flake and import its module:

```nix
{
  inputs.logchef.url = "github:oddship/logchef-nix";

  outputs = { nixpkgs, logchef, ... }: {
    nixosConfigurations.logs = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        logchef.nixosModules.default
        {
          services.logchef = {
            enable = true;
            adminEmails = [ "admin@example.com" ];

            # Keep secrets outside the Nix store.
            credentialFiles.LOGCHEF_AUTH__API_TOKEN_SECRET =
              "/run/secrets/logchef-api-token-secret";

            # Bind publicly only when a reverse proxy or firewall policy is ready.
            listenAddress = "127.0.0.1";
            port = 8125;

            settings = {
              server = {
                frontend_url = "https://logs.example.com";
                secure_cookie = true;
                trusted_proxies = [ "127.0.0.1" ];
              };
              logging.level = "info";
              ai.enabled = false;
            };
          };

          system.stateVersion = "26.05";
        }
      ];
    };
  };
}
```

Generate the required API-token hashing secret with, for example,
`openssl rand -hex 32`. Because `services.logchef.settings` becomes a
world-readable Nix store file, the module rejects known secret-bearing keys in
that attrset.

SQLite metadata is persisted at `/var/lib/logchef/logchef.db`. systemd owns the
directory through `StateDirectory=logchef` with mode `0700`; the service uses a
dynamic user, a read-only filesystem, no capabilities, namespace and device
isolation, syscall filtering, and other sandboxing controls.

### Runtime secrets

There are three supported patterns.

1. Map each environment variable to a runtime file. systemd copies it into the
   unit's private credential directory:

   ```nix
   services.logchef.credentialFiles = {
     LOGCHEF_AUTH__API_TOKEN_SECRET = "/run/secrets/logchef-api-token-secret";
     LOGCHEF_OIDC__CLIENT_SECRET = "/run/secrets/logchef-oidc-client-secret";
   };
   ```

2. Supply encrypted or externally managed systemd credentials yourself, then
   map the environment variables to their credential names:

   ```nix
   services.logchef.credentialNames = {
     LOGCHEF_AUTH__API_TOKEN_SECRET = "logchef-api-token-secret";
     LOGCHEF_OIDC__CLIENT_SECRET = "logchef-oidc-client-secret";
   };

   systemd.services.logchef.serviceConfig.LoadCredentialEncrypted = [
     "logchef-api-token-secret:/etc/credstore.encrypted/logchef-api-token-secret"
     "logchef-oidc-client-secret:/etc/credstore.encrypted/logchef-oidc-client-secret"
   ];
   ```

3. Set `services.logchef.environmentFile` to a runtime file containing systemd
   environment assignments such as:

   ```text
   LOGCHEF_AUTH__API_TOKEN_SECRET=...
   LOGCHEF_OIDC__CLIENT_SECRET=...
   ```

Do not construct any of these files with `builtins.toFile`, `pkgs.writeText`, or
a quoted Nix string containing the actual secret. sops-nix, agenix, systemd
credentials, or another runtime secret manager can own the paths.

## External dependencies

Logchef handles querying and access control. The module leaves the following
systems to their own operators.

### ClickHouse

ClickHouse is the separate service that stores the logs. Point Logchef at an
existing native endpoint through the UI, or provision it declaratively. The v2
provisioning shape uses `source_type` and a nested `connection` block.
`secret_ref` names a runtime environment variable, keeping the password out of
both the TOML file and the Nix store:

```nix
services.logchef = {
  settings.provisioning = {
    manage_sources = true;
    manage_teams = true;
    prune = false;
    dry_run = false;

    sources = [
      {
        name = "Production Logs";
        source_type = "clickhouse";
        meta_ts_field = "timestamp";
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

For a fully runtime-managed provisioning document, use `provisioningFile`, or
prefer `provisioningCredentialFile` when the document itself contains a
password. Start with upstream's `dry_run = true` before allowing reconciliation
or pruning.

### ZITADEL / OIDC

ZITADEL is a separate identity provider; this flake does not install it. Create
a confidential Web OIDC application in ZITADEL and register the exact callback
`https://logs.example.com/api/v1/auth/callback`. For an issuer at
`https://id.example.com`:

```nix
services.logchef = {
  adminEmails = [ "admin@example.com" ];
  localAuth.enable = false;

  settings.oidc = {
    provider_url = "https://id.example.com";
    auth_url = "https://id.example.com/oauth/v2/authorize";
    token_url = "https://id.example.com/oauth/v2/token";
    client_id = "YOUR_ZITADEL_CLIENT_ID";
    redirect_url = "https://logs.example.com/api/v1/auth/callback";
    scopes = [ "openid" "email" "profile" ];
  };

  credentialFiles = {
    LOGCHEF_AUTH__API_TOKEN_SECRET = "/run/secrets/logchef-api-token-secret";
    LOGCHEF_OIDC__CLIENT_SECRET = "/run/secrets/logchef-oidc-client-secret";
  };
};
```

ZITADEL's public issuer/domain must match `provider_url`. If ZITADEL is behind a
reverse proxy, configure its external domain and TLS mode correctly. Logchef's
callback and browser-facing frontend URL should use the same externally
reachable HTTPS origin.

To bootstrap without OIDC, enable local auth and provide the password only at
runtime:

```nix
services.logchef = {
  localAuth = {
    enable = true;
    adminEmail = "admin@example.com";
  };
  credentialFiles.LOGCHEF_AUTH__LOCAL__ADMIN_PASSWORD =
    "/run/secrets/logchef-local-admin-password";
};
```

## Build and test

```console
nix build .#logchef
nix flake check -L
nix develop
nix fmt
```

The VM smoke test boots NixOS, generates its secret at runtime, starts the
hardened service, fetches the embedded UI, verifies persistent SQLite state,
and checks key systemd sandbox properties. ClickHouse and ZITADEL are not part
of that test: they are independent integrations and are not needed for Logchef
to boot.

## Updating

1. Review the newest non-prerelease server release and its changelog.
2. Run `./update.sh`. It refreshes the release source, Go vendor hash, and the
   fixed-output Bun dependency tree.
3. Check that `package.nix` still follows upstream's Go toolchain and review
   changes to configuration, provisioning, migrations, and the release build.
4. Run `nix flake check -L` on x86_64 Linux. Build
   `.#packages.aarch64-linux.logchef` on native aarch64 Linux or with a remote
   builder as well.
5. Back up SQLite before deploying a release that may contain migrations.

The source build is intentional. An upstream binary would also be a valid Nix
package when its release asset, platform, and hash are pinned, but it should be
an explicit fallback if the source build stops being feasible—not a shortcut
around a failing or incomplete update.

## Automated updates

`.github/workflows/update-logchef.yml` checks the latest stable Logchef server
release once a day and can also be started with **Run workflow**. Because the
upstream repository also publishes CLI releases, the workflow lists releases
and selects an exact `vX.Y.Z` server tag instead of using GitHub's generic
`releases/latest` endpoint. When the upstream tag is newer, it runs `update.sh`,
executes `nix flake check -L`, and opens a branch and pull request with the
refreshed source and dependency hashes. It does not merge or deploy
automatically; review upstream release notes, migrations, and the generated
diff before merging.

## Licensing

Logchef itself is licensed AGPL-3.0-only, reflected in the package metadata.
The Nix packaging and module in this repository are MIT licensed; see
[LICENSE](./LICENSE).
