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
doctor_dir="$artifact_root/doctor-and-performance"
system_dir="$artifact_root/system-test-dry-run"
fixtures_dir="$artifact_root/fixtures-analysis"
hid_dir="$artifact_root/hid-inventory"

config_path="$doctor_dir/nape-gesture.config.json"

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
  "検証用設定作成" \
  "$doctor_dir/init-config.log" \
  ".build/debug/nape-gesture init-config --allow-unmatched --out $config_path" \
  .build/debug/nape-gesture init-config --allow-unmatched --out "$config_path"

run_split_success \
  "doctor JSON" \
  "$doctor_dir/doctor-debug.json" \
  "$doctor_dir/doctor-debug.stderr.log" \
  ".build/debug/nape-gesture doctor --config $config_path --benchmark-events 50000 --json" \
  .build/debug/nape-gesture doctor --config "$config_path" --benchmark-events 50000 --json

run_split_success \
  "doctor HID probe JSON" \
  "$doctor_dir/doctor-hid-probe-debug.json" \
  "$doctor_dir/doctor-hid-probe-debug.stderr.log" \
  ".build/debug/nape-gesture doctor --config $config_path --probe-hid --benchmark-events 1000 --json" \
  .build/debug/nape-gesture doctor --config "$config_path" --probe-hid --benchmark-events 1000 --json

run_split_success \
  "benchmark JSON" \
  "$doctor_dir/benchmark-debug.json" \
  "$doctor_dir/benchmark-debug.stderr.log" \
  ".build/debug/nape-gesture benchmark --events 200000 --json" \
  .build/debug/nape-gesture benchmark --events 200000 --json

run_combined_success \
  "system-test list" \
  "$system_dir/system-test-list.txt" \
  ".build/debug/nape-gesture system-test list" \
  .build/debug/nape-gesture system-test list

for scenario in space-left space-right mission-control horizontal-scroll; do
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
    "system-test $scenario analyze-log" \
    "$system_dir/system-$scenario-analysis.txt" \
    "$system_dir/system-$scenario-analysis.stderr.log" \
    ".build/debug/nape-gesture analyze-log $system_dir/system-$scenario.jsonl --json" \
    .build/debug/nape-gesture analyze-log "$system_dir/system-$scenario.jsonl" --json
done

run_split_success \
  "generate-scroll space-right dry-run JSON Lines" \
  "$system_dir/generated-space-right.jsonl" \
  "$system_dir/generated-space-right.stderr.log" \
  ".build/debug/nape-gesture generate-scroll --x 1200 --y 0 --steps 30 --mode space-right --phase auto --momentum-steps 8 --dry-run --log-json" \
  .build/debug/nape-gesture generate-scroll --x 1200 --y 0 --steps 30 --mode space-right --phase auto --momentum-steps 8 --dry-run --log-json

run_split_success \
  "generate-scroll space-right analyze-log" \
  "$system_dir/generated-space-right-analysis.txt" \
  "$system_dir/generated-space-right-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-log $system_dir/generated-space-right.jsonl" \
  .build/debug/nape-gesture analyze-log "$system_dir/generated-space-right.jsonl"

run_split_success \
  "sample scroll compare-log" \
  "$fixtures_dir/compare-sample-scroll.txt" \
  "$fixtures_dir/compare-sample-scroll.stderr.log" \
  ".build/debug/nape-gesture compare-log Fixtures/sample-trackpad-scroll-log.jsonl Fixtures/sample-generated-scroll-log.jsonl" \
  .build/debug/nape-gesture compare-log Fixtures/sample-trackpad-scroll-log.jsonl Fixtures/sample-generated-scroll-log.jsonl

run_split_success \
  "sample tuning derive-parameters" \
  "$fixtures_dir/derive-sample-tuning.json" \
  "$fixtures_dir/derive-sample-tuning.stderr.log" \
  ".build/debug/nape-gesture derive-parameters Fixtures/sample-tuning-trackpad-log.jsonl --json" \
  .build/debug/nape-gesture derive-parameters Fixtures/sample-tuning-trackpad-log.jsonl --json

run_split_success \
  "sample HID analyze-hid-log" \
  "$fixtures_dir/analyze-sample-hid.txt" \
  "$fixtures_dir/analyze-sample-hid.stderr.log" \
  ".build/debug/nape-gesture analyze-hid-log Fixtures/sample-hid-log.jsonl" \
  .build/debug/nape-gesture analyze-hid-log Fixtures/sample-hid-log.jsonl

run_split_success \
  "sample association analyze-association" \
  "$fixtures_dir/analyze-sample-association.json" \
  "$fixtures_dir/analyze-sample-association.stderr.log" \
  ".build/debug/nape-gesture analyze-association Fixtures/sample-association-hid-log.jsonl Fixtures/sample-association-event-log.jsonl --window 0.12 --json" \
  .build/debug/nape-gesture analyze-association Fixtures/sample-association-hid-log.jsonl Fixtures/sample-association-event-log.jsonl --window 0.12 --json

run_split_success \
  "clean target log assert-no-leaks" \
  "$fixtures_dir/clean-target-log-analysis.json" \
  "$fixtures_dir/clean-target-log-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/clean-target-log.jsonl --json --assert-no-leaks" \
  .build/debug/nape-gesture analyze-target-log Fixtures/clean-target-log.jsonl --json --assert-no-leaks

run_split_expected_failure \
  "leaky target log assert-no-leaks" \
  "$fixtures_dir/leaky-target-log-analysis.json" \
  "$fixtures_dir/leaky-target-log-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/leaky-target-log.jsonl --json --assert-no-leaks" \
  .build/debug/nape-gesture analyze-target-log Fixtures/leaky-target-log.jsonl --json --assert-no-leaks

run_split_success \
  "normal input target log assert-has-unmarked-input" \
  "$fixtures_dir/normal-input-target-log-analysis.json" \
  "$fixtures_dir/normal-input-target-log-analysis.stderr.log" \
  ".build/debug/nape-gesture analyze-target-log Fixtures/normal-input-target-log.jsonl --json --assert-has-unmarked-input" \
  .build/debug/nape-gesture analyze-target-log Fixtures/normal-input-target-log.jsonl --json --assert-has-unmarked-input

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
- Issue #10 の Safari / 対応アプリでのページ戻る、進む、ズーム、横スクロール画面挙動実測
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
