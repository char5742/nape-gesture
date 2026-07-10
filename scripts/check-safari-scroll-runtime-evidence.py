from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Any


REPORT_SCHEMA_VERSION = 1
CONTRACT_SCHEMA_VERSION = 2
PASS_EXIT_CODE = 0
FAIL_EXIT_CODE = 1
BLOCKED_EXIT_CODE = 2
INTEGER_PATTERN = re.compile(r"[+-]?\d+")
WINDOW_STACK_POINTER_TOLERANCE = 0.01
EXPECTED_FIXTURE_SCENARIOS = {"top-level", "nested", "frame"}
EXPECTED_ASSERTION_IDS = {
    "generic-generated-fail-closed",
    "generic-native-wheel",
    "vertical-only-frame",
    "long-article",
    "top-level",
    "frame-edge",
}


def is_number(value: object) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
    )


def is_positive_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def is_nonnegative_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def load_json(path: Path) -> object:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def value_at_path(document: object, dotted_path: str) -> object:
    value = document
    for component in dotted_path.split("."):
        if not isinstance(value, dict) or component not in value:
            raise KeyError(dotted_path)
        value = value[component]
    return value


def resolve_artifact(root: Path, relative_path: object) -> Path:
    if not isinstance(relative_path, str) or not relative_path:
        raise ValueError("artifact pathが空です。")
    candidate = Path(relative_path)
    if candidate.is_absolute():
        raise ValueError(f"artifact pathは相対pathに限定します: {relative_path}")
    resolved = (root / candidate).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise ValueError(f"artifact root外のpathは使用できません: {relative_path}") from error
    if not resolved.is_file():
        raise ValueError(f"artifact fileがありません: {relative_path}")
    return resolved


def compare_values(before: object, after: object, rule: object) -> tuple[bool, str]:
    if not isinstance(rule, dict):
        return False, "comparison定義がobjectではありません。"
    comparison = rule.get("comparison")
    if comparison == "unchanged":
        return after == before, f"before={before!r} after={after!r}"
    if comparison == "exact":
        expected = rule.get("value")
        return after == expected, f"expected={expected!r} actual={after!r}"
    if comparison in {"increased", "decreased"}:
        if not is_number(before) or not is_number(after):
            return False, f"数値比較ができません: before={before!r} after={after!r}"
        if comparison == "increased":
            return after > before, f"before={before!r} after={after!r}"
        return after < before, f"before={before!r} after={after!r}"
    return False, f"未知のcomparisonです: {comparison!r}"


def add_check(
    checks: list[dict[str, object]],
    check_id: str,
    passed: bool,
    message: str,
    detail: object | None = None,
) -> None:
    entry: dict[str, object] = {
        "id": check_id,
        "passed": bool(passed),
        "message": message,
    }
    if detail is not None:
        entry["detail"] = detail
    checks.append(entry)


def failure_report(
    artifact_root: Path,
    contract_path: Path,
    manifest_path: Path,
    message: str,
) -> dict[str, object]:
    return {
        "schemaVersion": REPORT_SCHEMA_VERSION,
        "status": "fail",
        "artifactRoot": str(artifact_root),
        "contract": str(contract_path),
        "manifest": str(manifest_path),
        "failureCount": 1,
        "blockedCount": 0,
        "checks": [
            {
                "id": "input",
                "passed": False,
                "message": message,
            }
        ],
        "runs": [],
    }


def parse_contract(contract: object) -> tuple[dict[str, Any], dict[str, Any], list[str]]:
    errors: list[str] = []
    if not isinstance(contract, dict):
        return {}, {}, ["contract rootはobjectである必要があります。"]
    probe_schema_version = contract.get("probeSchemaVersion")
    runtime_evidence = contract.get("runtimeEvidence")
    fixtures = contract.get("fixtures")
    assertions = contract.get("assertions")
    if contract.get("schemaVersion") != CONTRACT_SCHEMA_VERSION:
        errors.append(f"contract.schemaVersionは{CONTRACT_SCHEMA_VERSION}である必要があります。")
    if not is_positive_int(probe_schema_version):
        errors.append("contract.probeSchemaVersionが不正です。")
    if not isinstance(runtime_evidence, dict):
        errors.append("contract.runtimeEvidenceがありません。")
    else:
        if not is_positive_int(runtime_evidence.get("manifestSchemaVersion")):
            errors.append("runtimeEvidence.manifestSchemaVersionが不正です。")
        if runtime_evidence.get("safariBundleIdentifier") != "com.apple.Safari":
            errors.append("runtimeEvidence.safariBundleIdentifierが不正です。")
        maximum_distance = runtime_evidence.get("pointerMaximumDistance")
        if not is_number(maximum_distance) or maximum_distance <= 0:
            errors.append("runtimeEvidence.pointerMaximumDistanceが不正です。")
        success_exit_code = runtime_evidence.get("successExitCode")
        if (
            not isinstance(success_exit_code, int)
            or isinstance(success_exit_code, bool)
            or success_exit_code != 0
        ):
            errors.append("runtimeEvidence.successExitCodeが不正です。")
    if not isinstance(fixtures, list):
        errors.append("contract.fixturesがありません。")
        fixtures = []
    if not isinstance(assertions, list):
        errors.append("contract.assertionsがありません。")
        assertions = []

    fixture_map: dict[str, Any] = {}
    for fixture in fixtures:
        if not isinstance(fixture, dict) or not isinstance(fixture.get("scenario"), str):
            errors.append("contract.fixture定義が不正です。")
            continue
        scenario = fixture["scenario"]
        if scenario in fixture_map:
            errors.append(f"contract.fixtureが重複しています: {scenario}")
            continue
        measurement_paths = fixture.get("measurementPaths")
        reset_expect = fixture.get("resetExpect")
        if not isinstance(measurement_paths, list) or not all(
            isinstance(path, str) and path for path in measurement_paths
        ):
            errors.append(f"{scenario}: measurementPathsが不正です。")
            measurement_paths = []
        elif len(measurement_paths) != len(set(measurement_paths)):
            errors.append(f"{scenario}: measurementPathsが重複しています。")
        if not isinstance(reset_expect, dict) or set(reset_expect) != set(measurement_paths or []):
            errors.append(f"{scenario}: resetExpectがmeasurementPathsを網羅していません。")
        fixture_map[scenario] = fixture
    if set(fixture_map) != EXPECTED_FIXTURE_SCENARIOS:
        errors.append(
            f"contract.fixture集合が不正です: {sorted(fixture_map)}"
        )

    assertion_map: dict[str, Any] = {}
    for assertion in assertions:
        if not isinstance(assertion, dict) or not isinstance(assertion.get("id"), str):
            errors.append("contract.assertion定義が不正です。")
            continue
        assertion_id = assertion["id"]
        if assertion_id in assertion_map:
            errors.append(f"contract.assertionが重複しています: {assertion_id}")
            continue
        scenario = assertion.get("fixture")
        operations = assertion.get("operations")
        transitions = assertion.get("transitions")
        if not isinstance(scenario, str) or scenario not in fixture_map:
            errors.append(f"{assertion_id}: fixtureが不正です。")
        if not isinstance(assertion.get("pointerElementId"), str):
            errors.append(f"{assertion_id}: pointerElementIdが不正です。")
        if not isinstance(operations, list) or not operations:
            errors.append(f"{assertion_id}: operationsがありません。")
        else:
            operation_ids: set[str] = set()
            for operation in operations:
                if not isinstance(operation, dict) or not isinstance(operation.get("id"), str):
                    errors.append(f"{assertion_id}: operation定義が不正です。")
                    continue
                operation_id = operation["id"]
                if operation_id in operation_ids:
                    errors.append(f"{assertion_id}: operation.idが重複しています: {operation_id}")
                operation_ids.add(operation_id)
                if not isinstance(operation.get("kind"), str):
                    errors.append(f"{assertion_id}/{operation_id}: kindが不正です。")
                if operation.get("delivery") not in {"sync", "async", "native"}:
                    errors.append(f"{assertion_id}/{operation_id}: deliveryが不正です。")
                if not isinstance(operation.get("pidOverride"), bool):
                    errors.append(f"{assertion_id}/{operation_id}: pidOverrideが不正です。")
                routing = operation.get("routing")
                if not isinstance(routing, dict) or routing.get("type") not in {
                    "pid-override",
                    "pointer-element",
                    "pointer-window-owner",
                }:
                    errors.append(f"{assertion_id}/{operation_id}: routingが不正です。")
                if "sequence" in operation:
                    sequence = operation.get("sequence")
                    if not isinstance(sequence, list) or not sequence:
                        errors.append(f"{assertion_id}/{operation_id}: sequenceが不正です。")
                    else:
                        for command in sequence:
                            if (
                                not isinstance(command, dict)
                                or not isinstance(command.get("id"), str)
                                or not isinstance(command.get("parameters"), dict)
                                or not is_positive_int(command.get("steps"))
                            ):
                                errors.append(
                                    f"{assertion_id}/{operation_id}: sequence commandが不正です。"
                                )
                elif (
                    not isinstance(operation.get("parameters"), dict)
                    or not is_positive_int(operation.get("steps"))
                ):
                    errors.append(f"{assertion_id}/{operation_id}: parameters/stepsが不正です。")
        if not isinstance(transitions, list) or not transitions:
            errors.append(f"{assertion_id}: transitionsがありません。")
        else:
            scenario_fixture = fixture_map.get(scenario) if isinstance(scenario, str) else None
            measurement_paths = set(
                scenario_fixture.get("measurementPaths", [])
                if isinstance(scenario_fixture, dict)
                else []
            )
            for transition in transitions:
                if not isinstance(transition, dict):
                    errors.append(f"{assertion_id}: transition定義が不正です。")
                    continue
                if not all(
                    isinstance(transition.get(field), str) and transition.get(field)
                    for field in ("from", "to", "exitCode")
                ):
                    errors.append(f"{assertion_id}: transition metadataが不正です。")
                expect = transition.get("expect")
                if not isinstance(expect, dict) or set(expect) != measurement_paths:
                    errors.append(f"{assertion_id}: transition.expectが全pathを網羅していません。")
        assertion_map[assertion_id] = assertion
    if set(assertion_map) != EXPECTED_ASSERTION_IDS:
        errors.append(
            f"contract.assertion集合が不正です: {sorted(assertion_map)}"
        )
    return fixture_map, assertion_map, errors


def validate_pointer_setup(
    setup: object,
    maximum_distance: float,
) -> tuple[bool, str, dict[str, object]]:
    if not isinstance(setup, dict):
        return False, "pointer setupはobjectである必要があります。", {}
    requested = setup.get("requested")
    actual = setup.get("actual")
    stored_distance = setup.get("distance")
    if not isinstance(requested, dict) or not isinstance(actual, dict):
        return False, "pointer setupのrequested/actualがありません。", {}
    coordinates = [
        requested.get("x"),
        requested.get("y"),
        actual.get("x"),
        actual.get("y"),
    ]
    if not all(is_number(value) for value in coordinates) or not is_number(stored_distance):
        return False, "pointer setupの座標またはdistanceが有限数ではありません。", {}
    computed_distance = math.hypot(
        float(actual["x"]) - float(requested["x"]),
        float(actual["y"]) - float(requested["y"]),
    )
    detail = {
        "requested": requested,
        "actual": actual,
        "storedDistance": stored_distance,
        "computedDistance": computed_distance,
        "maximumDistance": maximum_distance,
    }
    if not math.isclose(float(stored_distance), computed_distance, abs_tol=0.01):
        return False, "pointer setupのdistanceが座標から再計算した値と一致しません。", detail
    if computed_distance > maximum_distance:
        return False, "pointer setupが許容距離を超えています。", detail
    return True, "pointer setupを確認しました。", detail


def validate_pointer_window_stack(
    document: object,
    pointer_setup_actual: object,
    expected_bundle_identifier: object,
    safari_process_id: object,
) -> tuple[bool, bool, str, dict[str, object]]:
    if not isinstance(document, dict):
        return False, False, "window stack証跡はobjectである必要があります。", {}
    if document.get("schemaVersion") != 1:
        return False, False, "window stack証跡のschemaVersionは1である必要があります。", {}
    system_uptime = document.get("systemUptimeSeconds")
    if not is_number(system_uptime) or system_uptime <= 0:
        return False, False, "systemUptimeSecondsは正の有限値である必要があります。", {}

    pointer = document.get("pointer")
    if not isinstance(pointer, dict) or not all(
        is_number(pointer.get(axis)) for axis in ("x", "y")
    ):
        return False, False, "window stack証跡のpointer座標が不正です。", {}
    if not isinstance(pointer_setup_actual, dict) or not all(
        is_number(pointer_setup_actual.get(axis)) for axis in ("x", "y")
    ):
        return False, False, "pointer setupのactual座標と照合できません。", {}
    pointer_distance = math.hypot(
        float(pointer["x"]) - float(pointer_setup_actual["x"]),
        float(pointer["y"]) - float(pointer_setup_actual["y"]),
    )
    if pointer_distance > WINDOW_STACK_POINTER_TOLERANCE:
        return (
            False,
            False,
            "window stackとpointer setupの座標が一致しません。",
            {
                "capturedPointer": pointer,
                "pointerSetupActual": pointer_setup_actual,
                "distance": pointer_distance,
                "maximumDistance": WINDOW_STACK_POINTER_TOLERANCE,
            },
        )

    frontmost = document.get("frontmostApplication")
    if not isinstance(frontmost, dict):
        return False, False, "frontmostApplicationがありません。", {}
    if not is_positive_int(frontmost.get("processID")):
        return False, False, "frontmostApplication.processIDが不正です。", {}
    if not isinstance(frontmost.get("bundleIdentifier"), str):
        return False, False, "frontmostApplication.bundleIdentifierが不正です。", {}
    if frontmost.get("localizedName") is not None and not isinstance(
        frontmost.get("localizedName"), str
    ):
        return False, False, "frontmostApplication.localizedNameが不正です。", {}

    windows = document.get("windows")
    if not isinstance(windows, list) or not windows:
        return False, False, "pointer直下のwindows配列が空です。", {}
    stack_indices: list[int] = []
    normalized_windows: list[dict[str, object]] = []
    for index, window in enumerate(windows):
        if not isinstance(window, dict):
            return False, False, f"windows[{index}]はobjectである必要があります。", {}
        stack_index = window.get("stackIndex")
        owner_process_id = window.get("ownerProcessID")
        window_number = window.get("windowNumber")
        bounds = window.get("bounds")
        if not is_nonnegative_int(stack_index):
            return False, False, f"windows[{index}].stackIndexが不正です。", {}
        if not is_positive_int(owner_process_id):
            return False, False, f"windows[{index}].ownerProcessIDが不正です。", {}
        if not is_positive_int(window_number):
            return False, False, f"windows[{index}].windowNumberが不正です。", {}
        if not isinstance(bounds, dict) or not all(
            is_number(bounds.get(name)) for name in ("x", "y", "width", "height")
        ):
            return False, False, f"windows[{index}].boundsが不正です。", {}
        if bounds["width"] <= 0 or bounds["height"] <= 0:
            return False, False, f"windows[{index}].boundsの大きさが不正です。", {}
        contains_pointer = (
            bounds["x"] <= pointer["x"] < bounds["x"] + bounds["width"]
            and bounds["y"] <= pointer["y"] < bounds["y"] + bounds["height"]
        )
        if not contains_pointer:
            return False, False, f"windows[{index}]がcapture pointerを含みません。", {}
        stack_indices.append(stack_index)
        normalized_windows.append(
            {
                "stackIndex": stack_index,
                "ownerProcessID": owner_process_id,
                "windowNumber": window_number,
                "bounds": bounds,
            }
        )
    if stack_indices != sorted(set(stack_indices)):
        return False, False, "windowsがfront-to-backのstackIndex順ではありません。", {}

    prerequisite_met = (
        frontmost.get("bundleIdentifier") == expected_bundle_identifier
        and windows[0].get("ownerProcessID") == safari_process_id
    )
    detail = {
        "systemUptimeSeconds": system_uptime,
        "pointer": pointer,
        "pointerSetupActual": pointer_setup_actual,
        "pointerDistance": pointer_distance,
        "frontmostApplication": frontmost,
        "windows": normalized_windows,
        "expected": {
            "frontmostBundleIdentifier": expected_bundle_identifier,
            "pointerWindowOwnerProcessID": safari_process_id,
        },
    }
    if prerequisite_met:
        return True, True, "通常routingのwindow owner事前条件を確認しました。", detail
    return True, False, "通常routingのwindow owner事前条件は未成立です。", detail


def load_exit_code(root: Path, relative_path: object) -> tuple[int | None, str | None]:
    try:
        path = resolve_artifact(root, relative_path)
        text = path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError, ValueError) as error:
        return None, str(error)
    if INTEGER_PATTERN.fullmatch(text) is None:
        return None, f"exit codeが整数ではありません: {relative_path}"
    return int(text), None


def validate_snapshot(
    snapshot: object,
    probe_schema_version: int,
    scenario: str,
    measurement_paths: list[str],
) -> list[str]:
    errors: list[str] = []
    if not isinstance(snapshot, dict):
        return ["snapshotはobjectである必要があります。"]
    snapshot_schema_version = snapshot.get("schemaVersion")
    if (
        not isinstance(snapshot_schema_version, int)
        or isinstance(snapshot_schema_version, bool)
        or snapshot_schema_version != probe_schema_version
    ):
        errors.append(
            f"schemaVersionが不正です: expected={probe_schema_version} actual={snapshot.get('schemaVersion')!r}"
        )
    if snapshot.get("scenario") != scenario:
        errors.append(
            f"scenarioが不正です: expected={scenario!r} actual={snapshot.get('scenario')!r}"
        )
    if snapshot.get("ready") is not True:
        errors.append(f"ready=trueではありません: {snapshot.get('ready')!r}")
    for path in measurement_paths:
        try:
            value_at_path(snapshot, path)
        except KeyError:
            errors.append(f"measurement pathがありません: {path}")
    return errors


def evaluate_run(
    root: Path,
    manifest: dict[str, Any],
    run: object,
    assertion: dict[str, Any],
    operation: dict[str, Any],
    fixture: dict[str, Any],
    contract: dict[str, Any],
) -> dict[str, object]:
    assertion_id = assertion["id"]
    operation_id = operation["id"]
    checks: list[dict[str, object]] = []
    blocked_reasons: list[dict[str, object]] = []
    result: dict[str, object] = {
        "assertionId": assertion_id,
        "operationId": operation_id,
        "status": "fail",
        "checks": checks,
        "blockedReasons": blocked_reasons,
    }
    if not isinstance(run, dict):
        add_check(checks, "manifest-run", False, "run定義がobjectではありません。")
        result["failureCount"] = 1
        return result

    expected_metadata = {
        "fixture": assertion["fixture"],
        "pointerElementId": assertion["pointerElementId"],
        "operation": operation,
    }
    actual_metadata = {
        "fixture": run.get("fixture"),
        "pointerElementId": run.get("pointerElementId"),
        "operation": run.get("operation"),
    }
    add_check(
        checks,
        "operation-metadata",
        actual_metadata == expected_metadata,
        "fixture、pointer、steps、delivery、PID override、routing metadataを照合しました。",
        {"expected": expected_metadata, "actual": actual_metadata},
    )

    safari = manifest.get("safari")
    safari_process_id = safari.get("processId") if isinstance(safari, dict) else None
    expected_target_process_id = safari_process_id if operation.get("pidOverride") is True else None
    add_check(
        checks,
        "target-process",
        run.get("targetProcessId") == expected_target_process_id,
        "PID固定診断と通常routingのtarget processを分離しました。",
        {
            "expected": expected_target_process_id,
            "actual": run.get("targetProcessId"),
            "pidOverride": operation.get("pidOverride"),
        },
    )

    artifacts = run.get("artifacts")
    if not isinstance(artifacts, dict):
        add_check(checks, "artifacts", False, "run.artifactsがありません。")
        result["failureCount"] = sum(not bool(check["passed"]) for check in checks)
        return result

    runtime_evidence = contract["runtimeEvidence"]
    routing = operation.get("routing")
    routing_type = routing.get("type") if isinstance(routing, dict) else None
    expected_artifact_keys = {"pointerSetup", "snapshots", "exitCodes"}
    if routing_type == "pointer-window-owner":
        expected_artifact_keys.add("windowOwner")
    add_check(
        checks,
        "artifact-set",
        set(artifacts) == expected_artifact_keys,
        "runごとのartifact集合を照合しました。",
        {
            "expected": sorted(expected_artifact_keys),
            "actual": sorted(artifacts),
        },
    )

    pointer_setup_actual: object = None
    try:
        pointer_path = resolve_artifact(root, artifacts.get("pointerSetup"))
        pointer_setup = load_json(pointer_path)
        pointer_passed, pointer_message, pointer_detail = validate_pointer_setup(
            pointer_setup,
            float(runtime_evidence["pointerMaximumDistance"]),
        )
        if isinstance(pointer_setup, dict):
            pointer_setup_actual = pointer_setup.get("actual")
        add_check(checks, "pointer-setup", pointer_passed, pointer_message, pointer_detail)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        add_check(checks, "pointer-setup", False, f"pointer setupを読み取れません: {error}")

    if routing_type == "pointer-window-owner":
        try:
            owner_path = resolve_artifact(root, artifacts.get("windowOwner"))
            owner_document = load_json(owner_path)
            prerequisite = routing.get("ownerPrerequisite")
            expected_bundle = (
                prerequisite.get("bundleIdentifier")
                if isinstance(prerequisite, dict)
                else None
            )
            owner_valid, prerequisite_met, owner_message, owner_detail = (
                validate_pointer_window_stack(
                    owner_document,
                    pointer_setup_actual,
                    expected_bundle,
                    safari_process_id,
                )
            )
            if not owner_valid:
                add_check(
                    checks,
                    "pointer-window-owner",
                    False,
                    owner_message,
                    owner_detail,
                )
            elif prerequisite_met:
                add_check(
                    checks,
                    "pointer-window-owner",
                    True,
                    owner_message,
                    owner_detail,
                )
            else:
                blocked_reasons.append(
                    {
                        "id": "host-overlay",
                        "message": (
                            "通常routing直前のfrontmost applicationまたは"
                            "pointer直下先頭windowがSafariではないためblockedです。"
                        ),
                        "detail": owner_detail,
                    }
                )
                add_check(
                    checks,
                    "pointer-window-owner",
                    True,
                    owner_message,
                    owner_detail,
                )
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
            add_check(
                checks,
                "pointer-window-owner",
                False,
                f"window owner証跡を構造的に確認できません: {error}",
            )
    else:
        add_check(
            checks,
            "routing-kind",
            routing_type in {"pid-override", "pointer-element"},
            "PID固定診断またはnative pointer routingとして確認しました。",
            {"routingType": routing_type},
        )

    transitions = assertion["transitions"]
    required_snapshot_names = {"before"}
    required_exit_names: set[str] = set()
    for transition in transitions:
        required_snapshot_names.add(transition["from"])
        required_snapshot_names.add(transition["to"])
        required_exit_names.add(transition["exitCode"])

    snapshot_paths = artifacts.get("snapshots")
    if not isinstance(snapshot_paths, dict) or set(snapshot_paths) != required_snapshot_names:
        add_check(
            checks,
            "snapshot-set",
            False,
            "before/after/atEndのsnapshot集合がcontractと一致しません。",
            {
                "expected": sorted(required_snapshot_names),
                "actual": sorted(snapshot_paths) if isinstance(snapshot_paths, dict) else None,
            },
        )
        snapshot_paths = snapshot_paths if isinstance(snapshot_paths, dict) else {}
    else:
        add_check(
            checks,
            "snapshot-set",
            True,
            "snapshot集合を確認しました。",
            sorted(required_snapshot_names),
        )

    snapshots: dict[str, object] = {}
    measurement_paths = fixture["measurementPaths"]
    for snapshot_name in sorted(required_snapshot_names):
        try:
            snapshot_path = resolve_artifact(root, snapshot_paths.get(snapshot_name))
            snapshot = load_json(snapshot_path)
            snapshot_errors = validate_snapshot(
                snapshot,
                contract["probeSchemaVersion"],
                assertion["fixture"],
                measurement_paths,
            )
            snapshots[snapshot_name] = snapshot
            add_check(
                checks,
                f"snapshot-{snapshot_name}",
                not snapshot_errors,
                "snapshotのready/schema/scenario/pathを確認しました。"
                if not snapshot_errors
                else "snapshot契約に違反しています。",
                snapshot_errors or snapshot_paths.get(snapshot_name),
            )
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
            add_check(
                checks,
                f"snapshot-{snapshot_name}",
                False,
                f"snapshotを読み取れません: {error}",
            )

    before_snapshot = snapshots.get("before")
    if before_snapshot is not None:
        for path, rule in fixture["resetExpect"].items():
            try:
                actual = value_at_path(before_snapshot, path)
                passed, detail = compare_values(None, actual, rule)
            except KeyError:
                passed, detail = False, "pathがありません。"
            add_check(
                checks,
                f"reset:{path}",
                passed,
                "reset初期値を確認しました。" if passed else "reset初期値が一致しません。",
                detail,
            )

    exit_code_paths = artifacts.get("exitCodes")
    if not isinstance(exit_code_paths, dict) or set(exit_code_paths) != required_exit_names:
        add_check(
            checks,
            "exit-code-set",
            False,
            "exit code集合がcontractと一致しません。",
            {
                "expected": sorted(required_exit_names),
                "actual": sorted(exit_code_paths) if isinstance(exit_code_paths, dict) else None,
            },
        )
        exit_code_paths = exit_code_paths if isinstance(exit_code_paths, dict) else {}
    else:
        add_check(
            checks,
            "exit-code-set",
            True,
            "exit code集合を確認しました。",
            sorted(required_exit_names),
        )
    for exit_name in sorted(required_exit_names):
        actual_exit_code, exit_error = load_exit_code(root, exit_code_paths.get(exit_name))
        expected_exit_code = runtime_evidence["successExitCode"]
        add_check(
            checks,
            f"exit-code:{exit_name}",
            exit_error is None and actual_exit_code == expected_exit_code,
            "operationのexit codeを確認しました。"
            if exit_error is None and actual_exit_code == expected_exit_code
            else "operationのexit codeが成功値ではありません。",
            exit_error
            or {"expected": expected_exit_code, "actual": actual_exit_code},
        )

    structural_failure_count = sum(not bool(check["passed"]) for check in checks)
    if not blocked_reasons and structural_failure_count == 0:
        for transition_index, transition in enumerate(transitions):
            before = snapshots[transition["from"]]
            after = snapshots[transition["to"]]
            for path, rule in transition["expect"].items():
                try:
                    before_value = value_at_path(before, path)
                    after_value = value_at_path(after, path)
                    passed, detail = compare_values(before_value, after_value, rule)
                except KeyError:
                    passed, detail = False, "pathがありません。"
                add_check(
                    checks,
                    f"transition-{transition_index}:{path}",
                    passed,
                    "状態遷移がcontractと一致しました。"
                    if passed
                    else "状態遷移がcontractと一致しません。",
                    detail,
                )

    failure_count = sum(not bool(check["passed"]) for check in checks)
    result["failureCount"] = failure_count
    if failure_count:
        result["status"] = "fail"
    elif blocked_reasons:
        result["status"] = "blocked"
    else:
        result["status"] = "pass"
    return result


def evaluate(
    artifact_root: Path,
    contract_path: Path,
    manifest_path: Path,
) -> tuple[dict[str, object], int]:
    root = artifact_root.resolve()
    resolved_contract = contract_path.resolve()
    resolved_manifest = manifest_path.resolve()
    try:
        contract = load_json(resolved_contract)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        report = failure_report(
            root,
            resolved_contract,
            resolved_manifest,
            f"contractを読み取れません: {error}",
        )
        return report, FAIL_EXIT_CODE
    try:
        manifest = load_json(resolved_manifest)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        report = failure_report(
            root,
            resolved_contract,
            resolved_manifest,
            f"manifestを読み取れません: {error}",
        )
        return report, FAIL_EXIT_CODE
    if not root.is_dir():
        report = failure_report(
            root,
            resolved_contract,
            resolved_manifest,
            "artifact rootがdirectoryではありません。",
        )
        return report, FAIL_EXIT_CODE
    if not isinstance(contract, dict) or not isinstance(manifest, dict):
        report = failure_report(
            root,
            resolved_contract,
            resolved_manifest,
            "contract/manifest rootはobjectである必要があります。",
        )
        return report, FAIL_EXIT_CODE

    fixture_map, assertion_map, contract_errors = parse_contract(contract)
    global_checks: list[dict[str, object]] = []
    add_check(
        global_checks,
        "contract-shape",
        not contract_errors,
        (
            "runtime contractの構造を確認しました。"
            if not contract_errors
            else "runtime contractが不正です。"
        ),
        contract_errors or None,
    )
    runtime_evidence = contract.get("runtimeEvidence")
    expected_manifest_schema = (
        runtime_evidence.get("manifestSchemaVersion")
        if isinstance(runtime_evidence, dict)
        else None
    )
    manifest_versions_match = (
        manifest.get("schemaVersion") == expected_manifest_schema
        and manifest.get("contractSchemaVersion") == contract.get("schemaVersion")
        and manifest.get("probeSchemaVersion") == contract.get("probeSchemaVersion")
    )
    add_check(
        global_checks,
        "manifest-versions",
        manifest_versions_match,
        "manifest、contract、probeのschema versionを照合しました。",
        {
            "manifest": manifest.get("schemaVersion"),
            "contract": manifest.get("contractSchemaVersion"),
            "probe": manifest.get("probeSchemaVersion"),
        },
    )
    safari = manifest.get("safari")
    safari_valid = (
        isinstance(safari, dict)
        and safari.get("bundleIdentifier")
        == (runtime_evidence.get("safariBundleIdentifier") if isinstance(runtime_evidence, dict) else None)
        and is_positive_int(safari.get("processId"))
    )
    add_check(
        global_checks,
        "safari-identity",
        safari_valid,
        "Safariのbundle identifierとprocess IDを確認しました。",
        safari,
    )

    expected_runs: dict[tuple[str, str], tuple[dict[str, Any], dict[str, Any]]] = {}
    if not contract_errors:
        for assertion_id, assertion in assertion_map.items():
            for operation in assertion["operations"]:
                expected_runs[(assertion_id, operation["id"])] = (assertion, operation)

    runs = manifest.get("runs")
    actual_runs: dict[tuple[str, str], object] = {}
    duplicate_runs: list[str] = []
    invalid_run_count = 0
    if isinstance(runs, list):
        for run in runs:
            if not isinstance(run, dict):
                invalid_run_count += 1
                continue
            key = (run.get("assertionId"), run.get("operationId"))
            if not all(isinstance(component, str) and component for component in key):
                invalid_run_count += 1
                continue
            typed_key = (key[0], key[1])
            if typed_key in actual_runs:
                duplicate_runs.append(f"{typed_key[0]}/{typed_key[1]}")
            else:
                actual_runs[typed_key] = run
    else:
        runs = []
        invalid_run_count = 1

    expected_keys = set(expected_runs)
    actual_keys = set(actual_runs)
    run_set_valid = (
        not contract_errors
        and not duplicate_runs
        and invalid_run_count == 0
        and actual_keys == expected_keys
    )
    add_check(
        global_checks,
        "run-set",
        run_set_valid,
        "assertionとoperationのruntime run集合を照合しました。",
        {
            "missing": [f"{a}/{o}" for a, o in sorted(expected_keys - actual_keys)],
            "extra": [f"{a}/{o}" for a, o in sorted(actual_keys - expected_keys)],
            "duplicates": duplicate_runs,
            "invalidRunCount": invalid_run_count,
        },
    )

    run_results: list[dict[str, object]] = []
    if not contract_errors and safari_valid:
        for key in sorted(expected_keys & actual_keys):
            assertion, operation = expected_runs[key]
            fixture = fixture_map[assertion["fixture"]]
            run_results.append(
                evaluate_run(
                    root,
                    manifest,
                    actual_runs[key],
                    assertion,
                    operation,
                    fixture,
                    contract,
                )
            )

    global_failure_count = sum(not bool(check["passed"]) for check in global_checks)
    run_failure_count = sum(int(run["failureCount"]) for run in run_results)
    blocked_count = sum(run["status"] == "blocked" for run in run_results)
    if global_failure_count or run_failure_count:
        status = "fail"
        exit_code = FAIL_EXIT_CODE
    elif blocked_count:
        status = "blocked"
        exit_code = BLOCKED_EXIT_CODE
    else:
        status = "pass"
        exit_code = PASS_EXIT_CODE

    report: dict[str, object] = {
        "schemaVersion": REPORT_SCHEMA_VERSION,
        "status": status,
        "artifactRoot": str(root),
        "contract": str(resolved_contract),
        "manifest": str(resolved_manifest),
        "failureCount": global_failure_count + run_failure_count,
        "blockedCount": blocked_count,
        "checks": global_checks,
        "runs": run_results,
    }
    return report, exit_code


def parse_arguments() -> argparse.Namespace:
    repository_root = Path(__file__).resolve().parent.parent
    default_contract = (
        repository_root / "docs" / "fixtures" / "safari-scroll-probe" / "contract.json"
    )
    parser = argparse.ArgumentParser(description="Safari scroll runtime証跡を機械判定します。")
    parser.add_argument("artifact_root", type=Path, help="証跡artifact root")
    parser.add_argument(
        "--contract",
        type=Path,
        default=default_contract,
        help="runtime contract.json",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        help="runtime manifest。省略時はartifact root/safari-scroll-runtime-manifest.json",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    manifest_path = (
        arguments.manifest
        if arguments.manifest is not None
        else arguments.artifact_root / "safari-scroll-runtime-manifest.json"
    )
    report, exit_code = evaluate(
        arguments.artifact_root,
        arguments.contract,
        manifest_path,
    )
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
