#!/bin/sh

# Issue #16 のうち、実機や TCC 操作なしで取得できる機械証跡を収集する。
# 実行ビットは不要です。`sh scripts/collect-completion-evidence.sh` で実行してください。

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

cd "$repo_root" || {
  printf '%s\n' "リポジトリ root へ移動できません: $repo_root" >&2
  exit 1
}

git_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ ! -f Package.swift ] || [ "$git_root" != "$repo_root" ]; then
  printf '%s\n' "このスクリプトは nape-gesture のリポジトリ root で実行してください。" >&2
  exit 1
fi

repo_head_sha=$(git rev-parse HEAD 2>/dev/null)
tracked_status=$(git status --porcelain --untracked-files=no 2>/dev/null)
if [ -z "$repo_head_sha" ] || [ -n "$tracked_status" ]; then
  printf '%s\n' "完成証跡はcleanなtracked treeから取得してください。repoHead=${repo_head_sha:-unknown}" >&2
  [ -z "$tracked_status" ] || printf '%s\n' "$tracked_status" >&2
  exit 1
fi

for required_path in \
  Fixtures/trackpad-contract/25F80/scroll-output-model-samples.json \
  Fixtures/trackpad-contract/25F80/scroll-output-model.json \
  Sources/NapeGestureProductOutput/ProductGestureSessionCoordinator.swift \
  Sources/NapeGestureProductOutput/TrackpadGestureOutputAdapter.swift \
  Sources/NapeGestureProductOutput/TrackpadScrollOutputModel.swift \
  Sources/nape-gesture-product-output-tests/main.swift \
  scripts/check-product-model-documentation.rb \
  scripts/check-finger-count-product-model.rb \
  scripts/derive-trackpad-scroll-output-model.rb \
  scripts/finalize-product-output-provenance.rb \
  scripts/test-finalize-product-output-provenance.rb
do
  if ! git ls-files --error-unmatch "$required_path" >/dev/null 2>&1; then
    printf '%s\n' "完成証跡の必須fileがGit管理下にありません: $required_path" >&2
    exit 1
  fi
done

artifact_root=${NAPE_COMPLETION_ARTIFACT_ROOT:-"artifacts/completion/$(date +%F)/machine-evidence"}
commands_file="$artifact_root/commands.txt"
summary_file="$artifact_root/summary.md"
failure_count=0
failed_logs=""

mkdir -p "$artifact_root"
: > "$commands_file"

cat > "$summary_file" <<EOF
# Issue #16 機械証跡サマリー

- 証跡 root: \`$artifact_root\`
- 実行日時: $(date '+%F %T %z')
- repo HEAD: \`$repo_head_sha\`
- tracked tree: clean
- 対象: 実機、TCC 操作、実イベント投稿なしで取得できる機械証跡

## 注意

このスクリプトで埋められるのは機械証跡だけです。
Nape Pro実機、純正トラックパッドの未確定contract、縦横scroll / application navigation / Space切替 / Mission Control / App Exposé / ZoomのOS/App結果、TCC、公証、Developer ID署名は未完了のままです。

## コマンド結果

| 結果 | 項目 | 終了コード | ログ |
| --- | --- | --- | --- |
EOF

append_summary() {
  result=$1
  title=$2
  status=$3
  log_path=$4
  printf '| %s | %s | %s | `%s` |\n' "$result" "$title" "$status" "$log_path" >> "$summary_file"
}

remember_failure() {
  failure_count=$((failure_count + 1))
  if [ -z "$failed_logs" ]; then
    failed_logs=$1
  else
    failed_logs="$failed_logs
$1"
  fi
}

run_combined_success() {
  title=$1
  log_path=$2
  display=$3
  shift 3

  mkdir -p "$(dirname -- "$log_path")"
  printf '$ %s > %s 2>&1\n' "$display" "$log_path" >> "$commands_file"
  printf '%s\n' "実行中: $title"

  "$@" > "$log_path" 2>&1
  status=$?

  if [ "$status" -eq 0 ]; then
    append_summary "成功" "$title" "$status" "$log_path"
  else
    append_summary "失敗" "$title" "$status" "$log_path"
    remember_failure "$log_path"
  fi
}

run_split_success() {
  title=$1
  stdout_path=$2
  stderr_path=$3
  display=$4
  shift 4

  mkdir -p "$(dirname -- "$stdout_path")" "$(dirname -- "$stderr_path")"
  printf '$ %s > %s 2> %s\n' "$display" "$stdout_path" "$stderr_path" >> "$commands_file"
  printf '%s\n' "実行中: $title"

  "$@" > "$stdout_path" 2> "$stderr_path"
  status=$?

  if [ "$status" -eq 0 ]; then
    append_summary "成功" "$title" "$status" "$stdout_path"
  else
    append_summary "失敗" "$title" "$status" "$stdout_path / $stderr_path"
    remember_failure "$stdout_path / $stderr_path"
  fi
}

run_split_expected_failure() {
  title=$1
  stdout_path=$2
  stderr_path=$3
  display=$4
  shift 4

  mkdir -p "$(dirname -- "$stdout_path")" "$(dirname -- "$stderr_path")"
  printf '$ %s > %s 2> %s\n' "$display" "$stdout_path" "$stderr_path" >> "$commands_file"
  printf '%s\n' "実行中: $title"

  "$@" > "$stdout_path" 2> "$stderr_path"
  status=$?

  if [ "$status" -ne 0 ]; then
    append_summary "期待どおり失敗" "$title" "$status" "$stdout_path / $stderr_path"
  else
    append_summary "期待に反して成功" "$title" "$status" "$stdout_path / $stderr_path"
    remember_failure "$stdout_path / $stderr_path"
  fi
}

run_split_expected_status() {
  title=$1
  stdout_path=$2
  stderr_path=$3
  display=$4
  expected_status=$5
  shift 5

  mkdir -p "$(dirname -- "$stdout_path")" "$(dirname -- "$stderr_path")"
  printf '$ %s > %s 2> %s\n' "$display" "$stdout_path" "$stderr_path" >> "$commands_file"
  printf '%s\n' "実行中: $title"

  "$@" > "$stdout_path" 2> "$stderr_path"
  status=$?

  if [ "$status" -eq "$expected_status" ]; then
    append_summary "期待どおり失敗" "$title" "$status" "$stdout_path / $stderr_path"
  else
    append_summary "期待外の終了コード" "$title" "$status" "$stdout_path / $stderr_path"
    remember_failure "$stdout_path / $stderr_path"
  fi
}

build_dir="$artifact_root/build-and-tests"
bundle_dir="$artifact_root/bundle"
gui_dir="$artifact_root/gui-smoke"
provenance_dir="$artifact_root/provenance"
doctor_dir="$artifact_root/doctor-and-performance"
system_dir="$artifact_root/system-test-dry-run"
fixtures_dir="$artifact_root/fixtures-analysis"
trackpad_analyzer_dir="$artifact_root/trackpad-event-analyzer"
hid_dir="$artifact_root/hid-inventory"

config_path="$doctor_dir/nape-gesture.config.json"
blocked_config_path="$doctor_dir/nape-gesture-impossible-target.config.json"
gui_config_path="$gui_dir/nape-gui-smoke.config.json"

run_combined_success \
  "由来ガード" \
  "$provenance_dir/check-provenance.log" \
  "sh scripts/check-provenance.sh" \
  sh scripts/check-provenance.sh

run_combined_success \
  "由来ガード回帰テスト" \
  "$provenance_dir/test-check-provenance.log" \
  "sh scripts/test-check-provenance.sh" \
  sh scripts/test-check-provenance.sh

run_combined_success \
  "製品モデル文書ガード" \
  "$provenance_dir/check-product-model-documentation.log" \
  "ruby scripts/check-product-model-documentation.rb" \
  ruby scripts/check-product-model-documentation.rb

run_combined_success \
  "固定finger-count製品モデルガード" \
  "$provenance_dir/check-finger-count-product-model.log" \
  "ruby scripts/check-finger-count-product-model.rb" \
  ruby scripts/check-finger-count-product-model.rb

run_combined_success \
  "製品gesture出力境界ガード" \
  "$provenance_dir/check-product-output-boundary.log" \
  "sh scripts/check-product-output-boundary.sh" \
  sh scripts/check-product-output-boundary.sh

run_combined_success \
  "診断event時刻境界ガード" \
  "$provenance_dir/check-diagnostic-event-time.log" \
  "sh scripts/check-diagnostic-event-time.sh" \
  sh scripts/check-diagnostic-event-time.sh

run_combined_success \
  "debug build" \
  "$build_dir/swift-build.log" \
  "swift build --scratch-path .build" \
  swift build --scratch-path .build

run_combined_success \
  "debug binary保存" \
  "$build_dir/debug-binary-copy.log" \
  "cp .build/debug/nape-gesture $build_dir/nape-gesture.debug" \
  cp .build/debug/nape-gesture "$build_dir/nape-gesture.debug"

run_combined_success \
  "debug binary SHA-256" \
  "$build_dir/debug-binary-sha256.txt" \
  "shasum -a 256 $build_dir/nape-gesture.debug" \
  shasum -a 256 "$build_dir/nape-gesture.debug"

run_combined_success \
  "core tests" \
  "$build_dir/core-tests.log" \
  ".build/debug/nape-gesture-core-tests" \
  .build/debug/nape-gesture-core-tests

run_combined_success \
  "移行前product output回帰test（完成判定外）" \
  "$build_dir/product-output-tests.log" \
  ".build/debug/nape-gesture-product-output-tests" \
  .build/debug/nape-gesture-product-output-tests

run_combined_success \
  "Trackpad scroll output model再導出" \
  "$build_dir/scroll-output-model-derivation.log" \
  "ruby scripts/derive-trackpad-scroll-output-model.rb | cmp - Fixtures/trackpad-contract/25F80/scroll-output-model.json" \
  sh -c 'ruby scripts/derive-trackpad-scroll-output-model.rb | cmp - Fixtures/trackpad-contract/25F80/scroll-output-model.json'

run_combined_success \
  "製品output provenance確定テスト" \
  "$build_dir/product-output-provenance-finalizer-tests.log" \
  "ruby scripts/test-finalize-product-output-provenance.rb" \
  ruby scripts/test-finalize-product-output-provenance.rb

run_combined_success \
  "app bundle原子的置換・保持テスト" \
  "$build_dir/bundle-app-safety-tests.log" \
  "sh scripts/test-bundle-app-safety.sh .build/debug/nape-gesture" \
  sh scripts/test-bundle-app-safety.sh .build/debug/nape-gesture

mkdir -p "$trackpad_analyzer_dir"

run_combined_success \
  "Trackpad analyzer fixture生成" \
  "$trackpad_analyzer_dir/fixture-generation.log" \
  ".build/debug/nape-gesture-diagnostic-output-tests --write-trackpad-analyzer-fixtures trackpad-event-analyzer" \
  .build/debug/nape-gesture-diagnostic-output-tests \
  --write-trackpad-analyzer-fixtures "$trackpad_analyzer_dir"

run_split_success \
  "Trackpad analyzer host正常系" \
  "$trackpad_analyzer_dir/host.report.json" \
  "$trackpad_analyzer_dir/host.stderr.log" \
  ".build/debug/nape-gesture analyze-trackpad-event-log host.jsonl --manifest host.manifest.json --json" \
  .build/debug/nape-gesture analyze-trackpad-event-log \
  "$trackpad_analyzer_dir/host.jsonl" \
  --manifest "$trackpad_analyzer_dir/host.manifest.json" \
  --json

run_split_success \
  "Trackpad analyzer generatedProduct正常系" \
  "$trackpad_analyzer_dir/generated.report.json" \
  "$trackpad_analyzer_dir/generated.stderr.log" \
  ".build/debug/nape-gesture analyze-trackpad-event-log generated.jsonl --manifest generated.manifest.json --provenance generated.provenance.jsonl --json" \
  .build/debug/nape-gesture analyze-trackpad-event-log \
  "$trackpad_analyzer_dir/generated.jsonl" \
  --manifest "$trackpad_analyzer_dir/generated.manifest.json" \
  --provenance "$trackpad_analyzer_dir/generated.provenance.jsonl" \
  --json

contract_path="Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json"

run_split_success \
  "Trackpad analyzer contract正常系" \
  "$trackpad_analyzer_dir/contract-valid.report.json" \
  "$trackpad_analyzer_dir/contract-valid.stderr.log" \
  ".build/debug/nape-gesture analyze-trackpad-event-log contract-valid.jsonl --manifest contract-valid.manifest.json --provenance contract-valid.provenance.jsonl --contract $contract_path --json" \
  .build/debug/nape-gesture analyze-trackpad-event-log \
  "$trackpad_analyzer_dir/contract-valid.jsonl" \
  --manifest "$trackpad_analyzer_dir/contract-valid.manifest.json" \
  --provenance "$trackpad_analyzer_dir/contract-valid.provenance.jsonl" \
  --contract "$contract_path" \
  --json

run_split_expected_status \
  "Trackpad analyzer momentum terminal欠落contract" \
  "$trackpad_analyzer_dir/contract-missing-momentum-terminal.report.json" \
  "$trackpad_analyzer_dir/contract-missing-momentum-terminal.stderr.log" \
  ".build/debug/nape-gesture analyze-trackpad-event-log contract-missing-momentum-terminal.jsonl --manifest contract-missing-momentum-terminal.manifest.json --provenance contract-missing-momentum-terminal.provenance.jsonl --contract $contract_path --json" \
  1 \
  .build/debug/nape-gesture analyze-trackpad-event-log \
  "$trackpad_analyzer_dir/contract-missing-momentum-terminal.jsonl" \
  --manifest "$trackpad_analyzer_dir/contract-missing-momentum-terminal.manifest.json" \
  --provenance "$trackpad_analyzer_dir/contract-missing-momentum-terminal.provenance.jsonl" \
  --contract "$contract_path" \
  --json

run_split_expected_status \
  "Trackpad analyzer未確定type 29混入contract" \
  "$trackpad_analyzer_dir/contract-unconfirmed-gesture.report.json" \
  "$trackpad_analyzer_dir/contract-unconfirmed-gesture.stderr.log" \
  ".build/debug/nape-gesture analyze-trackpad-event-log contract-unconfirmed-gesture.jsonl --manifest contract-unconfirmed-gesture.manifest.json --provenance contract-unconfirmed-gesture.provenance.jsonl --contract $contract_path --json" \
  1 \
  .build/debug/nape-gesture analyze-trackpad-event-log \
  "$trackpad_analyzer_dir/contract-unconfirmed-gesture.jsonl" \
  --manifest "$trackpad_analyzer_dir/contract-unconfirmed-gesture.manifest.json" \
  --provenance "$trackpad_analyzer_dir/contract-unconfirmed-gesture.provenance.jsonl" \
  --contract "$contract_path" \
  --json

run_split_expected_failure \
  "Trackpad analyzer provenance欠落" \
  "$trackpad_analyzer_dir/missing-provenance.report.json" \
  "$trackpad_analyzer_dir/missing-provenance.stderr.log" \
  ".build/debug/nape-gesture analyze-trackpad-event-log generated.jsonl --manifest generated.manifest.json --json" \
  .build/debug/nape-gesture analyze-trackpad-event-log \
  "$trackpad_analyzer_dir/generated.jsonl" \
  --manifest "$trackpad_analyzer_dir/generated.manifest.json" \
  --json

run_split_expected_failure \
  "Trackpad analyzer PID配送拒否" \
  "$trackpad_analyzer_dir/pid.report.json" \
  "$trackpad_analyzer_dir/pid.stderr.log" \
  ".build/debug/nape-gesture analyze-trackpad-event-log generated.jsonl --manifest generated.manifest.json --provenance pid.provenance.jsonl --json" \
  .build/debug/nape-gesture analyze-trackpad-event-log \
  "$trackpad_analyzer_dir/generated.jsonl" \
  --manifest "$trackpad_analyzer_dir/generated.manifest.json" \
  --provenance "$trackpad_analyzer_dir/pid.provenance.jsonl" \
  --json

run_split_expected_failure \
  "Trackpad analyzer負raw field拒否" \
  "$trackpad_analyzer_dir/negative-raw.report.json" \
  "$trackpad_analyzer_dir/negative-raw.stderr.log" \
  ".build/debug/nape-gesture analyze-trackpad-event-log negative-raw.jsonl --manifest negative-raw.manifest.json --json" \
  .build/debug/nape-gesture analyze-trackpad-event-log \
  "$trackpad_analyzer_dir/negative-raw.jsonl" \
  --manifest "$trackpad_analyzer_dir/negative-raw.manifest.json" \
  --json

run_combined_success \
  "Trackpad analyzer report契約確認" \
  "$trackpad_analyzer_dir/report-contract-check.log" \
  "Ruby JSON check for host/generated/missing/PID/negative reports" \
  ruby -rjson -e '
    root = ARGV.fetch(0)
    read = ->(name) { JSON.parse(File.read(File.join(root, name))) }
    host = read.call("host.report.json")
    abort "host正常系またはPhase 1 schema互換性" unless host["schemaVersion"] == 1 && !host.key?("contractPath") && !host.key?("contractComparison") && host["passed"]
    generated = read.call("generated.report.json")
    abort "generated正常系またはPhase 1 schema互換性" unless generated["schemaVersion"] == 1 && !generated.key?("contractPath") && !generated.key?("contractComparison") && generated["passed"]
    missing = read.call("missing-provenance.report.json")
    abort "provenance欠落" unless !missing["passed"] && missing.dig("provenance", "required") && !missing.dig("provenance", "provided")
    pid = read.call("pid.report.json")
    abort "PID配送" unless pid.dig("provenance", "analysis", "issues").any? { |issue| issue["code"] == "forbiddenDelivery" }
    negative = read.call("negative-raw.report.json")
    abort "負raw field" unless negative.dig("structure", "issues").any? { |issue| issue["code"] == "raw_field_number_out_of_range" }
    valid_contract = read.call("contract-valid.report.json")
    valid_comparison = valid_contract["contractComparison"]
    abort "contract正常系schema" unless valid_contract["schemaVersion"] == 2
    abort "contract正常系section" unless valid_contract["passed"] && valid_contract.dig("structure", "passed") && valid_contract.dig("manifest", "passed") && valid_contract.dig("hostReconstruction", "passed") && valid_contract.dig("provenance", "passed")
    abort "contract正常系比較" unless valid_comparison && valid_comparison["provided"] && valid_comparison["passed"]
    invalid_contract = read.call("contract-missing-momentum-terminal.report.json")
    invalid_comparison = invalid_contract["contractComparison"]
    invalid_codes = Array(invalid_comparison && invalid_comparison["issues"]).map { |issue| issue["code"] }
    abort "contract異常系schema" unless invalid_contract["schemaVersion"] == 2
    abort "contract異常系section" unless !invalid_contract["passed"] && invalid_contract.dig("structure", "passed") && invalid_contract.dig("manifest", "passed") && invalid_contract.dig("hostReconstruction", "passed") && invalid_contract.dig("provenance", "passed")
    abort "contract異常系比較" unless invalid_comparison && invalid_comparison["provided"] && !invalid_comparison["passed"] && invalid_codes.include?("missing_momentum_terminal")
    unconfirmed_contract = read.call("contract-unconfirmed-gesture.report.json")
    unconfirmed_comparison = unconfirmed_contract["contractComparison"]
    unconfirmed_codes = Array(unconfirmed_comparison && unconfirmed_comparison["issues"]).map { |issue| issue["code"] }
    abort "未確定type 29混入contract" unless unconfirmed_contract["schemaVersion"] == 2 && !unconfirmed_contract["passed"] && unconfirmed_contract.dig("structure", "passed") && unconfirmed_contract.dig("manifest", "passed") && unconfirmed_contract.dig("hostReconstruction", "passed") && unconfirmed_contract.dig("provenance", "passed") && unconfirmed_comparison && !unconfirmed_comparison["passed"] && unconfirmed_codes.include?("unconfirmed_gesture_event")
    puts "trackpad analyzer report contract passed"
  ' "$trackpad_analyzer_dir"

run_split_success \
  "公開trackpad fixture間identity照合" \
  "$fixtures_dir/trackpad-contract-fixtures.json" \
  "$fixtures_dir/trackpad-contract-fixtures.stderr.log" \
  "ruby scripts/verify-trackpad-physical-observations.rb --fixtures-only --json" \
  ruby scripts/verify-trackpad-physical-observations.rb --fixtures-only --json

run_split_success \
  "公開trackpad contractとlocal物理原本の照合" \
  "$fixtures_dir/trackpad-contract-raw-verification.json" \
  "$fixtures_dir/trackpad-contract-raw-verification.stderr.log" \
  "ruby scripts/verify-trackpad-physical-observations.rb --json" \
  ruby scripts/verify-trackpad-physical-observations.rb --json

printf '%s' '{"schemaVersion":2}' > "$trackpad_analyzer_dir/invalid-log.jsonl"
printf '%s\n' '{}' > "$trackpad_analyzer_dir/invalid-manifest.json"

run_split_expected_failure \
  "Trackpad raw analyzer不正入力" \
  "$trackpad_analyzer_dir/invalid-report.json" \
  "$trackpad_analyzer_dir/invalid-report.stderr.log" \
  ".build/debug/nape-gesture analyze-trackpad-event-log invalid-log.jsonl --manifest invalid-manifest.json --json" \
  .build/debug/nape-gesture analyze-trackpad-event-log \
  "$trackpad_analyzer_dir/invalid-log.jsonl" \
  --manifest "$trackpad_analyzer_dir/invalid-manifest.json" \
  --json

run_combined_success \
  "Trackpad raw analyzer失敗report確認" \
  "$trackpad_analyzer_dir/invalid-report-check.log" \
  "grep -F '\"passed\" : false' invalid-report.json" \
  grep -F '"passed" : false' "$trackpad_analyzer_dir/invalid-report.json"

run_combined_success \
  "diagnostic output tests" \
  "$build_dir/diagnostic-output-tests.log" \
  ".build/debug/nape-gesture-diagnostic-output-tests" \
  .build/debug/nape-gesture-diagnostic-output-tests

run_combined_success \
  "release build" \
  "$build_dir/swift-build-release.log" \
  "swift build -c release --scratch-path .build" \
  swift build -c release --scratch-path .build

run_combined_success \
  "app bundle 作成" \
  "$bundle_dir/bundle-app.log" \
  ".build/release/nape-gesture bundle-app --out .build/NapeGesture.app --replace" \
  .build/release/nape-gesture bundle-app --out .build/NapeGesture.app --replace

run_combined_success \
  "app bundle 検証" \
  "$bundle_dir/verify-bundle.log" \
  ".build/release/nape-gesture verify-bundle .build/NapeGesture.app" \
  .build/release/nape-gesture verify-bundle .build/NapeGesture.app

run_combined_success \
  "app bundle identity 確認" \
  "$bundle_dir/info-plist-identity-check.log" \
  "PlistBuddy CFBundleIdentifier / CFBundleExecutable / CFBundleName / CFBundleDisplayName / LSUIElement exact check" \
  sh -c "/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'dev.char5742.nape-gesture' && /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'nape-gesture' && /usr/libexec/PlistBuddy -c 'Print :CFBundleName' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'Nape Gesture' && /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'Nape Gesture' && /usr/libexec/PlistBuddy -c 'Print :LSUIElement' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'false'"

run_combined_success \
  "GUI smoke 設定作成" \
  "$gui_dir/init-gui-smoke-config.log" \
  ".build/debug/nape-gesture init-config --out $gui_config_path" \
  .build/debug/nape-gesture init-config --out "$gui_config_path"

run_split_success \
  "app GUI smoke JSON" \
  "$gui_dir/gui-smoke-app.json" \
  "$gui_dir/gui-smoke-app.stderr.log" \
  ".build/NapeGesture.app/Contents/MacOS/nape-gesture gui-smoke --config $gui_config_path --json --assert" \
  .build/NapeGesture.app/Contents/MacOS/nape-gesture gui-smoke --config "$gui_config_path" --json --assert

run_split_expected_failure \
  "未署名 app bundle 署名必須検証" \
  "$bundle_dir/verify-bundle-require-signature-unsigned.log" \
  "$bundle_dir/verify-bundle-require-signature-unsigned.stderr.log" \
  ".build/release/nape-gesture verify-bundle --require-signature .build/NapeGesture.app" \
  .build/release/nape-gesture verify-bundle --require-signature .build/NapeGesture.app

run_combined_success \
  "LICENSE 原本一致確認" \
  "$bundle_dir/license-cmp.log" \
  "cmp LICENSE .build/NapeGesture.app/Contents/Resources/LICENSE.txt" \
  cmp LICENSE .build/NapeGesture.app/Contents/Resources/LICENSE.txt

run_combined_success \
  "THIRD_PARTY_NOTICES 原本一致確認" \
  "$bundle_dir/third-party-notices-cmp.log" \
  "cmp THIRD_PARTY_NOTICES.md .build/NapeGesture.app/Contents/Resources/THIRD_PARTY_NOTICES.md" \
  cmp THIRD_PARTY_NOTICES.md .build/NapeGesture.app/Contents/Resources/THIRD_PARTY_NOTICES.md

run_combined_success \
  "Trackpad scroll contract bundle一致確認" \
  "$bundle_dir/trackpad-scroll-contract-cmp.log" \
  "cmp Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json .build/NapeGesture.app/Contents/Resources/TrackpadContracts/25F80/scroll-momentum-contract.json" \
  cmp Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json .build/NapeGesture.app/Contents/Resources/TrackpadContracts/25F80/scroll-momentum-contract.json

run_combined_success \
  "Trackpad scroll output model bundle一致確認" \
  "$bundle_dir/trackpad-scroll-output-model-cmp.log" \
  "cmp Fixtures/trackpad-contract/25F80/scroll-output-model.json .build/NapeGesture.app/Contents/Resources/TrackpadContracts/25F80/scroll-output-model.json" \
  cmp Fixtures/trackpad-contract/25F80/scroll-output-model.json .build/NapeGesture.app/Contents/Resources/TrackpadContracts/25F80/scroll-output-model.json

run_combined_success \
  "app bundle ad-hoc 署名" \
  "$bundle_dir/codesign-ad-hoc.log" \
  "codesign --force --deep --sign - .build/NapeGesture.app" \
  codesign --force --deep --sign - .build/NapeGesture.app

run_combined_success \
  "app bundle codesign 検証" \
  "$bundle_dir/codesign-verify.log" \
  "codesign --verify --deep --strict --verbose=2 .build/NapeGesture.app" \
  codesign --verify --deep --strict --verbose=2 .build/NapeGesture.app

run_combined_success \
  "署名済み app bundle 署名必須検証" \
  "$bundle_dir/verify-bundle-require-signature-signed.log" \
  ".build/release/nape-gesture verify-bundle --require-signature .build/NapeGesture.app" \
  .build/release/nape-gesture verify-bundle --require-signature .build/NapeGesture.app

run_combined_success \
  "検証用設定作成" \
  "$doctor_dir/init-config.log" \
  ".build/debug/nape-gesture init-config --allow-unmatched --out $config_path" \
  .build/debug/nape-gesture init-config --allow-unmatched --out "$config_path"

run_combined_success \
  "不一致対象デバイス設定作成" \
  "$doctor_dir/init-config-impossible-target.log" \
  ".build/debug/nape-gesture init-config --vendor-id 65535 --product-id 65535 --manufacturer-contains ImpossibleNapeDevice --product-contains ImpossibleNapeDevice --out $blocked_config_path" \
  .build/debug/nape-gesture init-config --vendor-id 65535 --product-id 65535 --manufacturer-contains ImpossibleNapeDevice --product-contains ImpossibleNapeDevice --out "$blocked_config_path"

run_split_success \
  "doctor JSON" \
  "$doctor_dir/doctor-debug.json" \
  "$doctor_dir/doctor-debug.stderr.log" \
  ".build/debug/nape-gesture doctor --config $config_path --benchmark-events 50000 --json" \
  .build/debug/nape-gesture doctor --config "$config_path" --benchmark-events 50000 --json

run_combined_success \
  "doctor JSON runtimeReadiness / tccStatus / permissionTarget / targetDeviceDiagnostics field check" \
  "$doctor_dir/doctor-json-field-check.log" \
  "grep -q runtimeReadiness $doctor_dir/doctor-debug.json && grep -q tccStatus $doctor_dir/doctor-debug.json && grep -q permissionTarget $doctor_dir/doctor-debug.json && grep -q grantRequired $doctor_dir/doctor-debug.json && grep -q targetDeviceDiagnostics $doctor_dir/doctor-debug.json && grep -q outputContract $doctor_dir/doctor-debug.json" \
  sh -c "grep -q '\"runtimeReadiness\"' '$doctor_dir/doctor-debug.json' && grep -q '\"tccStatus\"' '$doctor_dir/doctor-debug.json' && grep -q '\"permissionTarget\"' '$doctor_dir/doctor-debug.json' && grep -q '\"grantRequired\"' '$doctor_dir/doctor-debug.json' && grep -q '\"targetDeviceDiagnostics\"' '$doctor_dir/doctor-debug.json' && grep -q '\"outputContract\"' '$doctor_dir/doctor-debug.json'"

run_split_success \
  "doctor HID probe JSON" \
  "$doctor_dir/doctor-hid-probe-debug.json" \
  "$doctor_dir/doctor-hid-probe-debug.stderr.log" \
  ".build/debug/nape-gesture doctor --config $config_path --probe-hid --benchmark-events 1000 --json" \
  .build/debug/nape-gesture doctor --config "$config_path" --probe-hid --benchmark-events 1000 --json

run_combined_success \
  "doctor HID probe JSON runtimeReadiness / tccStatus / permissionTarget / targetDeviceDiagnostics field check" \
  "$doctor_dir/doctor-hid-probe-json-field-check.log" \
  "grep -q runtimeReadiness $doctor_dir/doctor-hid-probe-debug.json && grep -q tccStatus $doctor_dir/doctor-hid-probe-debug.json && grep -q permissionTarget $doctor_dir/doctor-hid-probe-debug.json && grep -q grantRequired $doctor_dir/doctor-hid-probe-debug.json && grep -q targetDeviceDiagnostics $doctor_dir/doctor-hid-probe-debug.json && grep -q outputContract $doctor_dir/doctor-hid-probe-debug.json" \
  sh -c "grep -q '\"runtimeReadiness\"' '$doctor_dir/doctor-hid-probe-debug.json' && grep -q '\"tccStatus\"' '$doctor_dir/doctor-hid-probe-debug.json' && grep -q '\"permissionTarget\"' '$doctor_dir/doctor-hid-probe-debug.json' && grep -q '\"grantRequired\"' '$doctor_dir/doctor-hid-probe-debug.json' && grep -q '\"targetDeviceDiagnostics\"' '$doctor_dir/doctor-hid-probe-debug.json' && grep -q '\"outputContract\"' '$doctor_dir/doctor-hid-probe-debug.json'"

run_split_expected_failure \
  "doctor assert-runtime-ready requires HID probe" \
  "$doctor_dir/doctor-assert-runtime-ready-requires-probe.json" \
  "$doctor_dir/doctor-assert-runtime-ready-requires-probe.stderr.log" \
  ".build/debug/nape-gesture doctor --config $config_path --benchmark-events 1000 --json --assert-runtime-ready" \
  .build/debug/nape-gesture doctor --config "$config_path" --benchmark-events 1000 --json --assert-runtime-ready

run_combined_success \
  "doctor assert-runtime-ready requires HID probe code check" \
  "$doctor_dir/doctor-assert-runtime-ready-requires-probe-code-check.log" \
  "grep -q inputMonitoring.notProbed $doctor_dir/doctor-assert-runtime-ready-requires-probe.json" \
  grep -q "inputMonitoring.notProbed" "$doctor_dir/doctor-assert-runtime-ready-requires-probe.json"

run_split_expected_failure \
  "doctor assert-runtime-ready target mismatch" \
  "$doctor_dir/doctor-assert-runtime-ready-target-mismatch.json" \
  "$doctor_dir/doctor-assert-runtime-ready-target-mismatch.stderr.log" \
  ".build/debug/nape-gesture doctor --config $blocked_config_path --probe-hid --benchmark-events 1000 --json --assert-runtime-ready" \
  .build/debug/nape-gesture doctor --config "$blocked_config_path" --probe-hid --benchmark-events 1000 --json --assert-runtime-ready

run_combined_success \
  "doctor assert-runtime-ready target mismatch code / diagnostics check" \
  "$doctor_dir/doctor-assert-runtime-ready-target-mismatch-code-check.log" \
  "grep -q targetDevice.notFound $doctor_dir/doctor-assert-runtime-ready-target-mismatch.json && grep -q targetDeviceDiagnostics $doctor_dir/doctor-assert-runtime-ready-target-mismatch.json && grep -q bestEvaluation $doctor_dir/doctor-assert-runtime-ready-target-mismatch.json" \
  sh -c "grep -q 'targetDevice.notFound' '$doctor_dir/doctor-assert-runtime-ready-target-mismatch.json' && grep -q '\"targetDeviceDiagnostics\"' '$doctor_dir/doctor-assert-runtime-ready-target-mismatch.json' && grep -q '\"bestEvaluation\"' '$doctor_dir/doctor-assert-runtime-ready-target-mismatch.json'"

run_split_success \
  "benchmark baseline JSON" \
  "$doctor_dir/benchmark-debug.json" \
  "$doctor_dir/benchmark-debug.stderr.log" \
  ".build/debug/nape-gesture benchmark --events 200000 --json --assert-baseline" \
  .build/debug/nape-gesture benchmark --events 200000 --json --assert-baseline

run_combined_success \
  "benchmark JSON schemaVersion / p95 / p99 field check" \
  "$doctor_dir/benchmark-json-percentile-field-check.log" \
  "grep -q schemaVersion 3 / sampledNanosecondsPerEvent / sampledNanosecondsPerCommand / p95Nanoseconds / p99Nanoseconds $doctor_dir/benchmark-debug.json" \
  sh -c "grep -q '\"schemaVersion\"[[:space:]]*:[[:space:]]*3' '$doctor_dir/benchmark-debug.json' && grep -q '\"sampledNanosecondsPerEvent\"' '$doctor_dir/benchmark-debug.json' && grep -q '\"sampledNanosecondsPerCommand\"' '$doctor_dir/benchmark-debug.json' && grep -q '\"p95Nanoseconds\"' '$doctor_dir/benchmark-debug.json' && grep -q '\"p99Nanoseconds\"' '$doctor_dir/benchmark-debug.json' && grep -q '\"recognizerP95NanosecondsPerEvent\"' '$doctor_dir/benchmark-debug.json' && grep -q '\"scrollPlannerP99NanosecondsPerCommand\"' '$doctor_dir/benchmark-debug.json'"

run_combined_success \
  "doctor benchmark JSON schemaVersion / p95 / p99 field check" \
  "$doctor_dir/doctor-benchmark-percentile-field-check.log" \
  "grep -q schemaVersion 3 / sampledNanosecondsPerEvent / sampledNanosecondsPerCommand / p95Nanoseconds / p99Nanoseconds $doctor_dir/doctor-debug.json" \
  sh -c "grep -q '\"schemaVersion\"[[:space:]]*:[[:space:]]*3' '$doctor_dir/doctor-debug.json' && grep -q '\"sampledNanosecondsPerEvent\"' '$doctor_dir/doctor-debug.json' && grep -q '\"sampledNanosecondsPerCommand\"' '$doctor_dir/doctor-debug.json' && grep -q '\"p95Nanoseconds\"' '$doctor_dir/doctor-debug.json' && grep -q '\"p99Nanoseconds\"' '$doctor_dir/doctor-debug.json' && grep -q '\"recognizerP95NanosecondsPerEvent\"' '$doctor_dir/doctor-debug.json' && grep -q '\"scrollPlannerP99NanosecondsPerCommand\"' '$doctor_dir/doctor-debug.json'"

run_combined_success \
  "移行前normal-after-release診断（完成判定外）" \
  "$system_dir/system-normal-after-release.log" \
  ".build/debug/nape-gesture system-test run --scenario normal-after-release --dry-run --log-json --out $system_dir/system-normal-after-release.jsonl" \
  .build/debug/nape-gesture system-test run --scenario normal-after-release --dry-run --log-json --out "$system_dir/system-normal-after-release.jsonl"

run_split_success \
  "移行前normal-after-release解析（完成判定外）" \
  "$system_dir/system-normal-after-release-analysis.json" \
  "$system_dir/system-normal-after-release-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-log $system_dir/system-normal-after-release.jsonl --json --assert-system-scenario normal-after-release --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel" \
  .build/debug/nape-gesture analyze-log "$system_dir/system-normal-after-release.jsonl" --json --assert-system-scenario normal-after-release --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel

run_combined_success \
  "移行前kill-switch診断（完成判定外）" \
  "$system_dir/system-gesture-wheel-then-kill-switch.log" \
  ".build/debug/nape-gesture system-test run --scenario gesture-wheel-then-kill-switch --dry-run --log-json --out $system_dir/system-gesture-wheel-then-kill-switch.jsonl" \
  .build/debug/nape-gesture system-test run --scenario gesture-wheel-then-kill-switch --dry-run --log-json --out "$system_dir/system-gesture-wheel-then-kill-switch.jsonl"

run_split_success \
  "移行前kill-switch解析（完成判定外）" \
  "$system_dir/system-gesture-wheel-then-kill-switch-analysis.json" \
  "$system_dir/system-gesture-wheel-then-kill-switch-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-log $system_dir/system-gesture-wheel-then-kill-switch.jsonl --json --assert-system-scenario gesture-wheel-then-kill-switch --assert-kill-switch-shortcut --assert-gesture-before-kill-switch" \
  .build/debug/nape-gesture analyze-log "$system_dir/system-gesture-wheel-then-kill-switch.jsonl" --json --assert-system-scenario gesture-wheel-then-kill-switch --assert-kill-switch-shortcut --assert-gesture-before-kill-switch

run_split_success \
  "sample scroll compare-log" \
  "$fixtures_dir/compare-sample-scroll.txt" \
  "$fixtures_dir/compare-sample-scroll.stderr.log" \
  ".build/debug/nape-gesture compare-log Fixtures/sample-trackpad-scroll-log.jsonl Fixtures/sample-generated-scroll-log.jsonl" \
  .build/debug/nape-gesture compare-log Fixtures/sample-trackpad-scroll-log.jsonl Fixtures/sample-generated-scroll-log.jsonl

run_split_success \
  "sample tuning derive-parameters assert-complete" \
  "$fixtures_dir/derive-sample-tuning.json" \
  "$fixtures_dir/derive-sample-tuning.stderr.log" \
  ".build/debug/nape-gesture derive-parameters Fixtures/sample-tuning-trackpad-log.jsonl --json --assert-complete" \
  .build/debug/nape-gesture derive-parameters Fixtures/sample-tuning-trackpad-log.jsonl --json --assert-complete

run_split_expected_failure \
  "incomplete tuning derive-parameters assert-complete" \
  "$fixtures_dir/derive-incomplete-tuning.json" \
  "$fixtures_dir/derive-incomplete-tuning.stderr.log" \
  ".build/debug/nape-gesture derive-parameters Fixtures/sample-log.jsonl --json --assert-complete" \
  .build/debug/nape-gesture derive-parameters Fixtures/sample-log.jsonl --json --assert-complete

run_split_expected_failure \
  "synthetic timestamp tuning derive-parameters assert-complete" \
  "$fixtures_dir/derive-synthetic-timestamp-tuning.json" \
  "$fixtures_dir/derive-synthetic-timestamp-tuning.stderr.log" \
  ".build/debug/nape-gesture derive-parameters Fixtures/synthetic-timestamp-tuning-trackpad-log.jsonl --json --assert-complete" \
  .build/debug/nape-gesture derive-parameters Fixtures/synthetic-timestamp-tuning-trackpad-log.jsonl --json --assert-complete

run_split_success \
  "sample HID analyze-hid-log" \
  "$fixtures_dir/analyze-sample-hid.txt" \
  "$fixtures_dir/analyze-sample-hid.stderr.log" \
  ".build/debug/nape-gesture analyze-hid-log Fixtures/sample-hid-log.jsonl" \
  .build/debug/nape-gesture analyze-hid-log Fixtures/sample-hid-log.jsonl

sample_target_stable_id="vendor=123;product=456;manufacturer=example;name=nape-pro-mouse;transport=bluetooth"

run_split_success \
  "sample association analyze-association" \
  "$fixtures_dir/analyze-sample-association.json" \
  "$fixtures_dir/analyze-sample-association.stderr.log" \
  ".build/debug/nape-gesture analyze-association Fixtures/sample-association-hid-log.jsonl Fixtures/sample-association-event-log.jsonl --window 0.12 --json" \
  .build/debug/nape-gesture analyze-association Fixtures/sample-association-hid-log.jsonl Fixtures/sample-association-event-log.jsonl --window 0.12 --json

run_split_success \
  "clean association assert-valid-window" \
  "$fixtures_dir/clean-association-analysis.json" \
  "$fixtures_dir/clean-association-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-association Fixtures/sample-association-hid-log.jsonl Fixtures/clean-association-event-log.jsonl --window 0.12 --target-stable-id $sample_target_stable_id --json --assert-valid-window" \
  .build/debug/nape-gesture analyze-association Fixtures/sample-association-hid-log.jsonl Fixtures/clean-association-event-log.jsonl --window 0.12 --target-stable-id "$sample_target_stable_id" --json --assert-valid-window

run_split_expected_failure \
  "sample association assert-valid-window" \
  "$fixtures_dir/sample-association-assert-valid-window.json" \
  "$fixtures_dir/sample-association-assert-valid-window.stderr.log" \
  ".build/debug/nape-gesture analyze-association Fixtures/sample-association-hid-log.jsonl Fixtures/sample-association-event-log.jsonl --window 0.12 --target-stable-id $sample_target_stable_id --json --assert-valid-window" \
  .build/debug/nape-gesture analyze-association Fixtures/sample-association-hid-log.jsonl Fixtures/sample-association-event-log.jsonl --window 0.12 --target-stable-id "$sample_target_stable_id" --json --assert-valid-window

run_split_expected_failure \
  "empty association HID assert-valid-window" \
  "$fixtures_dir/empty-association-assert-valid-window.json" \
  "$fixtures_dir/empty-association-assert-valid-window.stderr.log" \
  ".build/debug/nape-gesture analyze-association Fixtures/empty-association-hid-log.jsonl Fixtures/clean-association-event-log.jsonl --window 0.12 --target-stable-id $sample_target_stable_id --json --assert-valid-window" \
  .build/debug/nape-gesture analyze-association Fixtures/empty-association-hid-log.jsonl Fixtures/clean-association-event-log.jsonl --window 0.12 --target-stable-id "$sample_target_stable_id" --json --assert-valid-window

run_split_expected_failure \
  "scroll mismatch association assert-valid-window" \
  "$fixtures_dir/scroll-mismatch-association-assert-valid-window.json" \
  "$fixtures_dir/scroll-mismatch-association-assert-valid-window.stderr.log" \
  ".build/debug/nape-gesture analyze-association Fixtures/association-scroll-mismatch-hid-log.jsonl Fixtures/association-scroll-mismatch-event-log.jsonl --window 0.12 --target-stable-id $sample_target_stable_id --json --assert-valid-window" \
  .build/debug/nape-gesture analyze-association Fixtures/association-scroll-mismatch-hid-log.jsonl Fixtures/association-scroll-mismatch-event-log.jsonl --window 0.12 --target-stable-id "$sample_target_stable_id" --json --assert-valid-window

run_split_expected_failure \
  "AC Pan association assert-valid-window" \
  "$fixtures_dir/ac-pan-association-assert-valid-window.json" \
  "$fixtures_dir/ac-pan-association-assert-valid-window.stderr.log" \
  ".build/debug/nape-gesture analyze-association Fixtures/association-ac-pan-hid-log.jsonl Fixtures/association-ac-pan-event-log.jsonl --window 0.12 --target-stable-id $sample_target_stable_id --json --assert-valid-window" \
  .build/debug/nape-gesture analyze-association Fixtures/association-ac-pan-hid-log.jsonl Fixtures/association-ac-pan-event-log.jsonl --window 0.12 --target-stable-id "$sample_target_stable_id" --json --assert-valid-window

run_split_expected_failure \
  "button mismatch association assert-valid-window" \
  "$fixtures_dir/button-mismatch-association-assert-valid-window.json" \
  "$fixtures_dir/button-mismatch-association-assert-valid-window.stderr.log" \
  ".build/debug/nape-gesture analyze-association Fixtures/association-button-mismatch-hid-log.jsonl Fixtures/association-button-mismatch-event-log.jsonl --window 0.12 --target-stable-id $sample_target_stable_id --json --assert-valid-window" \
  .build/debug/nape-gesture analyze-association Fixtures/association-button-mismatch-hid-log.jsonl Fixtures/association-button-mismatch-event-log.jsonl --window 0.12 --target-stable-id "$sample_target_stable_id" --json --assert-valid-window

run_split_expected_failure \
  "non-target association assert-valid-window" \
  "$fixtures_dir/non-target-association-assert-valid-window.json" \
  "$fixtures_dir/non-target-association-assert-valid-window.stderr.log" \
  ".build/debug/nape-gesture analyze-association Fixtures/association-non-target-hid-log.jsonl Fixtures/association-non-target-event-log.jsonl --window 0.12 --target-stable-id $sample_target_stable_id --json --assert-valid-window" \
  .build/debug/nape-gesture analyze-association Fixtures/association-non-target-hid-log.jsonl Fixtures/association-non-target-event-log.jsonl --window 0.12 --target-stable-id "$sample_target_stable_id" --json --assert-valid-window

run_split_expected_failure \
  "mixed device association assert-valid-window" \
  "$fixtures_dir/mixed-device-association-assert-valid-window.json" \
  "$fixtures_dir/mixed-device-association-assert-valid-window.stderr.log" \
  ".build/debug/nape-gesture analyze-association Fixtures/association-mixed-device-hid-log.jsonl Fixtures/association-mixed-device-event-log.jsonl --window 0.12 --target-stable-id $sample_target_stable_id --json --assert-valid-window" \
  .build/debug/nape-gesture analyze-association Fixtures/association-mixed-device-hid-log.jsonl Fixtures/association-mixed-device-event-log.jsonl --window 0.12 --target-stable-id "$sample_target_stable_id" --json --assert-valid-window

run_split_success \
  "clean target log assert-no-leaks" \
  "$fixtures_dir/clean-target-log-analysis.json" \
  "$fixtures_dir/clean-target-log-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/clean-target-log.jsonl --json --assert-no-leaks" \
  .build/debug/nape-gesture analyze-target-log Fixtures/clean-target-log.jsonl --json --assert-no-leaks

run_split_success \
  "clean target log assert-has-generated-event" \
  "$fixtures_dir/clean-target-log-generated-analysis.json" \
  "$fixtures_dir/clean-target-log-generated-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/clean-target-log.jsonl --json --assert-has-generated-event" \
  .build/debug/nape-gesture analyze-target-log Fixtures/clean-target-log.jsonl --json --assert-has-generated-event

run_split_expected_failure \
  "leaky target log assert-no-leaks" \
  "$fixtures_dir/leaky-target-log-analysis.json" \
  "$fixtures_dir/leaky-target-log-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/leaky-target-log.jsonl --json --assert-no-leaks" \
  .build/debug/nape-gesture analyze-target-log Fixtures/leaky-target-log.jsonl --json --assert-no-leaks

run_split_expected_failure \
  "no generated target log assert-has-generated-event" \
  "$fixtures_dir/no-generated-target-log-analysis.json" \
  "$fixtures_dir/no-generated-target-log.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/no-generated-target-log.jsonl --json --assert-no-leaks --assert-has-generated-event" \
  .build/debug/nape-gesture analyze-target-log Fixtures/no-generated-target-log.jsonl --json --assert-no-leaks --assert-has-generated-event

run_split_success \
  "normal input target log assert-has-unmarked-click-drag-wheel" \
  "$fixtures_dir/normal-input-target-log-analysis.json" \
  "$fixtures_dir/normal-input-target-log-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/normal-input-target-log.jsonl --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel" \
  .build/debug/nape-gesture analyze-target-log Fixtures/normal-input-target-log.jsonl --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel

run_split_expected_failure \
  "normal input missing click target log assert-has-unmarked-click-drag-wheel" \
  "$fixtures_dir/normal-input-missing-click-target-log-analysis.json" \
  "$fixtures_dir/normal-input-missing-click-target-log-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/normal-input-missing-click-target-log.jsonl --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel" \
  .build/debug/nape-gesture analyze-target-log Fixtures/normal-input-missing-click-target-log.jsonl --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel

run_split_expected_failure \
  "normal input missing drag target log assert-has-unmarked-click-drag-wheel" \
  "$fixtures_dir/normal-input-missing-drag-target-log-analysis.json" \
  "$fixtures_dir/normal-input-missing-drag-target-log-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/normal-input-missing-drag-target-log.jsonl --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel" \
  .build/debug/nape-gesture analyze-target-log Fixtures/normal-input-missing-drag-target-log.jsonl --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel

run_split_expected_failure \
  "normal input missing wheel target log assert-has-unmarked-click-drag-wheel" \
  "$fixtures_dir/normal-input-missing-wheel-target-log-analysis.json" \
  "$fixtures_dir/normal-input-missing-wheel-target-log-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/normal-input-missing-wheel-target-log.jsonl --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel" \
  .build/debug/nape-gesture analyze-target-log Fixtures/normal-input-missing-wheel-target-log.jsonl --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel

run_split_success \
  "gesture target log assert-has-gesture" \
  "$fixtures_dir/gesture-target-log-analysis.json" \
  "$fixtures_dir/gesture-target-log-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/gesture-target-log.jsonl --json --assert-has-gesture" \
  .build/debug/nape-gesture analyze-target-log Fixtures/gesture-target-log.jsonl --json --assert-has-gesture

run_split_success \
  "HID devices all JSON" \
  "$hid_dir/devices-all.json" \
  "$hid_dir/devices-all.stderr.log" \
  ".build/debug/nape-gesture devices --all --json" \
  .build/debug/nape-gesture devices --all --json

cat >> "$summary_file" <<EOF

## 未完了の証跡

- Nape Pro 実機の接続、HID 識別、操作ログ
- 純正トラックパッドの2 / 3 / 4本指について、縦・横・斜め・軸変更・方向反転・速度差・terminalを同一schemaで収録
- Nape Pro元mouse入力と生成eventのfinger count、X/Y量、符号、sample順、timestamp、phase、terminal対応を比較
- TCC のアクセシビリティ / 入力監視許可操作
- 2 / 3 / 4本指入力を受けたmacOS / applicationの画面結果を、低レベルcontractとは別に実測
- Issue #146でmagnificationが固定finger-countと単一X/Y量から表現可能かを判定
- \`run\`、実イベント投稿、target 実測、常駐 CPU、入力遅延
- Developer ID 署名、公証、stapler、Gatekeeper 評価

EOF

if [ "$failure_count" -eq 0 ]; then
  cat >> "$summary_file" <<EOF
## 総合結果

機械証跡の収集は成功しました。
ただし、上記の未完了項目は完成扱いにしません。
EOF
  printf '%s\n' "機械証跡の収集は成功しました: $artifact_root"
  exit 0
fi

cat >> "$summary_file" <<EOF
## 総合結果

機械証跡の収集は未完了です。
失敗したログを確認し、根本原因を解消してから再実行してください。

確認対象:
\`\`\`text
$failed_logs
\`\`\`
EOF

printf '%s\n' "機械証跡の収集は未完了です。summary を確認してください: $summary_file" >&2
printf '%s\n' "確認対象ログ:" >&2
printf '%s\n' "$failed_logs" >&2
exit 1
