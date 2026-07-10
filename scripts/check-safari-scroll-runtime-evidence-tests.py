from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Callable


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
FIXTURE_ROOT = REPOSITORY_ROOT / "docs" / "fixtures" / "safari-scroll-probe"
CONTRACT_PATH = FIXTURE_ROOT / "contract.json"
CONTRACT_CHECKER = REPOSITORY_ROOT / "scripts" / "check-safari-scroll-probe-contract.py"
RUNTIME_EVALUATOR = REPOSITORY_ROOT / "scripts" / "check-safari-scroll-runtime-evidence.py"
SAFARI_PROCESS_ID = 4242


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def top_level_state() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "scenario": "top-level",
        "ready": True,
        "outer": {
            "x": 0,
            "y": 0,
            "wheel": {"count": 0, "target": "none"},
        },
        "inner": None,
        "frame": None,
    }


def nested_state() -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "scenario": "nested",
        "ready": True,
        "outer": {
            "x": 0,
            "y": 0,
            "wheel": {"count": 0, "target": "none"},
        },
        "inner": {
            "x": 0,
            "y": 0,
            "wheel": {"count": 0, "target": "none"},
        },
        "frame": {
            "x": 0,
            "y": 0,
            "wheel": {"count": 0, "target": "none"},
        },
    }


def expected_snapshots(assertion_id: str) -> dict[str, dict[str, Any]]:
    before = top_level_state() if assertion_id == "top-level" else nested_state()
    after = copy.deepcopy(before)
    if assertion_id == "generic-native-wheel":
        after["inner"]["y"] = 14
        after["inner"]["wheel"]["count"] = 1
        after["inner"]["wheel"]["target"] = "generic-1"
    elif assertion_id == "vertical-only-frame":
        after["frame"]["y"] = 367
    elif assertion_id == "long-article":
        after["outer"]["y"] = 674
    elif assertion_id == "top-level":
        after["outer"]["x"] = 1358
        after["outer"]["y"] = 608
    elif assertion_id == "frame-edge":
        at_end = copy.deepcopy(before)
        at_end["frame"]["y"] = 1468
        return {
            "before": before,
            "atEnd": at_end,
            "after": copy.deepcopy(at_end),
        }
    return {"before": before, "after": after}


def window_stack(owner_process_id: int = SAFARI_PROCESS_ID) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "wallClockUnixSeconds": 1_800_000_000,
        "systemUptimeSeconds": 1234.5,
        "pointer": {"x": 500.0, "y": 500.0},
        "frontmostApplication": {
            "processID": SAFARI_PROCESS_ID,
            "bundleIdentifier": "com.apple.Safari",
            "localizedName": "Safari",
        },
        "windows": [
            {
                "stackIndex": 0,
                "ownerName": "Safari" if owner_process_id == SAFARI_PROCESS_ID else "ChatGPT",
                "ownerProcessID": owner_process_id,
                "windowNumber": 88,
                "bounds": {"x": 0.0, "y": 0.0, "width": 1000.0, "height": 1000.0},
                "alpha": 1.0,
            },
            {
                "stackIndex": 3,
                "ownerName": "Safari",
                "ownerProcessID": SAFARI_PROCESS_ID,
                "windowNumber": 89,
                "bounds": {"x": 0.0, "y": 0.0, "width": 1000.0, "height": 1000.0},
                "alpha": 1.0,
            },
        ],
    }


def build_positive_artifact(
    root: Path,
) -> tuple[Path, dict[tuple[str, str], Path], dict[str, Any]]:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    run_directories: dict[tuple[str, str], Path] = {}
    runs: list[dict[str, object]] = []
    for assertion in contract["assertions"]:
        assertion_id = assertion["id"]
        for operation in assertion["operations"]:
            operation_id = operation["id"]
            run_directory = root / "runs" / assertion_id / operation_id
            run_directories[(assertion_id, operation_id)] = run_directory
            snapshots = expected_snapshots(assertion_id)
            snapshot_paths: dict[str, str] = {}
            for name, snapshot in snapshots.items():
                relative_path = Path("runs") / assertion_id / operation_id / f"{name}.json"
                write_json(root / relative_path, snapshot)
                snapshot_paths[name] = str(relative_path)

            pointer_relative = Path("runs") / assertion_id / operation_id / "pointer-setup.json"
            write_json(
                root / pointer_relative,
                {
                    "requested": {"x": 500.0, "y": 500.0},
                    "actual": {"x": 500.0, "y": 500.0},
                    "distance": 0.0,
                },
            )
            exit_codes: dict[str, str] = {}
            for transition in assertion["transitions"]:
                exit_name = transition["exitCode"]
                exit_relative = Path("runs") / assertion_id / operation_id / f"{exit_name}.exit-code.txt"
                (root / exit_relative).write_text("0\n", encoding="utf-8")
                exit_codes[exit_name] = str(exit_relative)

            artifacts: dict[str, object] = {
                "pointerSetup": str(pointer_relative),
                "snapshots": snapshot_paths,
                "exitCodes": exit_codes,
            }
            if operation["routing"]["type"] == "pointer-window-owner":
                owner_relative = Path("runs") / assertion_id / operation_id / "window-owner.json"
                write_json(root / owner_relative, window_stack())
                artifacts["windowOwner"] = str(owner_relative)

            runs.append(
                {
                    "assertionId": assertion_id,
                    "operationId": operation_id,
                    "fixture": assertion["fixture"],
                    "pointerElementId": assertion["pointerElementId"],
                    "operation": copy.deepcopy(operation),
                    "targetProcessId": (
                        SAFARI_PROCESS_ID if operation["pidOverride"] is True else None
                    ),
                    "artifacts": artifacts,
                }
            )

    manifest = {
        "schemaVersion": contract["runtimeEvidence"]["manifestSchemaVersion"],
        "contractSchemaVersion": contract["schemaVersion"],
        "probeSchemaVersion": contract["probeSchemaVersion"],
        "safari": {
            "bundleIdentifier": "com.apple.Safari",
            "processId": SAFARI_PROCESS_ID,
        },
        "runs": runs,
    }
    manifest_path = root / "manifest.json"
    write_json(manifest_path, manifest)
    return manifest_path, run_directories, manifest


def run_evaluator(root: Path, manifest_path: Path) -> tuple[subprocess.CompletedProcess[str], dict[str, Any]]:
    completed = subprocess.run(
        [
            sys.executable,
            str(RUNTIME_EVALUATOR),
            str(root),
            "--contract",
            str(CONTRACT_PATH),
            "--manifest",
            str(manifest_path),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    try:
        report = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise AssertionError(
            f"evaluatorのstdoutがJSONではありません: {error}\n"
            f"stdout={completed.stdout}\nstderr={completed.stderr}"
        ) from error
    return completed, report


class SafariScrollRuntimeEvidenceTests(unittest.TestCase):
    def with_artifact(
        self,
        mutation: Callable[[Path, Path, dict[tuple[str, str], Path], dict[str, Any]], None] | None = None,
    ) -> tuple[subprocess.CompletedProcess[str], dict[str, Any]]:
        temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(temporary_directory.cleanup)
        root = Path(temporary_directory.name)
        manifest_path, run_directories, manifest = build_positive_artifact(root)
        if mutation is not None:
            mutation(root, manifest_path, run_directories, manifest)
        return run_evaluator(root, manifest_path)

    def assert_failed(
        self,
        mutation: Callable[[Path, Path, dict[tuple[str, str], Path], dict[str, Any]], None],
    ) -> dict[str, Any]:
        completed, report = self.with_artifact(mutation)
        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        self.assertEqual(report["status"], "fail")
        self.assertGreater(report["failureCount"], 0)
        return report

    def test_positive_artifact_passes(self) -> None:
        completed, report = self.with_artifact()
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["failureCount"], 0)
        self.assertEqual(report["blockedCount"], 0)
        self.assertEqual(len(report["runs"]), 12)

    def test_outer_fallback_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("vertical-only-frame", "sync-pid")] / "after.json"
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            snapshot["outer"]["y"] = 1
            write_json(path, snapshot)

        self.assert_failed(mutate)

    def test_wheel_leak_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("long-article", "async-pid")] / "after.json"
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            snapshot["outer"]["wheel"]["count"] = 1
            snapshot["outer"]["wheel"]["target"] = "article"
            write_json(path, snapshot)

        self.assert_failed(mutate)

    def test_ready_false_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("generic-generated-fail-closed", "sync-pid")] / "before.json"
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            snapshot["ready"] = False
            write_json(path, snapshot)

        self.assert_failed(mutate)

    def test_frame_edge_change_after_end_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("frame-edge", "sync-pid")] / "after.json"
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            snapshot["frame"]["y"] += 1
            write_json(path, snapshot)

        self.assert_failed(mutate)

    def test_normal_routing_host_overlay_is_blocked(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("top-level", "async-normal")] / "window-owner.json"
            write_json(path, window_stack(owner_process_id=9999))

        completed, report = self.with_artifact(mutate)
        self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["failureCount"], 0)
        self.assertEqual(report["blockedCount"], 1)

    def test_normal_routing_non_safari_frontmost_is_blocked(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("top-level", "async-normal")] / "window-owner.json"
            document = json.loads(path.read_text(encoding="utf-8"))
            document["frontmostApplication"]["bundleIdentifier"] = "com.openai.codex"
            document["frontmostApplication"]["localizedName"] = "Codex"
            write_json(path, document)

        completed, report = self.with_artifact(mutate)
        self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["failureCount"], 0)
        self.assertEqual(report["blockedCount"], 1)

    def test_window_stack_pointer_mismatch_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("top-level", "async-normal")] / "window-owner.json"
            document = json.loads(path.read_text(encoding="utf-8"))
            document["pointer"]["x"] = 700
            write_json(path, document)

        self.assert_failed(mutate)

    def test_nonpositive_system_uptime_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("top-level", "async-normal")] / "window-owner.json"
            document = json.loads(path.read_text(encoding="utf-8"))
            document["systemUptimeSeconds"] = 0
            write_json(path, document)

        self.assert_failed(mutate)

    def test_pid_override_metadata_mismatch_fails(self) -> None:
        def mutate(
            _root: Path,
            manifest_path: Path,
            _run_directories: dict[tuple[str, str], Path],
            manifest: dict[str, Any],
        ) -> None:
            run = next(
                entry
                for entry in manifest["runs"]
                if entry["assertionId"] == "top-level"
                and entry["operationId"] == "async-normal"
            )
            run["operation"]["pidOverride"] = True
            run["targetProcessId"] = SAFARI_PROCESS_ID
            write_json(manifest_path, manifest)

        self.assert_failed(mutate)

    def test_frame_edge_sequence_metadata_mismatch_fails(self) -> None:
        def mutate(
            _root: Path,
            manifest_path: Path,
            _run_directories: dict[tuple[str, str], Path],
            manifest: dict[str, Any],
        ) -> None:
            run = next(
                entry
                for entry in manifest["runs"]
                if entry["assertionId"] == "frame-edge"
                and entry["operationId"] == "sync-pid"
            )
            run["operation"]["sequence"][0]["parameters"]["y"] = 800
            write_json(manifest_path, manifest)

        self.assert_failed(mutate)

    def test_contract_checker_rejects_native_pages_drift(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
            native_assertion = next(
                assertion
                for assertion in contract["assertions"]
                if assertion["id"] == "generic-native-wheel"
            )
            native_assertion["operations"][0]["parameters"]["pages"] = 1
            temporary_contract = Path(temporary_directory) / "contract.json"
            write_json(temporary_contract, contract)
            completed = subprocess.run(
                [
                    sys.executable,
                    str(CONTRACT_CHECKER),
                    "--contract",
                    str(temporary_contract),
                    "--fixture-root",
                    str(FIXTURE_ROOT),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 1)
            self.assertIn("operation metadata", completed.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
