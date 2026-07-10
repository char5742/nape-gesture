from __future__ import annotations

import copy
import hashlib
import json
import os
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
CANDIDATE_COMMIT = "a" * 40
APP_EXECUTABLE_RELATIVE_PATH = (
    Path("candidate") / "NapeGesture.app" / "Contents" / "MacOS" / "nape-gesture"
)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def artifact_reference(root: Path, relative_path: Path) -> dict[str, str]:
    return {
        "path": str(relative_path),
        "sha256": sha256_file(root / relative_path),
    }


def refresh_artifact_hashes(root: Path, value: object) -> None:
    if isinstance(value, dict) and set(value) == {"path", "sha256"}:
        value["sha256"] = sha256_file(root / value["path"])
        return
    if isinstance(value, dict):
        for child in value.values():
            refresh_artifact_hashes(root, child)
    elif isinstance(value, list):
        for child in value:
            refresh_artifact_hashes(root, child)


def find_run(manifest: dict[str, Any], assertion_id: str, operation_id: str) -> dict[str, Any]:
    return next(
        entry
        for entry in manifest["runs"]
        if entry["assertionId"] == assertion_id and entry["operationId"] == operation_id
    )


def generated_scroll_argv(
    command: dict[str, Any],
    delivery: str,
    pid_override: bool,
    app_executable: Path,
) -> list[str]:
    parameters = command["parameters"]
    argv = [
        str(app_executable),
        "generate-scroll",
        "--x",
        str(parameters["x"]),
        "--y",
        str(parameters["y"]),
        "--steps",
        str(command["steps"]),
        "--mode",
        str(parameters["mode"]),
        "--ax-delivery",
        delivery,
    ]
    if pid_override:
        argv.extend(["--post-to-pid", str(SAFARI_PROCESS_ID)])
    return argv


def invocation(operation: dict[str, Any], app_executable: Path) -> dict[str, object]:
    if operation["kind"] == "native-wheel":
        return {
            "kind": "computer-use",
            "commands": [
                {
                    "id": "operation",
                    "action": "scroll",
                    "direction": operation["parameters"]["direction"],
                    "pages": operation["parameters"]["pages"],
                }
            ],
        }
    commands = operation.get("sequence")
    if not isinstance(commands, list):
        commands = [
            {
                "id": "operation",
                "parameters": operation["parameters"],
                "steps": operation["steps"],
            }
        ]
    return {
        "kind": "cli",
        "commands": [
            {
                "id": command["id"],
                "argv": generated_scroll_argv(
                    command,
                    operation["delivery"],
                    operation["pidOverride"],
                    app_executable,
                ),
            }
            for command in commands
        ],
    }


def top_level_state() -> dict[str, Any]:
    return {
        "schemaVersion": 2,
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
        "schemaVersion": 2,
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
            "maxY": 1468,
            "atEnd": False,
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
        at_end["frame"]["atEnd"] = True
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
    app_executable = (root / APP_EXECUTABLE_RELATIVE_PATH).resolve()
    app_executable.parent.mkdir(parents=True, exist_ok=True)
    app_executable.write_bytes(b"synthetic nape gesture executable\n")
    run_directories: dict[tuple[str, str], Path] = {}
    runs: list[dict[str, object]] = []
    for assertion in contract["assertions"]:
        assertion_id = assertion["id"]
        for operation in assertion["operations"]:
            operation_id = operation["id"]
            run_directory = root / "runs" / assertion_id / operation_id
            run_directories[(assertion_id, operation_id)] = run_directory
            snapshots = expected_snapshots(assertion_id)
            snapshot_paths: dict[str, dict[str, str]] = {}
            for name, snapshot in snapshots.items():
                relative_path = Path("runs") / assertion_id / operation_id / f"{name}.json"
                write_json(root / relative_path, snapshot)
                snapshot_paths[name] = artifact_reference(root, relative_path)

            pointer_relative = Path("runs") / assertion_id / operation_id / "pointer-setup.json"
            write_json(
                root / pointer_relative,
                {
                    "requested": {"x": 500.0, "y": 500.0},
                    "actual": {"x": 500.0, "y": 500.0},
                    "distance": 0.0,
                },
            )
            exit_codes: dict[str, dict[str, str]] = {}
            for transition in assertion["transitions"]:
                exit_name = transition["exitCode"]
                exit_relative = Path("runs") / assertion_id / operation_id / f"{exit_name}.exit-code.txt"
                (root / exit_relative).write_text("0\n", encoding="utf-8")
                exit_codes[exit_name] = artifact_reference(root, exit_relative)

            artifacts: dict[str, object] = {
                "pointerSetup": artifact_reference(root, pointer_relative),
                "snapshots": snapshot_paths,
                "exitCodes": exit_codes,
            }
            if operation["routing"]["type"] == "pointer-window-owner":
                owner_relative = Path("runs") / assertion_id / operation_id / "window-owner.json"
                write_json(root / owner_relative, window_stack())
                artifacts["windowOwner"] = artifact_reference(root, owner_relative)

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
                    "executionStatus": "executed",
                    "invocation": invocation(operation, app_executable),
                    "artifacts": artifacts,
                }
            )

    manifest = {
        "schemaVersion": contract["runtimeEvidence"]["manifestSchemaVersion"],
        "contractSchemaVersion": contract["schemaVersion"],
        "probeSchemaVersion": contract["probeSchemaVersion"],
        "contractSha256": sha256_file(CONTRACT_PATH),
        "candidate": {
            "commit": CANDIDATE_COMMIT,
            "app": {
                "bundleIdentifier": "dev.char5742.nape-gesture",
                "executableSha256": sha256_file(app_executable),
            },
        },
        "safari": {
            "bundleIdentifier": "com.apple.Safari",
            "processId": SAFARI_PROCESS_ID,
        },
        "runs": runs,
    }
    manifest_path = root / "safari-scroll-runtime-manifest.json"
    write_json(manifest_path, manifest)
    return manifest_path, run_directories, manifest


def run_evaluator(
    root: Path,
    manifest_path: Path,
    *,
    contract_path: Path = CONTRACT_PATH,
    explicit_manifest: bool = True,
    expected_commit: str = CANDIDATE_COMMIT,
    app_executable: Path | None = None,
) -> tuple[subprocess.CompletedProcess[str], dict[str, Any]]:
    resolved_app_executable = (
        app_executable
        if app_executable is not None
        else root / APP_EXECUTABLE_RELATIVE_PATH
    )
    arguments = [
        sys.executable,
        str(RUNTIME_EVALUATOR),
        str(root),
        "--contract",
        str(contract_path),
        "--expected-commit",
        expected_commit,
        "--app-executable",
        str(resolved_app_executable),
    ]
    if explicit_manifest:
        arguments.extend(["--manifest", str(manifest_path)])
    completed = subprocess.run(
        arguments,
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
        *,
        refresh_hashes: bool = True,
    ) -> tuple[subprocess.CompletedProcess[str], dict[str, Any]]:
        temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(temporary_directory.cleanup)
        root = Path(temporary_directory.name)
        manifest_path, run_directories, manifest = build_positive_artifact(root)
        if mutation is not None:
            mutation(root, manifest_path, run_directories, manifest)
            if refresh_hashes:
                refresh_artifact_hashes(root, manifest.get("runs"))
            write_json(manifest_path, manifest)
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

    def test_frame_edge_not_at_end_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("frame-edge", "sync-pid")] / "atEnd.json"
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            snapshot["frame"]["y"] = 1
            write_json(path, snapshot)

        self.assert_failed(mutate)

    def test_false_does_not_equal_numeric_zero(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("vertical-only-frame", "sync-pid")] / "before.json"
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            snapshot["frame"]["x"] = False
            write_json(path, snapshot)

        self.assert_failed(mutate)

    def test_normal_routing_host_overlay_is_blocked(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("top-level", "async-normal")] / "window-owner.json"
            write_json(path, window_stack(owner_process_id=9999))
            run = find_run(manifest, "top-level", "async-normal")
            run["executionStatus"] = "precondition-blocked"
            run["invocation"] = None
            run["artifacts"] = {
                "pointerSetup": run["artifacts"]["pointerSetup"],
                "windowOwner": run["artifacts"]["windowOwner"],
            }

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
            manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("top-level", "async-normal")] / "window-owner.json"
            document = json.loads(path.read_text(encoding="utf-8"))
            document["frontmostApplication"]["bundleIdentifier"] = "com.openai.codex"
            document["frontmostApplication"]["localizedName"] = "Codex"
            write_json(path, document)
            run = find_run(manifest, "top-level", "async-normal")
            run["executionStatus"] = "precondition-blocked"
            run["invocation"] = None
            run["artifacts"] = {
                "pointerSetup": run["artifacts"]["pointerSetup"],
                "windowOwner": run["artifacts"]["windowOwner"],
            }

        completed, report = self.with_artifact(mutate)
        self.assertEqual(completed.returncode, 2, completed.stdout + completed.stderr)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["failureCount"], 0)
        self.assertEqual(report["blockedCount"], 1)

    def test_host_overlay_marked_executed_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("top-level", "async-normal")] / "window-owner.json"
            write_json(path, window_stack(owner_process_id=9999))

        self.assert_failed(mutate)

    def test_frontmost_safari_pid_mismatch_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("top-level", "async-normal")] / "window-owner.json"
            document = json.loads(path.read_text(encoding="utf-8"))
            document["frontmostApplication"]["processID"] = 7777
            write_json(path, document)

        self.assert_failed(mutate)

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

    def test_invalid_wall_clock_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("top-level", "async-normal")] / "window-owner.json"
            document = json.loads(path.read_text(encoding="utf-8"))
            document["wallClockUnixSeconds"] = "stale"
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

    def test_nonzero_operation_exit_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = (
                run_directories[("top-level", "async-normal")]
                / "operation.exit-code.txt"
            )
            path.write_text("2\n", encoding="utf-8")

        self.assert_failed(mutate)

    def test_missing_run_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            _run_directories: dict[tuple[str, str], Path],
            manifest: dict[str, Any],
        ) -> None:
            manifest["runs"] = manifest["runs"][:-1]

        self.assert_failed(mutate)

    def test_artifact_content_change_without_hash_update_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("top-level", "sync-pid")] / "after.json"
            snapshot = json.loads(path.read_text(encoding="utf-8"))
            snapshot["outer"]["x"] = 1
            snapshot["outer"]["y"] = 1
            write_json(path, snapshot)

        completed, report = self.with_artifact(mutate, refresh_hashes=False)
        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        self.assertEqual(report["status"], "fail")

    def test_contract_hash_mismatch_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            _run_directories: dict[tuple[str, str], Path],
            manifest: dict[str, Any],
        ) -> None:
            manifest["contractSha256"] = "0" * 64

        self.assert_failed(mutate)

    def test_candidate_commit_mismatch_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            _run_directories: dict[tuple[str, str], Path],
            manifest: dict[str, Any],
        ) -> None:
            manifest["candidate"]["commit"] = "c" * 40

        self.assert_failed(mutate)

    def test_candidate_executable_content_mismatch_fails(self) -> None:
        def mutate(
            root: Path,
            _manifest_path: Path,
            _run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            (root / APP_EXECUTABLE_RELATIVE_PATH).write_bytes(b"different executable\n")

        self.assert_failed(mutate)

    def test_manifest_probe_schema_bool_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            _run_directories: dict[tuple[str, str], Path],
            manifest: dict[str, Any],
        ) -> None:
            manifest["probeSchemaVersion"] = True

        self.assert_failed(mutate)

    def test_noncanonical_contract_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            manifest_path, _run_directories, manifest = build_positive_artifact(root)
            contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
            frame_edge = next(
                assertion
                for assertion in contract["assertions"]
                if assertion["id"] == "frame-edge"
            )
            frame_edge["transitions"][0]["expect"]["frame.y"] = {
                "comparison": "increased"
            }
            relaxed_contract = root / "relaxed-contract.json"
            write_json(relaxed_contract, contract)
            manifest["contractSha256"] = sha256_file(relaxed_contract)
            write_json(manifest_path, manifest)
            completed, report = run_evaluator(
                root,
                manifest_path,
                contract_path=relaxed_contract,
            )
            self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
            self.assertEqual(report["status"], "fail")

    def test_cross_run_artifact_alias_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            _run_directories: dict[tuple[str, str], Path],
            manifest: dict[str, Any],
        ) -> None:
            normal = find_run(manifest, "top-level", "async-normal")
            pid = find_run(manifest, "top-level", "async-pid")
            normal["artifacts"]["snapshots"] = copy.deepcopy(
                pid["artifacts"]["snapshots"]
            )
            normal["artifacts"]["exitCodes"] = copy.deepcopy(
                pid["artifacts"]["exitCodes"]
            )

        self.assert_failed(mutate)

    def test_cross_run_hard_link_alias_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            source = run_directories[("top-level", "async-pid")] / "after.json"
            destination = run_directories[("top-level", "async-normal")] / "after.json"
            destination.unlink()
            os.link(source, destination)

        self.assert_failed(mutate)

    def test_normalized_cross_run_artifact_alias_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            _run_directories: dict[tuple[str, str], Path],
            manifest: dict[str, Any],
        ) -> None:
            normal = find_run(manifest, "top-level", "async-normal")
            pid = find_run(manifest, "top-level", "async-pid")
            normal["artifacts"]["snapshots"]["after"] = {
                "path": (
                    "runs/top-level/async-normal/../../top-level/"
                    "async-pid/after.json"
                ),
                "sha256": pid["artifacts"]["snapshots"]["after"]["sha256"],
            }

        self.assert_failed(mutate)

    def test_default_manifest_path_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            manifest_path, _run_directories, _manifest = build_positive_artifact(root)
            completed, report = run_evaluator(
                root,
                manifest_path,
                explicit_manifest=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertEqual(report["status"], "pass")

    def test_target_process_float_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            _run_directories: dict[tuple[str, str], Path],
            manifest: dict[str, Any],
        ) -> None:
            run = find_run(manifest, "top-level", "sync-pid")
            run["targetProcessId"] = float(SAFARI_PROCESS_ID)

        self.assert_failed(mutate)

    def test_window_stack_schema_bool_fails(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            run_directories: dict[tuple[str, str], Path],
            _manifest: dict[str, Any],
        ) -> None:
            path = run_directories[("top-level", "async-normal")] / "window-owner.json"
            document = json.loads(path.read_text(encoding="utf-8"))
            document["schemaVersion"] = True
            write_json(path, document)

        self.assert_failed(mutate)

    def test_nonstring_execution_status_is_structured_failure(self) -> None:
        def mutate(
            _root: Path,
            _manifest_path: Path,
            _run_directories: dict[tuple[str, str], Path],
            manifest: dict[str, Any],
        ) -> None:
            run = find_run(manifest, "top-level", "sync-pid")
            run["executionStatus"] = []

        completed, report = self.with_artifact(mutate)
        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        self.assertEqual(report["status"], "fail")
        self.assertGreater(report["failureCount"], 0)

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
