import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "prepare_update", Path(__file__).resolve().parents[1] / "scripts/prepare-update.py"
)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class ToolchainTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.pin = self.repo / "go-toolchain.nix"
        self.pin.write_text('"go_1_27"\n')

    def prepare(self, snapshots, go_mod):
        with patch.object(updater, "compiler_versions", side_effect=snapshots), \
                patch.object(updater.subprocess, "run") as refresh:
            selected = updater.prepare_toolchain(self.repo, go_mod)
            return selected, refresh

    def test_existing_compiler_is_kept(self):
        selected, refresh = self.prepare(
            [{"go_1_27": ["1.27.1", "1.27.1"]}], "go 1.27.0\n"
        )
        self.assertEqual(selected, "go_1_27")
        refresh.assert_not_called()

    def test_new_minor_is_selected_for_both_systems(self):
        selected, refresh = self.prepare(
            [{"go_1_27": ["1.27.1"] * 2, "go_1_28": ["1.28.0"] * 2}],
            "go 1.28.0\n",
        )
        self.assertEqual(selected, "go_1_28")
        self.assertEqual(json.loads(self.pin.read_text()), selected)
        refresh.assert_not_called()

    def test_release_candidate_triggers_refresh(self):
        selected, refresh = self.prepare([
            {"go_1_27": ["1.27.1"] * 2, "go_1_28": ["1.28rc3"] * 2},
            {"go_1_27": ["1.27.2"] * 2, "go_1_28": ["1.28.1"] * 2},
        ], "go 1.28.0\n")
        self.assertEqual(selected, "go_1_28")
        refresh.assert_called_once()
        self.assertEqual(refresh.call_args.args[0], ["nix", "flake", "update", "nixpkgs"])

    def test_patch_requirement_triggers_refresh(self):
        selected, refresh = self.prepare([
            {"go_1_27": ["1.27.1"] * 2}, {"go_1_27": ["1.27.3"] * 2},
        ], "go 1.27.2\n")
        self.assertEqual(selected, "go_1_27")
        refresh.assert_called_once()

    def test_missing_architecture_fails_without_changing_selection(self):
        snapshot = {"go_1_27": ["1.27.1"] * 2, "go_1_28": ["1.28.0", None]}
        with self.assertRaisesRegex(ValueError, "Release version and dependency hashes"):
            self.prepare([snapshot, snapshot], "go 1.28.0\n")
        self.assertEqual(self.pin.read_text(), '"go_1_27"\n')

    def test_toolchain_directive_is_respected(self):
        self.assertEqual(updater.required_go("go 1.27.0\ntoolchain go1.28.2\n"), (1, 28, 2))

    def test_invalid_go_mod_fails_before_evaluation(self):
        with patch.object(updater, "compiler_versions") as evaluate:
            with self.assertRaises(ValueError):
                updater.prepare_toolchain(self.repo, "module example.com/server\n")
            evaluate.assert_not_called()


class ReleaseSelectionTests(unittest.TestCase):
    def test_cli_and_prerelease_tags_are_excluded(self):
        releases = [
            {"tag_name": tag, "published_at": date, "draft": False, "prerelease": pre}
            for tag, date, pre in [
                ("v2.2.0", "2026-10-01", False),
                ("cli-v9.0.0", "2026-10-05", False),
                ("v2.3.0", "2026-10-04", True),
            ]
        ]
        with patch.object(updater, "fetch", return_value=json.dumps(releases)):
            self.assertEqual(updater.latest_server_release(), "2.2.0")


class UpdateScriptTests(unittest.TestCase):
    """Exercise the real shell entrypoint with stubbed network/build tools."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        source = Path(__file__).resolve().parents[1]
        for name in ["update.sh", "package.nix", "README.md"]:
            shutil.copyfile(source / name, self.repo / name)
        for name in ["docs", "tests"]:
            shutil.copytree(source / name, self.repo / name)
        self.bin = self.repo / "bin"
        self.bin.mkdir()
        self.env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}"}
        self.calls = self.repo / "hash-calls"
        self.stub("nix-update", 'printf "%s\\n" "$*" >> hash-calls\n')

    def stub(self, name, script):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + script)
        path.chmod(0o755)

    def run_update(self, *args):
        return subprocess.run(["bash", "update.sh", *args], cwd=self.repo,
                              env=self.env, capture_output=True, text=True)

    def test_failed_preflight_never_refreshes_hashes_or_docs(self):
        self.stub("python3", "echo 'no compatible stable Go compiler' >&2\nexit 1\n")
        before = {path: path.read_bytes() for path in self.repo.rglob("*")
                  if path.is_file()}
        result = self.run_update("2.2.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no compatible stable Go compiler", result.stderr)
        self.assertFalse(self.calls.exists())
        for path, content in before.items():
            self.assertEqual(path.read_bytes(), content, str(path))

    def test_both_hash_updates_use_the_release_resolved_by_preflight(self):
        version = next(line.split('"')[1] for line in
                       (self.repo / "package.nix").read_text().splitlines()
                       if line.strip().startswith("version ="))
        self.stub("python3", f"echo {version}\n")
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), [
            f"--flake --version={version} logchef",
            f"--flake --version={version} logchef --subpackage nodeModules",
        ])

    def test_invalid_release_never_runs_preflight_or_hash_updates(self):
        self.stub("python3", "touch unexpected-preflight\n")
        result = self.run_update("cli-v0.2.2")
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.repo / "unexpected-preflight").exists())
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main()
