from __future__ import annotations

import argparse
import json
import math
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


CONTRACT_SCHEMA_VERSION = 2
EXPECTED_ASSERTION_IDS = {
    "generic-generated-fail-closed",
    "generic-native-wheel",
    "vertical-only-frame",
    "long-article",
    "top-level",
    "frame-edge",
}
EXPECTED_MEASUREMENT_PATHS = {
    "top-level": (
        "outer.x",
        "outer.y",
        "outer.wheel.count",
        "outer.wheel.target",
        "inner",
        "frame",
    ),
    "nested": (
        "outer.x",
        "outer.y",
        "outer.wheel.count",
        "outer.wheel.target",
        "inner.x",
        "inner.y",
        "inner.wheel.count",
        "inner.wheel.target",
        "frame.x",
        "frame.y",
        "frame.maxY",
        "frame.atEnd",
        "frame.wheel.count",
        "frame.wheel.target",
    ),
    "frame": (
        "scroll.x",
        "scroll.y",
        "scroll.maxY",
        "scroll.atEnd",
        "wheel.count",
        "wheel.target",
    ),
}
EXPECTED_FIXTURE_PATHS = {
    "top-level": "top-level.html",
    "nested": "nested.html",
    "frame": "frame.html",
}
EXPECTED_RESET_VALUES = {
    "top-level": {
        "outer.x": 0,
        "outer.y": 0,
        "outer.wheel.count": 0,
        "outer.wheel.target": "none",
        "inner": None,
        "frame": None,
    },
    "nested": {
        "outer.x": 0,
        "outer.y": 0,
        "outer.wheel.count": 0,
        "outer.wheel.target": "none",
        "inner.x": 0,
        "inner.y": 0,
        "inner.wheel.count": 0,
        "inner.wheel.target": "none",
        "frame.x": 0,
        "frame.y": 0,
        "frame.maxY": 1468,
        "frame.atEnd": False,
        "frame.wheel.count": 0,
        "frame.wheel.target": "none",
    },
    "frame": {
        "scroll.x": 0,
        "scroll.y": 0,
        "scroll.maxY": 1468,
        "scroll.atEnd": False,
        "wheel.count": 0,
        "wheel.target": "none",
    },
}


class FixtureHTMLParser(HTMLParser):
    def __init__(self, status_element_id: str, interface_name: str) -> None:
        super().__init__(convert_charrefs=True)
        self.status_element_id = status_element_id
        self.interface_name = interface_name
        self.root_attributes: dict[str, str | None] = {}
        self.element_attributes: dict[str, dict[str, str | None]] = {}
        self.duplicate_ids: set[str] = set()
        self.interface_script_count = 0
        self.status_depth = 0
        self.status_text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if tag == "html":
            self.root_attributes = attributes
        element_id = attributes.get("id")
        if element_id is not None:
            if element_id in self.element_attributes:
                self.duplicate_ids.add(element_id)
            self.element_attributes[element_id] = attributes
            if element_id == self.status_element_id:
                self.status_depth = 1
        elif self.status_depth > 0:
            self.status_depth += 1
        if tag == "script" and attributes.get("data-probe-interface") == self.interface_name:
            self.interface_script_count += 1

    def handle_endtag(self, _tag: str) -> None:
        if self.status_depth > 0:
            self.status_depth -= 1

    def handle_data(self, data: str) -> None:
        if self.status_depth > 0:
            self.status_text.append(data)


def value_at_path(value: object, path: str) -> object:
    current = value
    for component in path.split("."):
        if not isinstance(current, dict) or component not in current:
            raise KeyError(path)
        current = current[component]
    return current


def comparison(name: str, value: object = ...) -> dict[str, object]:
    result: dict[str, object] = {"comparison": name}
    if value is not ...:
        result["value"] = value
    return result


def expected_map(scenario: str, overrides: dict[str, dict[str, object]]) -> dict[str, dict[str, object]]:
    return {
        path: overrides.get(path, comparison("unchanged"))
        for path in EXPECTED_MEASUREMENT_PATHS[scenario]
    }


def generated_operation(
    operation_id: str,
    delivery: str,
    x: int,
    y: int,
    *,
    normal_routing: bool = False,
) -> dict[str, object]:
    if normal_routing:
        routing: dict[str, object] = {
            "type": "pointer-window-owner",
            "ownerPrerequisite": {
                "bundleIdentifier": "com.apple.Safari",
                "processIdSource": "manifest.safari.processId",
            },
        }
    else:
        routing = {"type": "pid-override"}
    return {
        "id": operation_id,
        "kind": "generated-scroll",
        "parameters": {"x": x, "y": y, "mode": "free"},
        "steps": 1,
        "delivery": delivery,
        "pidOverride": not normal_routing,
        "routing": routing,
    }


def pid_operations(x: int, y: int) -> list[dict[str, object]]:
    return [
        generated_operation("sync-pid", "sync", x, y),
        generated_operation("async-pid", "async", x, y),
    ]


def edge_operations() -> list[dict[str, object]]:
    sequence = [
        {
            "id": "reachEnd",
            "parameters": {"x": 0, "y": 10000, "mode": "free"},
            "steps": 1,
        },
        {
            "id": "edge",
            "parameters": {"x": 0, "y": 800, "mode": "free"},
            "steps": 1,
        },
    ]
    return [
        {
            "id": "sync-pid",
            "kind": "generated-scroll",
            "sequence": sequence,
            "delivery": "sync",
            "pidOverride": True,
            "routing": {"type": "pid-override"},
        },
        {
            "id": "async-pid",
            "kind": "generated-scroll",
            "sequence": sequence,
            "delivery": "async",
            "pidOverride": True,
            "routing": {"type": "pid-override"},
        },
    ]


EXPECTED_ASSERTIONS: dict[str, dict[str, object]] = {
    "generic-generated-fail-closed": {
        "fixture": "nested",
        "pointerElementId": "inner",
        "operations": pid_operations(1, 800),
        "transitions": [
            {
                "from": "before",
                "to": "after",
                "exitCode": "operation",
                "expect": expected_map("nested", {}),
            }
        ],
    },
    "generic-native-wheel": {
        "fixture": "nested",
        "pointerElementId": "inner",
        "operations": [
            {
                "id": "native-wheel",
                "kind": "native-wheel",
                "parameters": {"direction": "down", "pages": 0.2},
                "steps": 1,
                "delivery": "native",
                "pidOverride": False,
                "routing": {"type": "pointer-element"},
            }
        ],
        "transitions": [
            {
                "from": "before",
                "to": "after",
                "exitCode": "operation",
                "expect": expected_map(
                    "nested",
                    {
                        "inner.y": comparison("increased"),
                        "inner.wheel.count": comparison("increased"),
                        "inner.wheel.target": comparison("exact", "generic-1"),
                    },
                ),
            }
        ],
    },
    "vertical-only-frame": {
        "fixture": "nested",
        "pointerElementId": "frame",
        "operations": pid_operations(1, 800),
        "transitions": [
            {
                "from": "before",
                "to": "after",
                "exitCode": "operation",
                "expect": expected_map(
                    "nested", {"frame.y": comparison("increased")}
                ),
            }
        ],
    },
    "long-article": {
        "fixture": "nested",
        "pointerElementId": "article",
        "operations": pid_operations(0, 800),
        "transitions": [
            {
                "from": "before",
                "to": "after",
                "exitCode": "operation",
                "expect": expected_map(
                    "nested", {"outer.y": comparison("increased")}
                ),
            }
        ],
    },
    "top-level": {
        "fixture": "top-level",
        "pointerElementId": "top-content",
        "operations": pid_operations(1600, 800)
        + [generated_operation("async-normal", "async", 1600, 800, normal_routing=True)],
        "transitions": [
            {
                "from": "before",
                "to": "after",
                "exitCode": "operation",
                "expect": expected_map(
                    "top-level",
                    {
                        "outer.x": comparison("increased"),
                        "outer.y": comparison("increased"),
                    },
                ),
            }
        ],
    },
    "frame-edge": {
        "fixture": "nested",
        "pointerElementId": "frame",
        "operations": edge_operations(),
        "transitions": [
            {
                "from": "before",
                "to": "atEnd",
                "exitCode": "reachEnd",
                "expect": expected_map(
                    "nested",
                    {
                        "frame.y": comparison("increased"),
                        "frame.atEnd": comparison("exact", True),
                    },
                ),
            },
            {
                "from": "atEnd",
                "to": "after",
                "exitCode": "edge",
                "expect": expected_map("nested", {}),
            },
        ],
    },
}


def is_positive_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def validate_comparison(
    rule: object, context: str, errors: list[str]
) -> None:
    if not isinstance(rule, dict):
        errors.append(f"{context}: comparison 定義は object である必要があります。")
        return
    comparison_name = rule.get("comparison")
    if comparison_name not in {"unchanged", "increased", "decreased", "exact"}:
        errors.append(f"{context}: comparison が不正です: {comparison_name}")
        return
    expected_keys = {"comparison", "value"} if comparison_name == "exact" else {"comparison"}
    if set(rule) != expected_keys:
        errors.append(
            f"{context}: {comparison_name} の必須fieldが一致しません: {sorted(rule)}"
        )


def validate_contract(
    contract: object,
    fixture_root: Path,
) -> tuple[list[str], int, int]:
    errors: list[str] = []
    if not isinstance(contract, dict):
        return ["contract root は object である必要があります。"], 0, 0

    schema_version = contract.get("schemaVersion")
    probe_schema_version = contract.get("probeSchemaVersion")
    interface_name = contract.get("interfaceName")
    status_element_id = contract.get("statusElementId")
    fixtures = contract.get("fixtures")
    assertions = contract.get("assertions")
    runtime_evidence = contract.get("runtimeEvidence")

    if schema_version != CONTRACT_SCHEMA_VERSION:
        errors.append(
            f"contract.schemaVersion は {CONTRACT_SCHEMA_VERSION} である必要があります。"
        )
    if not is_positive_int(probe_schema_version):
        errors.append("contract.probeSchemaVersion は正の整数である必要があります。")
    if not isinstance(interface_name, str) or not interface_name:
        errors.append("contract.interfaceName がありません。")
    if not isinstance(status_element_id, str) or not status_element_id:
        errors.append("contract.statusElementId がありません。")
    if not isinstance(fixtures, list) or not fixtures:
        errors.append("contract.fixtures がありません。")
    if not isinstance(assertions, list) or not assertions:
        errors.append("contract.assertions がありません。")
    if not isinstance(runtime_evidence, dict):
        errors.append("contract.runtimeEvidence がありません。")
    else:
        if runtime_evidence.get("manifestSchemaVersion") != 2:
            errors.append("runtimeEvidence.manifestSchemaVersion は 2 である必要があります。")
        if runtime_evidence.get("safariBundleIdentifier") != "com.apple.Safari":
            errors.append(
                "runtimeEvidence.safariBundleIdentifier は com.apple.Safari である必要があります。"
            )
        maximum_distance = runtime_evidence.get("pointerMaximumDistance")
        if (
            not isinstance(maximum_distance, (int, float))
            or isinstance(maximum_distance, bool)
            or not math.isfinite(maximum_distance)
            or maximum_distance <= 0
        ):
            errors.append("runtimeEvidence.pointerMaximumDistance は正の有限値が必要です。")
        success_exit_code = runtime_evidence.get("successExitCode")
        if (
            not isinstance(success_exit_code, int)
            or isinstance(success_exit_code, bool)
            or success_exit_code != 0
        ):
            errors.append("runtimeEvidence.successExitCode は 0 である必要があります。")
    if errors:
        return errors, 0, 0

    parsed_fixtures: dict[str, tuple[dict[str, Any], FixtureHTMLParser]] = {}
    fixture_scenarios: set[str] = set()
    for fixture in fixtures:
        if not isinstance(fixture, dict):
            errors.append("fixture 定義は object である必要があります。")
            continue
        scenario = fixture.get("scenario")
        relative_path = fixture.get("path")
        required_ids = fixture.get("requiredElementIds")
        state_paths = fixture.get("statePaths")
        measurement_paths = fixture.get("measurementPaths")
        reset_expect = fixture.get("resetExpect")
        if not isinstance(scenario, str) or not scenario:
            errors.append("fixture.scenario がありません。")
            continue
        if scenario in fixture_scenarios:
            errors.append(f"fixture scenario が重複しています: {scenario}")
            continue
        fixture_scenarios.add(scenario)
        if scenario not in EXPECTED_FIXTURE_PATHS:
            errors.append(f"未知の fixture scenario です: {scenario}")
            continue
        if relative_path != EXPECTED_FIXTURE_PATHS[scenario]:
            errors.append(f"{scenario}: fixture.path が期待値と一致しません。")
            continue
        if not isinstance(relative_path, str) or Path(relative_path).name != relative_path:
            errors.append(f"{scenario}: fixture.path は同一 directory のファイル名に限定します。")
            continue
        if not isinstance(required_ids, list) or not all(
            isinstance(value, str) and value for value in required_ids
        ):
            errors.append(f"{scenario}: requiredElementIds が不正です。")
            continue

        expected_measurements = set(EXPECTED_MEASUREMENT_PATHS[scenario])
        if (
            not isinstance(measurement_paths, list)
            or len(measurement_paths) != len(expected_measurements)
            or set(measurement_paths) != expected_measurements
        ):
            errors.append(f"{scenario}: measurementPaths が完全な集合ではありません。")
            continue
        expected_state_paths = expected_measurements | {"ready"}
        if (
            not isinstance(state_paths, list)
            or len(state_paths) != len(expected_state_paths)
            or set(state_paths) != expected_state_paths
        ):
            errors.append(f"{scenario}: statePaths が完全な集合ではありません。")
            continue
        if not isinstance(reset_expect, dict) or set(reset_expect) != expected_measurements:
            errors.append(f"{scenario}: resetExpect が全measurement pathを網羅していません。")
            continue
        for path, expected_value in EXPECTED_RESET_VALUES[scenario].items():
            rule = reset_expect[path]
            validate_comparison(rule, f"{scenario}.resetExpect.{path}", errors)
            if rule != comparison("exact", expected_value):
                errors.append(f"{scenario}: reset初期値が不正です: {path}")

        fixture_path = fixture_root / relative_path
        parser = FixtureHTMLParser(status_element_id, interface_name)
        try:
            parser.feed(fixture_path.read_text(encoding="utf-8"))
            parser.close()
        except (OSError, UnicodeError) as error:
            errors.append(f"{scenario}: HTML を読み取れません: {error}")
            continue

        if parser.duplicate_ids:
            errors.append(f"{scenario}: id が重複しています: {sorted(parser.duplicate_ids)}")
        if parser.root_attributes.get("data-probe-scenario") != scenario:
            errors.append(f"{scenario}: html[data-probe-scenario] が一致しません。")
        if parser.root_attributes.get("data-probe-schema-version") != str(probe_schema_version):
            errors.append(f"{scenario}: html[data-probe-schema-version] が一致しません。")
        if parser.interface_script_count != 1:
            errors.append(f"{scenario}: data-probe-interface={interface_name} の script は1個必要です。")
        missing_ids = sorted(set(required_ids) - set(parser.element_attributes))
        if missing_ids:
            errors.append(f"{scenario}: 必須 element id がありません: {missing_ids}")

        forbidden_attributes = fixture.get("forbiddenAttributesByElementId", {})
        if not isinstance(forbidden_attributes, dict):
            errors.append(f"{scenario}: forbiddenAttributesByElementId が不正です。")
        else:
            for element_id, names in forbidden_attributes.items():
                if not isinstance(element_id, str) or not isinstance(names, list):
                    errors.append(f"{scenario}: forbidden attribute 定義が不正です。")
                    continue
                attributes = parser.element_attributes.get(element_id, {})
                present = sorted(
                    name for name in names if isinstance(name, str) and name in attributes
                )
                if present:
                    errors.append(f"{scenario}: #{element_id} に禁止属性があります: {present}")

        try:
            initial_state = json.loads("".join(parser.status_text).strip())
        except json.JSONDecodeError as error:
            errors.append(f"{scenario}: #{status_element_id} の初期状態が JSON ではありません: {error}")
            continue
        if initial_state.get("schemaVersion") != probe_schema_version:
            errors.append(f"{scenario}: 初期状態の schemaVersion が一致しません。")
        if initial_state.get("scenario") != scenario:
            errors.append(f"{scenario}: 初期状態の scenario が一致しません。")
        for state_path in state_paths:
            try:
                value_at_path(initial_state, state_path)
            except KeyError:
                errors.append(f"{scenario}: 初期状態に path がありません: {state_path}")
        for path, expected_value in EXPECTED_RESET_VALUES[scenario].items():
            try:
                actual_value = value_at_path(initial_state, path)
            except KeyError:
                continue
            if actual_value != expected_value:
                errors.append(
                    f"{scenario}: HTML初期状態がreset値と一致しません: {path}={actual_value!r}"
                )

        parsed_fixtures[scenario] = (fixture, parser)

    if fixture_scenarios != set(EXPECTED_FIXTURE_PATHS):
        errors.append(
            f"fixture scenario集合が不正です: {sorted(fixture_scenarios)}"
        )

    assertion_ids: set[str] = set()
    for assertion in assertions:
        if not isinstance(assertion, dict):
            errors.append("assertion 定義は object である必要があります。")
            continue
        assertion_id = assertion.get("id")
        if not isinstance(assertion_id, str) or not assertion_id:
            errors.append("assertion.id がありません。")
            continue
        if assertion_id in assertion_ids:
            errors.append(f"assertion.id が重複しています: {assertion_id}")
            continue
        assertion_ids.add(assertion_id)
        expected_assertion = EXPECTED_ASSERTIONS.get(assertion_id)
        if expected_assertion is None:
            errors.append(f"未知の assertion.id です: {assertion_id}")
            continue

        scenario = assertion.get("fixture")
        pointer_element_id = assertion.get("pointerElementId")
        operations = assertion.get("operations")
        transitions = assertion.get("transitions")
        expected_keys = {"id", "fixture", "pointerElementId", "operations", "transitions"}
        if set(assertion) != expected_keys:
            errors.append(
                f"{assertion_id}: assertion field集合が不正です: {sorted(assertion)}"
            )
        if scenario != expected_assertion["fixture"]:
            errors.append(f"{assertion_id}: fixture が期待値と一致しません。")
            continue
        if scenario not in parsed_fixtures:
            errors.append(f"{assertion_id}: fixture を検証できません。")
            continue
        _, parser = parsed_fixtures[scenario]
        if pointer_element_id != expected_assertion["pointerElementId"]:
            errors.append(f"{assertion_id}: pointerElementId が期待値と一致しません。")
        if not isinstance(pointer_element_id, str) or pointer_element_id not in parser.element_attributes:
            errors.append(f"{assertion_id}: pointerElementId が fixture にありません。")

        if not isinstance(operations, list):
            errors.append(f"{assertion_id}: operations がありません。")
        else:
            operation_ids = [
                operation.get("id") if isinstance(operation, dict) else None
                for operation in operations
            ]
            if len(operation_ids) != len(set(operation_ids)):
                errors.append(f"{assertion_id}: operation.id が重複しています。")
            if operations != expected_assertion["operations"]:
                errors.append(
                    f"{assertion_id}: steps/delivery/PID/routingを含む"
                    "operation metadataが期待値と一致しません。"
                )

        if not isinstance(transitions, list):
            errors.append(f"{assertion_id}: transitions がありません。")
            continue
        for transition_index, transition in enumerate(transitions):
            if not isinstance(transition, dict):
                errors.append(f"{assertion_id}: transition は object である必要があります。")
                continue
            expect = transition.get("expect")
            if not isinstance(expect, dict):
                errors.append(f"{assertion_id}: transition.expect がありません。")
                continue
            measurement_paths = set(EXPECTED_MEASUREMENT_PATHS[scenario])
            if set(expect) != measurement_paths:
                errors.append(
                    f"{assertion_id}: transition[{transition_index}] が"
                    "全measurement pathを網羅していません。"
                )
            for path, rule in expect.items():
                validate_comparison(
                    rule,
                    f"{assertion_id}.transitions[{transition_index}].expect.{path}",
                    errors,
                )
        if transitions != expected_assertion["transitions"]:
            errors.append(
                f"{assertion_id}: path、比較演算子、snapshot遷移、"
                "exit code契約が期待値と一致しません。"
            )

    if assertion_ids != EXPECTED_ASSERTION_IDS:
        missing = sorted(EXPECTED_ASSERTION_IDS - assertion_ids)
        extra = sorted(assertion_ids - EXPECTED_ASSERTION_IDS)
        errors.append(f"assertion.id集合が不正です: missing={missing} extra={extra}")

    return errors, len(parsed_fixtures), len(assertion_ids)


def parse_arguments() -> argparse.Namespace:
    repository_root = Path(__file__).resolve().parent.parent
    default_fixture_root = repository_root / "docs" / "fixtures" / "safari-scroll-probe"
    parser = argparse.ArgumentParser(description="Safari scroll probe contractを静的検査します。")
    parser.add_argument(
        "--contract",
        type=Path,
        default=default_fixture_root / "contract.json",
        help="検査するcontract.json",
    )
    parser.add_argument(
        "--fixture-root",
        type=Path,
        default=default_fixture_root,
        help="Safari probe HTMLがあるdirectory",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        contract = json.loads(arguments.contract.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"失敗: Safari probe contract を読み取れません: {error}", file=sys.stderr)
        return 1

    errors, fixture_count, assertion_count = validate_contract(
        contract,
        arguments.fixture_root,
    )
    if errors:
        for error in errors:
            print(f"失敗: {error}", file=sys.stderr)
        print(f"Safari scroll probe contract は {len(errors)} 件失敗しました。", file=sys.stderr)
        return 1

    print(
        "Safari scroll probe contract を確認しました: "
        f"schema={CONTRACT_SCHEMA_VERSION} fixture={fixture_count} assertion={assertion_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
