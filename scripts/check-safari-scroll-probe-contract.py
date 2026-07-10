from __future__ import annotations

import json
import sys
from html.parser import HTMLParser
from pathlib import Path


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


def main() -> int:
    repository_root = Path(__file__).resolve().parent.parent
    fixture_root = repository_root / "docs" / "fixtures" / "safari-scroll-probe"
    contract_path = fixture_root / "contract.json"
    errors: list[str] = []

    try:
        contract = json.loads(contract_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"失敗: Safari probe contract を読み取れません: {error}", file=sys.stderr)
        return 1

    schema_version = contract.get("schemaVersion")
    interface_name = contract.get("interfaceName")
    status_element_id = contract.get("statusElementId")
    fixtures = contract.get("fixtures")
    assertions = contract.get("assertions")
    if not isinstance(schema_version, int) or schema_version < 1:
        errors.append("contract.schemaVersion は正の整数である必要があります。")
    if not isinstance(interface_name, str) or not interface_name:
        errors.append("contract.interfaceName がありません。")
    if not isinstance(status_element_id, str) or not status_element_id:
        errors.append("contract.statusElementId がありません。")
    if not isinstance(fixtures, list) or not fixtures:
        errors.append("contract.fixtures がありません。")
    if not isinstance(assertions, list) or not assertions:
        errors.append("contract.assertions がありません。")
    if errors:
        for error in errors:
            print(f"失敗: {error}", file=sys.stderr)
        return 1

    parsed_fixtures: dict[str, tuple[dict[str, object], FixtureHTMLParser]] = {}
    for fixture in fixtures:
        if not isinstance(fixture, dict):
            errors.append("fixture 定義は object である必要があります。")
            continue
        scenario = fixture.get("scenario")
        relative_path = fixture.get("path")
        required_ids = fixture.get("requiredElementIds")
        state_paths = fixture.get("statePaths")
        if not isinstance(scenario, str) or not scenario:
            errors.append("fixture.scenario がありません。")
            continue
        if scenario in parsed_fixtures:
            errors.append(f"fixture scenario が重複しています: {scenario}")
            continue
        if not isinstance(relative_path, str) or Path(relative_path).name != relative_path:
            errors.append(f"{scenario}: fixture.path は同一 directory のファイル名に限定します。")
            continue
        if not isinstance(required_ids, list) or not all(isinstance(value, str) for value in required_ids):
            errors.append(f"{scenario}: requiredElementIds が不正です。")
            continue
        if not isinstance(state_paths, list) or not all(isinstance(value, str) for value in state_paths):
            errors.append(f"{scenario}: statePaths が不正です。")
            continue

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
        if parser.root_attributes.get("data-probe-schema-version") != str(schema_version):
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
                present = sorted(name for name in names if isinstance(name, str) and name in attributes)
                if present:
                    errors.append(f"{scenario}: #{element_id} に禁止属性があります: {present}")

        try:
            initial_state = json.loads("".join(parser.status_text).strip())
        except json.JSONDecodeError as error:
            errors.append(f"{scenario}: #{status_element_id} の初期状態が JSON ではありません: {error}")
            continue
        if initial_state.get("schemaVersion") != schema_version:
            errors.append(f"{scenario}: 初期状態の schemaVersion が一致しません。")
        if initial_state.get("scenario") != scenario:
            errors.append(f"{scenario}: 初期状態の scenario が一致しません。")
        for state_path in state_paths:
            try:
                value_at_path(initial_state, state_path)
            except KeyError:
                errors.append(f"{scenario}: 初期状態に path がありません: {state_path}")

        parsed_fixtures[scenario] = (fixture, parser)

    assertion_ids: set[str] = set()
    allowed_comparisons = {"unchanged", "increased", "decreased"}
    for assertion in assertions:
        if not isinstance(assertion, dict):
            errors.append("assertion 定義は object である必要があります。")
            continue
        assertion_id = assertion.get("id")
        scenario = assertion.get("fixture")
        pointer_element_id = assertion.get("pointerElementId")
        operation = assertion.get("operation")
        expected = assertion.get("expect")
        if not isinstance(assertion_id, str) or not assertion_id:
            errors.append("assertion.id がありません。")
            continue
        if assertion_id in assertion_ids:
            errors.append(f"assertion.id が重複しています: {assertion_id}")
        assertion_ids.add(assertion_id)
        if not isinstance(scenario, str) or scenario not in parsed_fixtures:
            errors.append(f"{assertion_id}: fixture が不正です。")
            continue
        fixture, parser = parsed_fixtures[scenario]
        if not isinstance(pointer_element_id, str) or pointer_element_id not in parser.element_attributes:
            errors.append(f"{assertion_id}: pointerElementId が fixture にありません。")
        if not isinstance(operation, str) or not operation:
            errors.append(f"{assertion_id}: operation がありません。")
        if not isinstance(expected, dict) or not expected:
            errors.append(f"{assertion_id}: expect がありません。")
            continue
        state_paths = set(fixture["statePaths"])
        for state_path, comparison in expected.items():
            if state_path not in state_paths:
                errors.append(f"{assertion_id}: expect path が statePaths にありません: {state_path}")
            if comparison not in allowed_comparisons:
                errors.append(f"{assertion_id}: comparison が不正です: {comparison}")

    if errors:
        for error in errors:
            print(f"失敗: {error}", file=sys.stderr)
        print(f"Safari scroll probe contract は {len(errors)} 件失敗しました。", file=sys.stderr)
        return 1

    print(
        f"Safari scroll probe contract を確認しました: fixture={len(parsed_fixtures)} assertion={len(assertion_ids)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
