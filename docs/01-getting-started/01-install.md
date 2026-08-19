# Install

## Build the package

From a checkout:

```console
nix build .#logchef
./result/bin/logchef --help
```

The package is built from Logchef v2.0.2. The Vite frontend is compiled from the upstream lockfile and embedded in a statically linked Go server. There is no OCI image or runtime container dependency.

The flake publishes `packages.default` and `packages.logchef` for `x86_64-linux` and `aarch64-linux`.

## Add the flake to NixOS

Import `nixosModules.default` and configure the service:

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
            credentialFiles.LOGCHEF_AUTH__API_TOKEN_SECRET =
              "/run/secrets/logchef-api-token-secret";
          };
          system.stateVersion = "26.05";
        }
      ];
    };
  };
}
```

The service listens on `127.0.0.1:8125` by default. Keep that boundary when a reverse proxy is in front, or set `openFirewall = true` only when the host should accept direct connections.

## Local development

The dev shell includes Bun, Go 1.26, `nix-update`, `nixfmt-tree`, and `just`:

```console
nix develop
nix fmt
nix flake check -L
```
