---
title: Install
description: Build Logchef or deploy a working local-auth instance with the logchef-nix NixOS module.
---

# Install

## Build the package

From a checkout:

```console
nix build .#logchef
./result/bin/logchef --help
```

The package is built from Logchef v2.1.0. The Vite frontend is compiled from the upstream lockfile and embedded in a statically linked Go server. There is no OCI image or runtime container dependency.

The flake publishes `packages.default` and `packages.logchef` for `x86_64-linux` and `aarch64-linux`.

## Deploy a first instance

Create two runtime secrets on the target host. The API-token secret protects
stored API tokens and the local password must be at least 10 characters:

```console
sudo install -d -m 0700 /var/lib/logchef-secrets
sudo install -m 0600 /dev/null /var/lib/logchef-secrets/api-token-secret
sudo install -m 0600 /dev/null /var/lib/logchef-secrets/admin-password
openssl rand -hex 32 | sudo tee /var/lib/logchef-secrets/api-token-secret >/dev/null
openssl rand -base64 24 | sudo tee /var/lib/logchef-secrets/admin-password >/dev/null
```

Import `nixosModules.default` and enable local authentication for the first
login:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    logchef = {
      url = "github:oddship/logchef-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, logchef, ... }: {
    nixosConfigurations.logs = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        logchef.nixosModules.default
        {
          services.logchef = {
            enable = true;
            adminEmails = [ "admin@example.com" ];
            localAuth = {
              enable = true;
              adminEmail = "admin@example.com";
            };
            settings.server.secure_cookie = false;
            credentialFiles = {
              LOGCHEF_AUTH__API_TOKEN_SECRET =
                "/var/lib/logchef-secrets/api-token-secret";
              LOGCHEF_AUTH__LOCAL__ADMIN_PASSWORD =
                "/var/lib/logchef-secrets/admin-password";
            };
          };
          system.stateVersion = "26.05";
        }
      ];
    };
  };
}
```

Apply the configuration and verify the service before adding an external
datasource:

```console
sudo nixos-rebuild switch --flake .#logs
systemctl status logchef --no-pager
journalctl -u logchef -b --no-pager -n 50
curl --fail http://127.0.0.1:8125/
```

Open `http://127.0.0.1:8125` through a local tunnel and sign in as
`admin@example.com` with the password stored in
`/var/lib/logchef-secrets/admin-password`. Replace the plain files with
sops-nix, agenix, or encrypted systemd credentials for a maintained host.

The service listens on `127.0.0.1:8125` by default. `secure_cookie = false` is
required only for this local HTTP bootstrap. Before publishing the service,
follow [[Reverse proxy and TLS]], use HTTPS, and set it back to `true`.

If you prefer SSO, configure the complete OIDC block in [[External integrations]]
instead of enabling local authentication. Logchef refuses to start unless local
authentication is enabled or the required OIDC endpoints and client ID are
present.

## Local development

The dev shell includes Bun, the package's selected Go compiler, Python, `nix-update`, `nixfmt-tree`, and `just`:

```console
nix develop
nix fmt
nix flake check -L
```
