---
name: maintain-logchef-nix
description: Maintain oddship/logchef-nix by reviewing upstream server releases, diagnosing CI failures, handling update PRs, and preparing validated flake releases with upgrade guidance. Use for repository maintenance, not for deploying a user's Logchef instance.
---

# Maintain logchef-nix

Run from the repository root. This skill holds the maintenance procedure;
scheduling belongs to the invoking agent platform. The daily release updater
remains in `.github/workflows/update-logchef.yml`.

## Establish current state

- Verify the checkout's origin is `oddship/logchef-nix`, inspect local changes,
  and fetch current remote refs. Preserve unrelated work and use an isolated
  branch or checkout when necessary.
- Read applicable `AGENTS.md` instructions. Before external prose, apply the
  maintainer's Humanizer skill when provided. Never use em dashes in outgoing
  communication.
- Inspect recent Actions runs, every open PR, and published and draft releases.
  Match results to the exact commit being reviewed; an old green status does
  not validate a new commit. Distinguish failed checks from workflows awaiting
  GitHub approval.
- Compare the package pin with upstream's latest stable **server** release.
  The upstream repository also releases a CLI: select non-draft,
  non-prerelease tags matching `^v[0-9]+\.[0-9]+\.[0-9]+$` from the paginated
  releases list, as the updater does. Do not rely on `releases/latest`.

## Review and repair

Read the upstream changelog, especially migrations, permissions, API and CLI
changes, configuration, and provisioning. Use these repository references:

- `docs/03-maintenance/01-release-checklist.md` for update and publication steps.
- `docs/02-operations/04-backup-and-upgrade.md` for consumer guidance and rollback.
- `.github/workflows/checks.yml` for the authoritative required CI commands.

Use `./update.sh [VERSION]` when pins need changing. It selects a compatible
stable Go compiler, updates hashes, and synchronizes version references.
Review the downloaded source and lockfiles, not just the generated hashes.

Diagnose CI failures from their logs before changing code. Keep source and
dependency hashes fixed, runtime secrets out of the Nix store, the frontend
embedded, and meaningful tests enabled. The shutdown goroutine-count test
runs in a separate Go process intentionally; preserve its coverage when
changing test execution.

The updater recreates its versioned branch from the triggering revision and
force-pushes it with a lease. Manual fixes on an open automation branch can
therefore be overwritten on a later run. Check branch history before editing;
keep work on a separate maintenance branch when it must survive regeneration,
and incorporate prerequisite fixes into the base before rerunning the updater.

## Validate the reviewed revision

For substantive package, module, or workflow changes, run the repository's
required checks locally or verify successful CI on that exact revision:

```sh
bash tests/check-version-docs.sh
python3 -m unittest discover -s tests -p 'test_*.py'
nix develop --command bash tests/check-docs.sh
nix fmt -- --ci
nix flake check --all-systems --no-build
nix build .#checks.x86_64-linux.package \
  .#checks.x86_64-linux.moduleEvaluation \
  .#checks.x86_64-linux.vm -L --no-link
nix run nixpkgs#actionlint
```

For instructions-only changes, validate the skill's frontmatter, references,
and behavior against the actual workflows. Follow repository-required CI
before merging. Do not repeat expensive checks on unchanged commits without
a failure or unresolved concern.

All-system evaluation does not prove a native aarch64 build. Follow the
release checklist's architecture requirements and record any validation gap.
The VM smoke test uses a fresh database; it does not validate migrations of
an existing database, custom scripts, or alert behavior.

## Handle PRs and releases

Act within the invoking task's authorization. For an authorized scheduled
maintenance run, push conventional commits and open or update PRs as needed;
merge routine release or maintenance PRs only after review and all required
checks pass. Match the reviewed head when merging so a concurrent update is
not merged without review.

If an update introduces database migrations, permission changes, breaking
integrations, or another disruptive change, prepare the concrete update and
upgrade documentation, keep the PR as a draft, and request the maintainer's
decision before merging or publishing. Respect any approval already given
for that specific update. CI success alone does not establish upgrade readiness.

Close automated update PRs only when a merged release or a newer reviewed
update supersedes them; explain which release or PR replaces them. Do not
discard distinct fixes while cleaning up older updates.

For approved releases, add version-specific migration notes to the upgrade
guide and link them from the README. Prepare GitHub release notes covering
upgrade impact, backup and rollback requirements, pinning, upstream notes,
and validation. Publish only when authorized, after the intended commit is
merged and its required checks pass. Target its exact SHA, link docs through
the release tag, and remove draft-only publication instructions. Preserve
published tags, including older versions consumers may still pin.

After release work, verify tag targets and published notes, documentation
deployment when affected, and a successful updater run on `master` when
relevant. Confirm any remaining PRs are intentional.

## Report

Give a short result with links to changes, releases, and workflow evidence.
Identify remaining decisions or blockers and distinguish checked behavior
from assumptions. If everything is healthy, say so without unnecessary edits.
Maintaining this repository does not authorize deploying a host, deprecating
the flake, or contacting upstream; those require a separate user request.
