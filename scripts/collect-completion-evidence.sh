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

artifact_root=${NAPE_COMPLETION_ARTIFACT_ROOT:-"artifacts/completion/$(date +%F)/machine-evidence"}
safari_runtime_artifact_root=${NAPE_SAFARI_SCROLL_RUNTIME_ARTIFACT_ROOT:-}
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
- 対象: 実機、TCC 操作、実イベント投稿なしで取得できる機械証跡

## 注意

このスクリプトで埋められるのは機械証跡だけです。
Nape Pro 実機、純正トラックパッド、TCC、Spaces / Mission Control の画面挙動、公証、Developer ID 署名は未完了のままです。

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

build_dir="$artifact_root/build-and-tests"
bundle_dir="$artifact_root/bundle"
gui_dir="$artifact_root/gui-smoke"
provenance_dir="$artifact_root/provenance"
doctor_dir="$artifact_root/doctor-and-performance"
system_dir="$artifact_root/system-test-dry-run"
fixtures_dir="$artifact_root/fixtures-analysis"
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
  "イベント時刻 Date epoch 混入ガード" \
  "$provenance_dir/monotonic-event-time-guard.log" \
  "CGEvent 入力、慣性、投稿経路に Date().timeIntervalSince1970 がないことを確認" \
  sh -c "if git grep -n -F 'Date().timeIntervalSince1970' -- Sources/nape-gesture/CGEventUtilities.swift Sources/nape-gesture/NapeGestureDaemon.swift Sources/nape-gesture/EventPoster.swift Sources/nape-gesture/GenerateScrollCommand.swift Sources/nape-gesture/SystemBehaviorTestCommand.swift; then exit 1; fi"

run_combined_success \
  "debug build" \
  "$build_dir/swift-build.log" \
  "swift build --scratch-path .build" \
  swift build --scratch-path .build

run_combined_success \
  "core tests" \
  "$build_dir/core-tests.log" \
  ".build/debug/nape-gesture-core-tests" \
  .build/debug/nape-gesture-core-tests

run_combined_success \
  "Safari scroll probe contract" \
  "$build_dir/safari-scroll-probe-contract.log" \
  "python3 scripts/check-safari-scroll-probe-contract.py" \
  python3 scripts/check-safari-scroll-probe-contract.py

run_combined_success \
  "Safari scroll probe WebKit render contract" \
  "$build_dir/safari-scroll-probe-render.log" \
  "swift scripts/check-safari-scroll-probe-render.swift" \
  swift scripts/check-safari-scroll-probe-render.swift

run_combined_success \
  "Safari runtime evidence evaluator tests" \
  "$build_dir/safari-scroll-runtime-evidence-tests.log" \
  "python3 scripts/check-safari-scroll-runtime-evidence-tests.py" \
  python3 scripts/check-safari-scroll-runtime-evidence-tests.py

safari_runtime_unfinished="- Safari runtime artifact 未指定。NAPE_SAFARI_SCROLL_RUNTIME_ARTIFACT_ROOT で最終証跡 root を指定して評価する"

run_combined_success \
  "CGEvent scroll probe typecheck" \
  "$build_dir/probe-cgevent-scroll-delivery-typecheck.log" \
  "swiftc -typecheck scripts/probe-cgevent-scroll-delivery.swift" \
  swiftc -typecheck scripts/probe-cgevent-scroll-delivery.swift

run_combined_success \
  "Codex host visibility helper typecheck" \
  "$build_dir/set-codex-host-visibility-typecheck.log" \
  "swiftc -typecheck scripts/set-codex-host-visibility.swift" \
  swiftc -typecheck scripts/set-codex-host-visibility.swift

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

if [ -n "$safari_runtime_artifact_root" ]; then
  candidate_commit=$(git rev-parse HEAD)
  run_split_success \
    "Safari runtime evidence artifact" \
    "$artifact_root/safari-scroll-runtime/evaluation.json" \
    "$artifact_root/safari-scroll-runtime/evaluation.stderr.log" \
    "python3 scripts/check-safari-scroll-runtime-evidence.py $safari_runtime_artifact_root --expected-commit $candidate_commit --app-executable .build/NapeGesture.app/Contents/MacOS/nape-gesture" \
    python3 scripts/check-safari-scroll-runtime-evidence.py \
      "$safari_runtime_artifact_root" \
      --expected-commit "$candidate_commit" \
      --app-executable .build/NapeGesture.app/Contents/MacOS/nape-gesture
  safari_runtime_unfinished=""
fi

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
  "grep -q runtimeReadiness $doctor_dir/doctor-debug.json && grep -q tccStatus $doctor_dir/doctor-debug.json && grep -q permissionTarget $doctor_dir/doctor-debug.json && grep -q grantRequired $doctor_dir/doctor-debug.json && grep -q targetDeviceDiagnostics $doctor_dir/doctor-debug.json" \
  sh -c "grep -q '\"runtimeReadiness\"' '$doctor_dir/doctor-debug.json' && grep -q '\"tccStatus\"' '$doctor_dir/doctor-debug.json' && grep -q '\"permissionTarget\"' '$doctor_dir/doctor-debug.json' && grep -q '\"grantRequired\"' '$doctor_dir/doctor-debug.json' && grep -q '\"targetDeviceDiagnostics\"' '$doctor_dir/doctor-debug.json'"

run_split_success \
  "doctor HID probe JSON" \
  "$doctor_dir/doctor-hid-probe-debug.json" \
  "$doctor_dir/doctor-hid-probe-debug.stderr.log" \
  ".build/debug/nape-gesture doctor --config $config_path --probe-hid --benchmark-events 1000 --json" \
  .build/debug/nape-gesture doctor --config "$config_path" --probe-hid --benchmark-events 1000 --json

run_combined_success \
  "doctor HID probe JSON runtimeReadiness / tccStatus / permissionTarget / targetDeviceDiagnostics field check" \
  "$doctor_dir/doctor-hid-probe-json-field-check.log" \
  "grep -q runtimeReadiness $doctor_dir/doctor-hid-probe-debug.json && grep -q tccStatus $doctor_dir/doctor-hid-probe-debug.json && grep -q permissionTarget $doctor_dir/doctor-hid-probe-debug.json && grep -q grantRequired $doctor_dir/doctor-hid-probe-debug.json && grep -q targetDeviceDiagnostics $doctor_dir/doctor-hid-probe-debug.json" \
  sh -c "grep -q '\"runtimeReadiness\"' '$doctor_dir/doctor-hid-probe-debug.json' && grep -q '\"tccStatus\"' '$doctor_dir/doctor-hid-probe-debug.json' && grep -q '\"permissionTarget\"' '$doctor_dir/doctor-hid-probe-debug.json' && grep -q '\"grantRequired\"' '$doctor_dir/doctor-hid-probe-debug.json' && grep -q '\"targetDeviceDiagnostics\"' '$doctor_dir/doctor-hid-probe-debug.json'"

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
  "system-test list" \
  "$system_dir/system-test-list.txt" \
  ".build/debug/nape-gesture system-test list" \
  .build/debug/nape-gesture system-test list

for scenario in space-left space-right mission-control horizontal-scroll page-back page-forward zoom-in zoom-out kill-switch; do
  if [ "$scenario" = "space-left" ] || [ "$scenario" = "space-right" ]; then
    run_combined_success \
      "system-test $scenario dry-run JSON Lines" \
      "$system_dir/system-$scenario.log" \
      ".build/debug/nape-gesture system-test run --scenario $scenario --target finder --dry-run --log-json --out $system_dir/system-$scenario.jsonl" \
      .build/debug/nape-gesture system-test run --scenario "$scenario" --target finder --dry-run --log-json --out "$system_dir/system-$scenario.jsonl"
  else
    run_combined_success \
      "system-test $scenario dry-run JSON Lines" \
      "$system_dir/system-$scenario.log" \
      ".build/debug/nape-gesture system-test run --scenario $scenario --dry-run --log-json --out $system_dir/system-$scenario.jsonl" \
      .build/debug/nape-gesture system-test run --scenario "$scenario" --dry-run --log-json --out "$system_dir/system-$scenario.jsonl"
  fi

  run_split_success \
    "system-test $scenario analyze-log assert-system-scenario / current-uptime" \
    "$system_dir/system-$scenario-analysis.txt" \
    "$system_dir/system-$scenario-analysis.stderr.log" \
    ".build/debug/nape-gesture analyze-log $system_dir/system-$scenario.jsonl --json --assert-current-uptime --assert-system-scenario $scenario" \
    .build/debug/nape-gesture analyze-log "$system_dir/system-$scenario.jsonl" --json --assert-current-uptime --assert-system-scenario "$scenario"
done

run_split_expected_failure \
  "system-test steps 上限超過" \
  "$system_dir/system-steps-overflow.stdout.log" \
  "$system_dir/system-steps-overflow.stderr.log" \
  ".build/debug/nape-gesture system-test run --scenario horizontal-scroll --steps 257 --dry-run --log-json" \
  .build/debug/nape-gesture system-test run --scenario horizontal-scroll --steps 257 --dry-run --log-json

run_combined_success \
  "system-test steps 上限超過の部分出力禁止" \
  "$system_dir/system-steps-overflow-assertion.log" \
  "steps上限超過時のstdoutが空であることを確認" \
  sh -c 'test ! -s "$1" && grep -Fq "最大値は 256" "$2"' \
  sh "$system_dir/system-steps-overflow.stdout.log" "$system_dir/system-steps-overflow.stderr.log"

run_split_expected_failure \
  "system-test 系列時間上限超過" \
  "$system_dir/system-duration-overflow.stdout.log" \
  "$system_dir/system-duration-overflow.stderr.log" \
  ".build/debug/nape-gesture system-test run --scenario horizontal-scroll --steps 3 --interval 20 --dry-run --log-json" \
  .build/debug/nape-gesture system-test run --scenario horizontal-scroll --steps 3 --interval 20 --dry-run --log-json

run_combined_success \
  "system-test 系列時間上限超過の部分出力禁止" \
  "$system_dir/system-duration-overflow-assertion.log" \
  "系列時間上限超過時のstdoutが空であることを確認" \
  sh -c 'test ! -s "$1" && grep -Fq "イベント列の最大時間は 30.0 秒" "$2"' \
  sh "$system_dir/system-duration-overflow.stdout.log" "$system_dir/system-duration-overflow.stderr.log"

system_atomic_output="$system_dir/system-derived-overflow-preserve.jsonl"
printf '%s\n' "existing-system-test-log" > "$system_atomic_output"
run_split_expected_failure \
  "system-test 派生速度 overflow" \
  "$system_dir/system-derived-overflow.stdout.log" \
  "$system_dir/system-derived-overflow.stderr.log" \
  ".build/debug/nape-gesture system-test run --scenario horizontal-scroll --amount 1e308 --steps 1 --interval 0.001 --dry-run --log-json --out $system_atomic_output" \
  .build/debug/nape-gesture system-test run --scenario horizontal-scroll --amount 1e308 --steps 1 --interval 0.001 --dry-run --log-json --out "$system_atomic_output"

run_combined_success \
  "system-test 派生値失敗の出力原子性" \
  "$system_dir/system-derived-overflow-assertion.log" \
  "派生速度overflow時のstdoutが空で既存出力が不変であることを確認" \
  sh -c 'test ! -s "$1" && grep -Fq "派生したスクロール量または速度が有限値ではありません" "$2" && test "$(cat "$3")" = "existing-system-test-log"' \
  sh "$system_dir/system-derived-overflow.stdout.log" "$system_dir/system-derived-overflow.stderr.log" "$system_atomic_output"

run_combined_success \
  "system-test normal-after-release dry-run JSON Lines" \
  "$system_dir/system-normal-after-release.log" \
  ".build/debug/nape-gesture system-test run --scenario normal-after-release --dry-run --log-json --out $system_dir/system-normal-after-release.jsonl" \
  .build/debug/nape-gesture system-test run --scenario normal-after-release --dry-run --log-json --out "$system_dir/system-normal-after-release.jsonl"

run_split_success \
  "system-test normal-after-release analyze-log assert-has-unmarked-click-drag-wheel" \
  "$system_dir/system-normal-after-release-analysis.json" \
  "$system_dir/system-normal-after-release-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-log $system_dir/system-normal-after-release.jsonl --json --assert-current-uptime --assert-system-scenario normal-after-release --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel" \
  .build/debug/nape-gesture analyze-log "$system_dir/system-normal-after-release.jsonl" --json --assert-current-uptime --assert-system-scenario normal-after-release --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel

run_combined_success \
  "system-test gesture-wheel-then-kill-switch dry-run JSON Lines" \
  "$system_dir/system-gesture-wheel-then-kill-switch.log" \
  ".build/debug/nape-gesture system-test run --scenario gesture-wheel-then-kill-switch --dry-run --log-json --out $system_dir/system-gesture-wheel-then-kill-switch.jsonl" \
  .build/debug/nape-gesture system-test run --scenario gesture-wheel-then-kill-switch --dry-run --log-json --out "$system_dir/system-gesture-wheel-then-kill-switch.jsonl"

run_split_success \
  "system-test gesture-wheel-then-kill-switch analyze-log assert-gesture-before-kill-switch" \
  "$system_dir/system-gesture-wheel-then-kill-switch-analysis.json" \
  "$system_dir/system-gesture-wheel-then-kill-switch-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-log $system_dir/system-gesture-wheel-then-kill-switch.jsonl --json --assert-current-uptime --assert-system-scenario gesture-wheel-then-kill-switch --assert-kill-switch-shortcut --assert-gesture-before-kill-switch" \
  .build/debug/nape-gesture analyze-log "$system_dir/system-gesture-wheel-then-kill-switch.jsonl" --json --assert-current-uptime --assert-system-scenario gesture-wheel-then-kill-switch --assert-kill-switch-shortcut --assert-gesture-before-kill-switch

run_split_success \
  "generate-scroll space-right dry-run JSON Lines" \
  "$system_dir/generated-space-right.jsonl" \
  "$system_dir/generated-space-right.stderr.log" \
  ".build/debug/nape-gesture generate-scroll --x 1200 --y 0 --steps 30 --mode space-right --phase auto --momentum-steps 8 --dry-run --log-json" \
  .build/debug/nape-gesture generate-scroll --x 1200 --y 0 --steps 30 --mode space-right --phase auto --momentum-steps 8 --dry-run --log-json

run_split_success \
  "generate-scroll space-right analyze-log current-uptime" \
  "$system_dir/generated-space-right-analysis.txt" \
  "$system_dir/generated-space-right-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-log $system_dir/generated-space-right.jsonl --assert-current-uptime" \
  .build/debug/nape-gesture analyze-log "$system_dir/generated-space-right.jsonl" --assert-current-uptime

run_split_expected_failure \
  "generate-scroll 派生値 overflow" \
  "$system_dir/generated-overflow.jsonl" \
  "$system_dir/generated-overflow.stderr.log" \
  ".build/debug/nape-gesture generate-scroll --x 1e308 --steps 1 --momentum-steps 1 --momentum-scale 2 --dry-run --log-json" \
  .build/debug/nape-gesture generate-scroll --x 1e308 --steps 1 --momentum-steps 1 --momentum-scale 2 --dry-run --log-json

run_combined_success \
  "generate-scroll overflow の部分出力禁止" \
  "$system_dir/generated-overflow-assertion.log" \
  "overflow時のstdoutが空でstderrに派生イベント失敗理由があることを確認" \
  sh -c 'test ! -s "$1" && grep -Fq "派生イベントが有限値ではない" "$2"' \
  sh "$system_dir/generated-overflow.jsonl" "$system_dir/generated-overflow.stderr.log"

run_split_expected_failure \
  "generate-scroll 後続timestamp変換不能" \
  "$system_dir/generated-unconvertible-timestamp.jsonl" \
  "$system_dir/generated-unconvertible-timestamp.stderr.log" \
  ".build/debug/nape-gesture generate-scroll --x 1 --steps 2 --interval 1e308 --dry-run --log-json" \
  .build/debug/nape-gesture generate-scroll --x 1 --steps 2 --interval 1e308 --dry-run --log-json

run_combined_success \
  "generate-scroll timestamp失敗の部分出力禁止" \
  "$system_dir/generated-unconvertible-timestamp-assertion.log" \
  "後続timestamp変換不能時のstdoutが空であることを確認" \
  sh -c 'test ! -s "$1" && grep -Fq "timestampを起動後nanosecondsへ変換できない" "$2"' \
  sh "$system_dir/generated-unconvertible-timestamp.jsonl" "$system_dir/generated-unconvertible-timestamp.stderr.log"

run_split_expected_failure \
  "epoch timestamp analyze-log assert-current-uptime" \
  "$fixtures_dir/epoch-timestamp-current-uptime.json" \
  "$fixtures_dir/epoch-timestamp-current-uptime.stderr.log" \
  ".build/debug/nape-gesture analyze-log Fixtures/epoch-timestamp-generated-scroll-log.jsonl --json --assert-current-uptime" \
  .build/debug/nape-gesture analyze-log Fixtures/epoch-timestamp-generated-scroll-log.jsonl --json --assert-current-uptime

run_combined_success \
  "generate-scroll CLI expected failure" \
  "$system_dir/generate-scroll-cli-expected-failure.log" \
  "sh scripts/check-generate-scroll-cli.sh .build/debug/nape-gesture" \
  sh scripts/check-generate-scroll-cli.sh .build/debug/nape-gesture

run_combined_success \
  "system-test 投稿結果の3状態契約" \
  "$system_dir/system-test-post-result.log" \
  "sh scripts/check-system-behavior-post-result.sh" \
  sh scripts/check-system-behavior-post-result.sh

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
- 純正トラックパッドでの実操作ログ
- TCC のアクセシビリティ / 入力監視許可操作
- Spaces / Mission Control の画面挙動実測
$safari_runtime_unfinished
- Issue #10 の時刻修正後 Safari / 対応アプリでのページ戻る、進む、ズーム、横スクロール CGEvent log と computer-use 画面挙動
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
