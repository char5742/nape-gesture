#!/bin/sh

# Issue #6 / #12 のうち、アクセシビリティ許可済み環境で実イベント経路を検証する証跡を収集する。
# 実行ビットは不要です。`sh scripts/collect-runtime-event-evidence.sh` で実行してください。

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

artifact_root=${NAPE_RUNTIME_EVENT_ARTIFACT_ROOT:-"artifacts/completion/$(date +%F)/runtime-event-evidence"}
use_app_bundle=${NAPE_RUNTIME_EVENT_USE_APP_BUNDLE:-0}
if [ "${NAPE_RUNTIME_EVENT_TOOL+x}" ]; then
  tool_path=$NAPE_RUNTIME_EVENT_TOOL
elif [ "$use_app_bundle" = "1" ]; then
  tool_path=".build/NapeGesture.app/Contents/MacOS/nape-gesture"
else
  tool_path=".build/debug/nape-gesture"
fi
commands_file="$artifact_root/commands.txt"
summary_file="$artifact_root/summary.md"
build_dir="$artifact_root/build"
doctor_dir="$artifact_root/doctor"
scenario_dir="$artifact_root/scenarios"
config_path="$doctor_dir/system-test-allow-unmatched.json"
failure_count=0
failed_logs=""

mkdir -p "$artifact_root"
: > "$commands_file"

cat > "$summary_file" <<EOF
# Runtime event 証跡サマリー

- 証跡 root: \`$artifact_root\`
- 実行日時: $(date '+%F %T %z')
- 対象: Issue #6 の元入力抑制、Issue #12 のキルスイッチ漏れ抑制、通常入力復帰
- 実行ツール: \`$tool_path\`

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

  return "$status"
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

  return "$status"
}

runtime_identity() {
  sed -n '/"runtimeIdentity" : {/,/}/p' "$doctor_dir/doctor-debug.json" \
    | sed 's/^/    /' >> "$summary_file"
}

hid_probe() {
  sed -n '/"hidProbe" : {/,/}/p' "$doctor_dir/doctor-debug.json" \
    | sed 's/^/    /' >> "$summary_file"
}

hid_probe_succeeded() {
  sed -n '/"hidProbe" : {/,/}/p' "$doctor_dir/doctor-debug.json" \
    | grep -q '"succeeded" : true'
}

tcc_accessibility_granted() {
  sed -n '/"accessibility" : {/,/}/p' "$doctor_dir/doctor-debug.json" \
    | grep -q '"status" : "granted"'
}

tcc_input_monitoring_granted() {
  sed -n '/"inputMonitoring" : {/,/}/p' "$doctor_dir/doctor-debug.json" \
    | grep -q '"status" : "granted"'
}

runtime_readiness() {
  sed -n '/"runtimeReadiness" : {/,/^  }/p' "$doctor_dir/doctor-debug.json" \
    | sed 's/^/    /' >> "$summary_file"
}

finish_summary() {
  if [ "$failure_count" -eq 0 ]; then
    cat >> "$summary_file" <<EOF

## 総合結果

Runtime event 証跡の収集は成功しました。
EOF
    printf '%s\n' "Runtime event 証跡の収集は成功しました: $artifact_root"
    exit 0
  fi

  cat >> "$summary_file" <<EOF

## 総合結果

Runtime event 証跡の収集は未完了です。
失敗したログを確認し、根本原因を解消してから再実行してください。

確認対象:
\`\`\`text
$failed_logs
\`\`\`
EOF

  printf '%s\n' "Runtime event 証跡の収集は未完了です。summary を確認してください: $summary_file" >&2
  printf '%s\n' "確認対象ログ:" >&2
  printf '%s\n' "$failed_logs" >&2
  exit 1
}

cleanup_processes() {
  if [ "${target_pid:-}" != "" ]; then
    kill "$target_pid" 2>/dev/null || true
    wait "$target_pid" 2>/dev/null || true
    target_pid=""
  fi
  if [ "${daemon_pid:-}" != "" ]; then
    kill "$daemon_pid" 2>/dev/null || true
    wait "$daemon_pid" 2>/dev/null || true
    daemon_pid=""
  fi
}

handle_interrupt() {
  cleanup_processes
  exit 130
}

wait_for_ready_file() {
  ready_file=$1
  attempts=0
  while [ "$attempts" -lt 80 ]; do
    if [ -f "$ready_file" ]; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 0.1
  done
  return 1
}

wait_for_daemon_started() {
  log_path=$1
  pid=$2
  attempts=0
  while [ "$attempts" -lt 80 ]; do
    if grep -q "nape-gesture を開始しました" "$log_path" 2>/dev/null; then
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      return 1
    fi
    attempts=$((attempts + 1))
    sleep 0.1
  done
  return 1
}

run_scenario_with_no_leaks() {
  scenario=$1
  title=$2

  dir="$scenario_dir/$scenario"
  target_log="$dir/target.jsonl"
  ready_file="$dir/target.ready.json"
  daemon_log="$dir/daemon.log"
  target_stdout="$dir/target.stdout.log"
  target_stderr="$dir/target.stderr.log"
  system_log="$dir/system-test.log"
  analysis_json="$dir/analyze-target-log.json"
  analysis_stderr="$dir/analyze-target-log.stderr.log"

  mkdir -p "$dir"
  rm -f "$target_log" "$ready_file"

  printf '%s\n' "実行中: $title"
  printf '$ %s run --config %s > %s 2>&1 &\n' "$tool_path" "$config_path" "$daemon_log" >> "$commands_file"
  "$tool_path" run --config "$config_path" > "$daemon_log" 2>&1 &
  daemon_pid=$!
  if ! wait_for_daemon_started "$daemon_log" "$daemon_pid"; then
    append_summary "失敗" "$title daemon 起動" "-" "$daemon_log"
    remember_failure "$daemon_log"
    cleanup_processes
    return
  fi

  printf '$ %s target --out %s --duration 5 --ready-file %s > %s 2> %s &\n' "$tool_path" "$target_log" "$ready_file" "$target_stdout" "$target_stderr" >> "$commands_file"
  "$tool_path" target --out "$target_log" --duration 5 --ready-file "$ready_file" > "$target_stdout" 2> "$target_stderr" &
  target_pid=$!

  if ! wait_for_ready_file "$ready_file"; then
    append_summary "失敗" "$title ready-file" "-" "$target_stdout / $target_stderr"
    remember_failure "$target_stdout / $target_stderr"
    cleanup_processes
    return
  fi

  printf '$ %s system-test run --scenario %s > %s 2>&1\n' "$tool_path" "$scenario" "$system_log" >> "$commands_file"
  "$tool_path" system-test run --scenario "$scenario" > "$system_log" 2>&1
  system_status=$?
  wait "$target_pid" 2>/dev/null || true
  target_pid=""
  cleanup_processes

  if [ "$system_status" -ne 0 ]; then
    append_summary "失敗" "$title system-test" "$system_status" "$system_log"
    remember_failure "$system_log"
    return
  fi

  if [ "$scenario" = "kill-switch" ] || [ "$scenario" = "gesture-wheel-then-kill-switch" ]; then
    if grep -q "キルスイッチによりジェスチャーを無効化しました" "$daemon_log"; then
      append_summary "成功" "$title daemon 停止ログ" "0" "$daemon_log"
    else
      append_summary "失敗" "$title daemon 停止ログ" "-" "$daemon_log"
      remember_failure "$daemon_log"
    fi
  fi

  if [ "$scenario" = "gesture-drag" ] || [ "$scenario" = "gesture-wheel" ] || [ "$scenario" = "gesture-wheel-then-kill-switch" ]; then
    printf '$ %s analyze-target-log %s --json --assert-no-leaks --assert-has-generated-event > %s 2> %s\n' "$tool_path" "$target_log" "$analysis_json" "$analysis_stderr" >> "$commands_file"
    "$tool_path" analyze-target-log "$target_log" --json --assert-no-leaks --assert-has-generated-event > "$analysis_json" 2> "$analysis_stderr"
  else
    printf '$ %s analyze-target-log %s --json --assert-no-leaks > %s 2> %s\n' "$tool_path" "$target_log" "$analysis_json" "$analysis_stderr" >> "$commands_file"
    "$tool_path" analyze-target-log "$target_log" --json --assert-no-leaks > "$analysis_json" 2> "$analysis_stderr"
  fi
  analysis_status=$?

  if [ "$analysis_status" -eq 0 ]; then
    append_summary "成功" "$title" "$analysis_status" "$analysis_json"
  else
    append_summary "失敗" "$title" "$analysis_status" "$analysis_json / $analysis_stderr"
    remember_failure "$analysis_json / $analysis_stderr"
  fi
}

run_normal_after_release() {
  scenario=normal-after-release
  title="normal-after-release 通常入力通過"
  dir="$scenario_dir/$scenario"
  target_log="$dir/target.jsonl"
  ready_file="$dir/target.ready.json"
  daemon_log="$dir/daemon.log"
  target_stdout="$dir/target.stdout.log"
  target_stderr="$dir/target.stderr.log"
  system_log="$dir/system-test.log"
  analysis_json="$dir/analyze-target-log.json"
  analysis_stderr="$dir/analyze-target-log.stderr.log"

  mkdir -p "$dir"
  rm -f "$target_log" "$ready_file"

  printf '%s\n' "実行中: $title"
  printf '$ %s run --config %s > %s 2>&1 &\n' "$tool_path" "$config_path" "$daemon_log" >> "$commands_file"
  "$tool_path" run --config "$config_path" > "$daemon_log" 2>&1 &
  daemon_pid=$!
  if ! wait_for_daemon_started "$daemon_log" "$daemon_pid"; then
    append_summary "失敗" "$title daemon 起動" "-" "$daemon_log"
    remember_failure "$daemon_log"
    cleanup_processes
    return
  fi

  printf '$ %s target --out %s --duration 5 --ready-file %s > %s 2> %s &\n' "$tool_path" "$target_log" "$ready_file" "$target_stdout" "$target_stderr" >> "$commands_file"
  "$tool_path" target --out "$target_log" --duration 5 --ready-file "$ready_file" > "$target_stdout" 2> "$target_stderr" &
  target_pid=$!

  if ! wait_for_ready_file "$ready_file"; then
    append_summary "失敗" "$title ready-file" "-" "$target_stdout / $target_stderr"
    remember_failure "$target_stdout / $target_stderr"
    cleanup_processes
    return
  fi

  printf '$ %s system-test run --scenario normal-after-release > %s 2>&1\n' "$tool_path" "$system_log" >> "$commands_file"
  "$tool_path" system-test run --scenario normal-after-release > "$system_log" 2>&1
  system_status=$?
  wait "$target_pid" 2>/dev/null || true
  target_pid=""
  cleanup_processes

  if [ "$system_status" -ne 0 ]; then
    append_summary "失敗" "$title system-test" "$system_status" "$system_log"
    remember_failure "$system_log"
    return
  fi

  printf '$ %s analyze-target-log %s --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel > %s 2> %s\n' "$tool_path" "$target_log" "$analysis_json" "$analysis_stderr" >> "$commands_file"
  "$tool_path" analyze-target-log "$target_log" --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel > "$analysis_json" 2> "$analysis_stderr"
  analysis_status=$?

  if [ "$analysis_status" -eq 0 ]; then
    append_summary "成功" "$title" "$analysis_status" "$analysis_json"
  else
    append_summary "失敗" "$title" "$analysis_status" "$analysis_json / $analysis_stderr"
    remember_failure "$analysis_json / $analysis_stderr"
  fi
}

trap cleanup_processes EXIT
trap handle_interrupt INT TERM

run_combined_success \
  "debug build" \
  "$build_dir/swift-build.log" \
  "swift build --scratch-path .build" \
  swift build --scratch-path .build || finish_summary

if [ "$use_app_bundle" = "1" ]; then
  run_combined_success \
    "runtime 用 release build" \
    "$build_dir/swift-build-release.log" \
    "swift build -c release --scratch-path .build" \
    swift build -c release --scratch-path .build || finish_summary

  run_combined_success \
    "runtime 用 .app 作成" \
    "$build_dir/bundle-app.log" \
    ".build/release/nape-gesture bundle-app --out .build/NapeGesture.app --replace" \
    .build/release/nape-gesture bundle-app --out .build/NapeGesture.app --replace || finish_summary

  run_combined_success \
    "runtime 用 .app 検証" \
    "$build_dir/verify-bundle.log" \
    ".build/release/nape-gesture verify-bundle .build/NapeGesture.app" \
    .build/release/nape-gesture verify-bundle .build/NapeGesture.app || finish_summary
fi

if [ ! -x "$tool_path" ]; then
  append_summary "失敗" "実行ツール確認" "-" "$tool_path"
  remember_failure "$tool_path"
  finish_summary
fi

run_combined_success \
  "検証用 allow-unmatched 設定作成" \
  "$doctor_dir/init-config.log" \
  "$tool_path init-config --allow-unmatched --out $config_path" \
  "$tool_path" init-config --allow-unmatched --out "$config_path" || finish_summary

run_split_success \
  "doctor JSON" \
  "$doctor_dir/doctor-debug.json" \
  "$doctor_dir/doctor-debug.stderr.log" \
  "$tool_path doctor --config $config_path --probe-hid --benchmark-events 1000 --json" \
  "$tool_path" doctor --config "$config_path" --probe-hid --benchmark-events 1000 --json || finish_summary

if ! tcc_accessibility_granted; then
  append_summary "外部ブロッカー" "Accessibility 未許可のため runtime event シナリオを未実行" "-" "$doctor_dir/doctor-debug.json"
  cat >> "$summary_file" <<EOF

## 外部ブロッカー

現在の実行主体はアクセシビリティ未許可です。
この状態では \`run\`、\`target\`、実イベント投稿を組み合わせた #6 / #12 の最終証跡は取得しません。

権限付与対象:
\`\`\`text
EOF
  runtime_identity
  cat >> "$summary_file" <<EOF
\`\`\`

HID 入力監視プローブ:
\`\`\`text
EOF
  hid_probe
  cat >> "$summary_file" <<EOF
\`\`\`

Runtime readiness:
\`\`\`text
EOF
  runtime_readiness
  cat >> "$summary_file" <<EOF
\`\`\`

システム設定で上記の実行主体へアクセシビリティ権限を付与し、プロセスを再起動してからこのスクリプトを再実行してください。
物理キー操作や目視判断は不要です。権限付与後は \`system-test\` の未マーク CGEvent 投稿と \`analyze-target-log\` の終了コードで判定します。通常入力通過はクリック / ドラッグ / ホイールが揃うことを機械判定します。

## 総合結果

Runtime event 証跡は未完了です。
ただし、未実行理由は macOS の TCC / アクセシビリティ権限という外部ブロッカーとして記録しました。
EOF
  printf '%s\n' "Runtime event 証跡は未完了です。Accessibility 未許可のため summary に外部ブロッカーを記録しました: $summary_file"
  exit 0
fi

if ! tcc_input_monitoring_granted || ! hid_probe_succeeded; then
  append_summary "外部ブロッカー" "入力監視プローブ未成功のため runtime event シナリオを未実行" "-" "$doctor_dir/doctor-debug.json"
  cat >> "$summary_file" <<EOF

## 外部ブロッカー

現在の実行主体は HID 入力監視プローブに成功していません。
この状態では \`run\` と \`system-test\` を組み合わせた #6 / #12 の最終証跡は取得しません。

権限付与対象:
\`\`\`text
EOF
  runtime_identity
  cat >> "$summary_file" <<EOF
\`\`\`

HID 入力監視プローブ:
\`\`\`text
EOF
  hid_probe
  cat >> "$summary_file" <<EOF
\`\`\`

Runtime readiness:
\`\`\`text
EOF
  runtime_readiness
  cat >> "$summary_file" <<EOF
\`\`\`

システム設定で上記の実行主体へ入力監視権限を付与し、プロセスを再起動してからこのスクリプトを再実行してください。
物理操作や目視判断は不要です。入力監視プローブが成功すれば、runtime event シナリオは \`analyze-target-log\` の終了コードで判定します。

## 総合結果

Runtime event 証跡は未完了です。
ただし、未実行理由は macOS の TCC / 入力監視権限という外部ブロッカーとして記録しました。
EOF
  printf '%s\n' "Runtime event 証跡は未完了です。入力監視プローブ未成功のため summary に外部ブロッカーを記録しました: $summary_file"
  exit 0
fi

run_scenario_with_no_leaks gesture-drag "gesture-drag 元入力漏れなし"
run_scenario_with_no_leaks gesture-wheel "gesture-wheel 元入力漏れなし"
run_scenario_with_no_leaks kill-switch "kill-switch キー漏れなし"
run_scenario_with_no_leaks gesture-wheel-then-kill-switch "gesture-wheel-then-kill-switch 暴走中停止"
run_normal_after_release

finish_summary
