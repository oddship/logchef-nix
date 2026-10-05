#!/usr/bin/env python3
"""Prepare a stable Go toolchain before nix-update builds dependency hashes."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.request


def version_tuple(value):
    match = re.fullmatch(r"(\d+)\.(\d+)(?:\.(\d+))?", value)
    if not match:
        raise ValueError(f"Not a stable version: {value}")
    return tuple(int(part or 0) for part in match.groups())


def required_go(go_mod):
    match = re.search(r"^go\s+(\S+)\s*$", go_mod, re.MULTILINE)
    if not match:
        raise ValueError("Upstream go.mod has no Go version directive")
    required = version_tuple(match[1])
    toolchain = re.search(r"^toolchain\s+go(\S+)\s*$", go_mod, re.MULTILINE)
    if toolchain:
        required = max(required, version_tuple(toolchain[1]))
    return required


def fetch(url):
    headers = {"User-Agent": "logchef-nix-updater"}
    token = os.environ.get("GH_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode()


def latest_server_release():
    releases = []
    page = 1
    while True:
        batch = json.loads(fetch(
            f"https://api.github.com/repos/mr-karan/logchef/releases?per_page=100&page={page}"
        ))
        releases.extend(item for item in batch if not item["draft"]
                        and not item["prerelease"]
                        and re.fullmatch(r"v\d+\.\d+\.\d+", item["tag_name"]))
        if len(batch) < 100:
            break
        page += 1
    if not releases:
        raise ValueError("No stable Logchef server release found")
    return max(releases, key=lambda item: item["published_at"])["tag_name"][1:]


def compiler_versions(repo, attributes):
    # Check the compiler on every system supported by the flake.
    expression = '''let
      f = builtins.getFlake (toString ./.);
      attrs = builtins.fromJSON %s;
      systems = builtins.attrNames f.packages;
    in builtins.listToAttrs (map (name: {
      inherit name;
      value = map (system:
        let p = f.inputs.nixpkgs.legacyPackages.${system};
        in if builtins.hasAttr name p then p.${name}.version else null
      ) systems;
    }) attrs)''' % json.dumps(json.dumps(attributes))
    result = subprocess.run(
        ["nix", "eval", "--impure", "--json", "--expr", expression],
        cwd=repo, check=True, capture_output=True, text=True,
    )
    return json.loads(result.stdout)


def compatible(versions, requirement):
    try:
        return bool(versions) and all(version_tuple(v) >= requirement for v in versions)
    except (ValueError, TypeError):
        return False


def prepare_toolchain(repo, go_mod):
    requirement = required_go(go_mod)
    path = repo / "go-toolchain.nix"
    current = json.loads(path.read_text())
    target = f"go_{requirement[0]}_{requirement[1]}"
    candidates = list(dict.fromkeys([current, target]))
    for attempt in range(2):
        available = compiler_versions(repo, candidates)
        for attribute in candidates:
            if compatible(available[attribute], requirement):
                if attribute != current:
                    path.write_text(json.dumps(attribute) + "\n")
                print(f"Using {attribute} for upstream Go {'.'.join(map(str, requirement))}",
                      file=sys.stderr)
                return attribute
        if attempt == 0:
            print("Pinned nixpkgs lacks a compatible stable Go compiler; refreshing it.",
                  file=sys.stderr)
            subprocess.run(["nix", "flake", "update", "nixpkgs"], cwd=repo, check=True,
                           stdout=sys.stderr)
    raise ValueError(
        f"No stable compiler meets upstream Go {'.'.join(map(str, requirement))} "
        f"on every supported system, even after refreshing nixpkgs: {available}. "
        "Choose a nixpkgs input providing this compiler before retrying. "
        "Release version and dependency hashes have not been changed."
    )


def main():
    repo = Path(__file__).resolve().parent.parent
    version = (sys.argv[1] if len(sys.argv) > 1 else "") or latest_server_release()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError(f"Invalid stable release version: {version}")
    go_mod = fetch(f"https://raw.githubusercontent.com/mr-karan/logchef/v{version}/go.mod")
    prepare_toolchain(repo, go_mod)
    print(version)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release preflight failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
