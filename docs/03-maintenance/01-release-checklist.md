# Release checklist

This repository tracks a released Logchef source version rather than a moving branch. A release update should leave a reviewer with a source URL, fixed hashes, and a passing test result.

## Update

1. Read the upstream release notes and inspect changes to configuration, migrations, provisioning, and the build workflow.
2. Run `./update.sh` to refresh the source, Go vendor, fixed-output Bun dependency tree, and user-facing Logchef version references.
3. Confirm the Go toolchain in `package.nix` still matches upstream.
4. Review the generated diff. Do not accept a hash-only change without checking the downloaded source and lockfiles.

The scheduled GitHub Actions workflow performs the same update automatically.
It checks the upstream stable-release API once per day, opens a versioned PR
when the tag changes, and leaves the merge decision with a maintainer. Use
**Run workflow** for an immediate check.

## Verify

```console
nix fmt
nix flake check -L
nix build .#logchef
```

The checks cover the package, frontend and Go tests, module evaluation, and an x86_64 NixOS VM. Build the aarch64 package on native aarch64 hardware or with a trusted remote builder before publishing a release.

The VM test starts the service with a secret generated at runtime, fetches the embedded UI, confirms that SQLite state is created, and checks several systemd sandbox properties. It deliberately does not start ClickHouse or ZITADEL.

## Publish safely

Back up `/var/lib/logchef/logchef.db` before deploying a release that may contain migrations. Keep secrets in a runtime secret manager, and verify that no generated TOML, environment file, or command line contains them.

The package is source-built and statically linked. A pinned upstream release binary would be an acceptable fallback if source builds stop being feasible, but it should carry an explicit platform-specific hash and a documented provenance decision.
