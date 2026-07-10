#!/bin/sh

# sample-cpu が数値 PID だけで別の実行主体を合格させないことを確認する。
# 実行ビットは不要です。sh scripts/test-sample-cpu.sh で実行してください。

set -u

tool_path=${1:-.build/debug/nape-gesture}
case "$tool_path" in
  /*) ;;
  *) tool_path="$PWD/$tool_path" ;;
esac
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
self_exec_fixture="$script_directory/fixtures/sample-cpu-self-exec.sh"

if [ ! -x "$tool_path" ]; then
  printf '%s\n' "sample-cpu テスト対象が見つからないか実行できません: $tool_path" >&2
  exit 1
fi

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/nape-sample-cpu-tests.XXXXXX") || exit 1
child_pids=""

remember_child() {
  child_pids="$child_pids $1"
}

forget_child() {
  forgotten_pid=$1
  remaining_pids=""
  for remembered_pid in $child_pids; do
    if [ "$remembered_pid" != "$forgotten_pid" ]; then
      remaining_pids="$remaining_pids $remembered_pid"
    fi
  done
  child_pids=$remaining_pids
}

stop_child() {
  child_pid=$1
  /usr/bin/pkill -TERM -P "$child_pid" 2>/dev/null || true
  kill "$child_pid" 2>/dev/null || true
  wait "$child_pid" 2>/dev/null || true
  forget_child "$child_pid"
}

cleanup() {
  for child_pid in $child_pids; do
    stop_child "$child_pid"
  done
  rm -rf "$temporary_directory"
}

fail() {
  printf '%s\n' "sample-cpu テスト失敗: $1" >&2
  exit 1
}

json_value() {
  json_path=$1
  key_path=$2
  /usr/bin/plutil -extract "$key_path" raw -o - "$json_path"
}

wait_for_file() {
  wait_path=$1
  wait_description=$2
  wait_attempt=0
  while [ ! -f "$wait_path" ]; do
    wait_attempt=$((wait_attempt + 1))
    if [ "$wait_attempt" -ge 500 ]; then
      fail "$wait_description が準備完了になりません"
    fi
    /bin/sleep 0.01
  done
}

resolve_process_executable() {
  resolve_pid=$1
  /usr/bin/swift -e '
    import Darwin

    let pid = Int32(CommandLine.arguments[1])!
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let result = proc_pidpath(pid, &path, UInt32(path.count))
    if result <= 0 {
        exit(1)
    }
    print(String(cString: path))
  ' "$resolve_pid"
}

cli_failure_count=0
expect_cli_failure() {
  cli_failure_label=$1
  cli_failure_expected=$2
  shift 2
  cli_failure_count=$((cli_failure_count + 1))
  cli_failure_stdout="$temporary_directory/cli-failure-$cli_failure_count.stdout.log"
  cli_failure_stderr="$temporary_directory/cli-failure-$cli_failure_count.stderr.log"

  if "$tool_path" sample-cpu "$@" > "$cli_failure_stdout" 2> "$cli_failure_stderr"; then
    fail "$cli_failure_label が合格しました"
  fi
  grep -Fq -- "$cli_failure_expected" "$cli_failure_stderr" \
    || fail "$cli_failure_label のエラー理由が不明確です"
  if grep -Fq 'Fatal error' "$cli_failure_stderr"; then
    fail "$cli_failure_label で Fatal error が発生しました"
  fi
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if [ ! -r "$self_exec_fixture" ]; then
  fail "同一 path exec fixture を読み取れません: $self_exec_fixture"
fi

expect_cli_failure \
  "pid_t 上限超過" \
  '--pid の値が不正です: 2147483648' \
  --pid 2147483648 --expected-executable /bin/sleep --duration 0.1 --interval 0.1 --json
expect_cli_failure \
  "duration inf" \
  '--duration の値が不正です: inf' \
  --pid 1 --expected-executable /bin/sleep --duration inf --interval 1 --json
expect_cli_failure \
  "duration nan" \
  '--duration の値が不正です: nan' \
  --pid 1 --expected-executable /bin/sleep --duration nan --interval 1 --json
expect_cli_failure \
  "duration ゼロ" \
  '--duration の値が不正です: 0' \
  --pid 1 --expected-executable /bin/sleep --duration 0 --interval 1 --json
expect_cli_failure \
  "duration 負値" \
  '--duration の値が不正です: -1' \
  --pid 1 --expected-executable /bin/sleep --duration -1 --interval 1 --json
expect_cli_failure \
  "duration 上限超過" \
  '--duration の値が不正です: 86401' \
  --pid 1 --expected-executable /bin/sleep --duration 86401 --interval 1 --json
expect_cli_failure \
  "interval inf" \
  '--interval の値が不正です: inf' \
  --pid 1 --expected-executable /bin/sleep --duration 1 --interval inf --json
expect_cli_failure \
  "interval nan" \
  '--interval の値が不正です: nan' \
  --pid 1 --expected-executable /bin/sleep --duration 1 --interval nan --json
expect_cli_failure \
  "interval ゼロ" \
  '--interval の値が不正です: 0' \
  --pid 1 --expected-executable /bin/sleep --duration 1 --interval 0 --json
expect_cli_failure \
  "interval 負値" \
  '--interval の値が不正です: -1' \
  --pid 1 --expected-executable /bin/sleep --duration 1 --interval -1 --json
expect_cli_failure \
  "非有限 duration/interval 比率" \
  '--duration / --interval の値が不正です: 有限な比率ではありません' \
  --pid 1 --expected-executable /bin/sleep --duration 1 --interval 5e-324 --json
expect_cli_failure \
  "sample 数上限超過" \
  '--duration / --interval の値が不正です: 推定 sample 数が上限 100000 を超えます' \
  --pid 1 --expected-executable /bin/sleep --duration 86400 --interval 0.000001 --json
expect_cli_failure \
  "pid 値欠損" \
  '--pid の値がありません。' \
  --pid --expected-executable /bin/sleep --json
expect_cli_failure \
  "ready-file 値欠損" \
  '--ready-file の値がありません。' \
  --pid 1 --expected-executable /bin/sleep --ready-file --json
expect_cli_failure \
  "duration 重複" \
  '--duration の値が不正です: 重複して指定されています' \
  --pid 1 --expected-executable /bin/sleep --duration 1 --duration 2 --json
expect_cli_failure \
  "ready-file 重複" \
  '--ready-file の値が不正です: 重複して指定されています' \
  --pid 1 --expected-executable /bin/sleep \
  --ready-file "$temporary_directory/ready-a" --ready-file "$temporary_directory/ready-b" --json
expect_cli_failure \
  "json flag 重複" \
  '--json の値が不正です: 重複して指定されています' \
  --pid 1 --expected-executable /bin/sleep --json --json
expect_cli_failure \
  "未知 option" \
  'sample-cpu option の値が不正です: --unknown' \
  --pid 1 --expected-executable /bin/sleep --unknown
expect_cli_failure \
  "out/ready-file 同一パス" \
  '--ready-file の値が不正です: --out と同じパスは指定できません' \
  --pid 1 --expected-executable /bin/sleep \
  --out "$temporary_directory/shared-output" --ready-file "$temporary_directory/shared-output" --json

case_path_directory="$temporary_directory/case-path"
case_path_real_directory="$temporary_directory/case-path-real"
case_path_symlink_directory="$temporary_directory/case-path-link"
mkdir -p "$case_path_directory" "$case_path_real_directory"
ln -s "$case_path_real_directory" "$case_path_symlink_directory"
expect_cli_failure \
  "out/ready-file case-only 同一パス" \
  '--ready-file の値が不正です: --out と同じパスは指定できません' \
  --pid 1 --expected-executable /bin/sleep \
  --out "$case_path_directory/Report.JSON" \
  --ready-file "$case_path_directory/report.json" --json
expect_cli_failure \
  "out/ready-file ancestor symlink・case-only 同一パス" \
  '--ready-file の値が不正です: --out と同じパスは指定できません' \
  --pid 1 --expected-executable /bin/sleep \
  --out "$case_path_symlink_directory/Report.JSON" \
  --ready-file "$case_path_real_directory/report.json" --json

/bin/sleep 5 &
correct_pid=$!
remember_child "$correct_pid"
if ! "$tool_path" sample-cpu \
  --pid "$correct_pid" \
  --expected-executable /bin/sleep \
  --duration 1 \
  --interval 1 \
  --mode idle \
  --json \
  --assert-baseline \
  > "$temporary_directory/correct.json" \
  2> "$temporary_directory/correct.stderr.log"; then
  sed -n '1,120p' "$temporary_directory/correct.stderr.log" >&2
  fail "/bin/sleep の正しい実行主体が不合格になりました"
fi
if "$tool_path" sample-cpu \
  --pid "$correct_pid" \
  --duration 0.1 \
  --interval 0.1 \
  --mode idle \
  --json \
  --assert-baseline \
  > "$temporary_directory/missing-expected.json" \
  2> "$temporary_directory/missing-expected.stderr.log"; then
  fail "--expected-executable 未指定が合格しました"
fi
grep -Fq -- '--expected-executable の値がありません' "$temporary_directory/missing-expected.stderr.log" \
  || fail "--expected-executable 未指定のエラー理由が不明確です"
stop_child "$correct_pid"

[ "$(json_value "$temporary_directory/correct.json" expectedExecutablePath)" = "/bin/sleep" ] \
  || fail "expectedExecutablePath が /bin/sleep ではありません"
[ "$(json_value "$temporary_directory/correct.json" resolvedExecutablePath)" = "/bin/sleep" ] \
  || fail "resolvedExecutablePath が /bin/sleep ではありません"
[ "$(json_value "$temporary_directory/correct.json" executableIdentityMatched)" = "true" ] \
  || fail "正しい /bin/sleep の executableIdentityMatched が true ではありません"
[ "$(json_value "$temporary_directory/correct.json" processIdentityStable)" = "true" ] \
  || fail "正しい /bin/sleep の processIdentityStable が true ではありません"
[ "$(json_value "$temporary_directory/correct.json" baseline.passed)" = "true" ] \
  || fail "正しい /bin/sleep の baseline.passed が true ではありません"
[ "$(json_value "$temporary_directory/correct.json" sampleCount)" -ge 2 ] \
  || fail "正しい /bin/sleep で初回と deadline 後の最終 sample が揃っていません"
[ "$(json_value "$temporary_directory/correct.json" requestedDurationReached)" = "true" ] \
  || fail "正しい /bin/sleep の requestedDurationReached が true ではありません"
correct_actual_duration=$(json_value "$temporary_directory/correct.json" actualDurationSeconds)
/usr/bin/awk -v actual="$correct_actual_duration" 'BEGIN { exit !(actual >= 1) }' \
  || fail "duration=1 の実測時間が 1 秒未満です: $correct_actual_duration"
[ "$(json_value "$temporary_directory/correct.json" schemaVersion)" = "1" ] \
  || fail "sample-cpu の schemaVersion: 1 が維持されていません"
correct_start_token=$(json_value "$temporary_directory/correct.json" processStartToken)
[ -n "$correct_start_token" ] \
  || fail "processStartToken が JSON にありません"
[ "$correct_start_token" = "$(json_value "$temporary_directory/correct.json" samples.0.processStartToken)" ] \
  || fail "report と sample の processStartToken が一致しません"
correct_pidversion=$(json_value "$temporary_directory/correct.json" processIDVersion)
[ -n "$correct_pidversion" ] \
  || fail "processIDVersion が JSON にありません"
[ "$correct_pidversion" = "$(json_value "$temporary_directory/correct.json" samples.0.processIDVersion)" ] \
  || fail "report と sample の processIDVersion が一致しません"

coverage_target_ready="$temporary_directory/duration-coverage-target.ready"
coverage_trigger="$temporary_directory/duration-coverage.trigger"
coverage_sampler_ready="$temporary_directory/duration-coverage-sampler.ready.json"
/bin/sh -c ': > "$1"; while [ ! -f "$2" ]; do /bin/sleep 0.01; done; /bin/sleep 0.25' \
  sh "$coverage_target_ready" "$coverage_trigger" \
  > "$temporary_directory/duration-coverage-process.stdout.log" \
  2> "$temporary_directory/duration-coverage-process.stderr.log" &
coverage_target_pid=$!
remember_child "$coverage_target_pid"
wait_for_file "$coverage_target_ready" "duration 未達 target"
coverage_expected=$(resolve_process_executable "$coverage_target_pid")
[ -x "$coverage_expected" ] \
  || fail "duration 未達 target の executable を解決できません: $coverage_expected"

"$tool_path" sample-cpu \
  --pid "$coverage_target_pid" \
  --expected-executable "$coverage_expected" \
  --duration 1 \
  --interval 0.1 \
  --mode idle \
  --ready-file "$coverage_sampler_ready" \
  --json \
  --assert-baseline \
  > "$temporary_directory/duration-coverage.json" \
  2> "$temporary_directory/duration-coverage.stderr.log" &
coverage_sampler_pid=$!
remember_child "$coverage_sampler_pid"
wait_for_file "$coverage_sampler_ready" "duration 未達 sampler"
: > "$coverage_trigger"
wait "$coverage_sampler_pid" 2>/dev/null
coverage_status=$?
forget_child "$coverage_sampler_pid"
if [ "$coverage_status" -eq 0 ]; then
  fail "要求 duration 前に終了したプロセスが baseline に合格しました"
fi
stop_child "$coverage_target_pid"

[ -s "$temporary_directory/duration-coverage.json" ] \
  || fail "duration 未達で JSON report が出力されませんでした"
[ "$(json_value "$temporary_directory/duration-coverage.json" requestedDurationReached)" = "false" ] \
  || fail "duration 未達の requestedDurationReached が false ではありません"
[ "$(json_value "$temporary_directory/duration-coverage.json" baseline.passed)" = "false" ] \
  || fail "duration 未達の baseline.passed が false ではありません"
[ "$(json_value "$temporary_directory/duration-coverage.json" sampleCount)" -ge 1 ] \
  || fail "duration 未達 report に ready 公開前の有効 sample がありません"
grep -Fq 'deadline 到達後に最終 sample を採取できませんでした' \
  "$temporary_directory/duration-coverage.stderr.log" \
  || fail "duration 未達のエラー理由が不明確です"
[ "$(json_value "$coverage_sampler_ready" ready)" = "true" ] \
  || fail "duration 未達 ready-file が完全な JSON ではありません"
[ "$(json_value "$coverage_sampler_ready" pid)" = "$coverage_target_pid" ] \
  || fail "duration 未達 ready-file の PID が target と一致しません"
[ "$(json_value "$coverage_sampler_ready" completedSampleCount)" = "1" ] \
  || fail "duration 未達 ready-file の completedSampleCount が 1 ではありません"

/bin/sleep 5 &
wrong_expected_pid=$!
remember_child "$wrong_expected_pid"
if "$tool_path" sample-cpu \
  --pid "$wrong_expected_pid" \
  --expected-executable /bin/cat \
  --duration 0.2 \
  --interval 0.1 \
  --mode idle \
  --json \
  --assert-baseline \
  > "$temporary_directory/wrong-expected.json" \
  2> "$temporary_directory/wrong-expected.stderr.log"; then
  fail "誤った expected executable が合格しました"
fi
stop_child "$wrong_expected_pid"

[ "$(json_value "$temporary_directory/wrong-expected.json" expectedExecutablePath)" = "/bin/cat" ] \
  || fail "誤 expected の expectedExecutablePath が保存されていません"
[ "$(json_value "$temporary_directory/wrong-expected.json" resolvedExecutablePath)" = "/bin/sleep" ] \
  || fail "誤 expected の resolvedExecutablePath が実プロセスを示していません"
[ "$(json_value "$temporary_directory/wrong-expected.json" executableIdentityMatched)" = "false" ] \
  || fail "誤 expected の executableIdentityMatched が false ではありません"
[ "$(json_value "$temporary_directory/wrong-expected.json" baseline.passed)" = "false" ] \
  || fail "誤 expected の baseline.passed が false ではありません"
grep -Fq '実行ファイルが期待値と一致しません' "$temporary_directory/wrong-expected.stderr.log" \
  || fail "誤 expected のエラー理由が不明確です"

/bin/sh -c '/bin/sleep 5 & wait' \
  > "$temporary_directory/shell-wrapper-process.stdout.log" \
  2> "$temporary_directory/shell-wrapper-process.stderr.log" &
wrapper_pid=$!
remember_child "$wrapper_pid"
if "$tool_path" sample-cpu \
  --pid "$wrapper_pid" \
  --expected-executable /bin/sleep \
  --duration 0.2 \
  --interval 0.1 \
  --mode idle \
  --json \
  --assert-baseline \
  > "$temporary_directory/shell-wrapper.json" \
  2> "$temporary_directory/shell-wrapper.stderr.log"; then
  fail "sleep を待つ shell wrapper の PID が /bin/sleep として合格しました"
fi
stop_child "$wrapper_pid"

[ "$(json_value "$temporary_directory/shell-wrapper.json" expectedExecutablePath)" = "/bin/sleep" ] \
  || fail "shell wrapper テストの expectedExecutablePath が保存されていません"
[ "$(json_value "$temporary_directory/shell-wrapper.json" executableIdentityMatched)" = "false" ] \
  || fail "shell wrapper の executableIdentityMatched が false ではありません"
[ "$(json_value "$temporary_directory/shell-wrapper.json" baseline.passed)" = "false" ] \
  || fail "shell wrapper の baseline.passed が false ではありません"
if [ "$(json_value "$temporary_directory/shell-wrapper.json" resolvedExecutablePath)" = "/bin/sleep" ]; then
  fail "shell wrapper の resolvedExecutablePath が誤って /bin/sleep になりました"
fi

identity_change_target_ready="$temporary_directory/identity-change-target.ready"
identity_change_trigger="$temporary_directory/identity-change.trigger"
identity_change_sampler_ready="$temporary_directory/identity-change-sampler.ready.json"
/bin/sh -c ': > "$1"; while [ ! -f "$2" ]; do /bin/sleep 0.05; done; exec /bin/sleep 5' \
  sh "$identity_change_target_ready" "$identity_change_trigger" \
  > "$temporary_directory/identity-change-process.stdout.log" \
  2> "$temporary_directory/identity-change-process.stderr.log" &
identity_change_pid=$!
remember_child "$identity_change_pid"

wait_for_file "$identity_change_target_ready" "途中 exec target"
identity_change_expected=$(resolve_process_executable "$identity_change_pid")
[ -x "$identity_change_expected" ] \
  || fail "途中 exec テストの初期 executable を解決できません: $identity_change_expected"

"$tool_path" sample-cpu \
  --pid "$identity_change_pid" \
  --expected-executable "$identity_change_expected" \
  --duration 2 \
  --interval 0.2 \
  --mode idle \
  --ready-file "$identity_change_sampler_ready" \
  --json \
  --assert-baseline \
  > "$temporary_directory/identity-change.json" \
  2> "$temporary_directory/identity-change.stderr.log" &
identity_change_sampler_pid=$!
remember_child "$identity_change_sampler_pid"
wait_for_file "$identity_change_sampler_ready" "途中 exec sampler"
: > "$identity_change_trigger"
wait "$identity_change_sampler_pid" 2>/dev/null
identity_change_status=$?
forget_child "$identity_change_sampler_pid"
if [ "$identity_change_status" -eq 0 ]; then
  fail "測定中に exec した PID が同じ実行主体として合格しました"
fi
stop_child "$identity_change_pid"

[ -s "$temporary_directory/identity-change.json" ] \
  || fail "path が変わる途中 exec で JSON report が出力されませんでした"
[ "$(json_value "$temporary_directory/identity-change.json" executableIdentityMatched)" = "false" ] \
  || fail "途中 exec の executableIdentityMatched が false ではありません"
[ "$(json_value "$temporary_directory/identity-change.json" processIdentityStable)" = "false" ] \
  || fail "途中 exec の processIdentityStable が false ではありません"
[ "$(json_value "$temporary_directory/identity-change.json" baseline.passed)" = "false" ] \
  || fail "途中 exec の baseline.passed が false ではありません"
[ "$(json_value "$temporary_directory/identity-change.json" sampleCount)" -ge 1 ] \
  || fail "途中 exec report に ready 公開前の有効 sample がありません"
[ "$(json_value "$identity_change_sampler_ready" ready)" = "true" ] \
  || fail "途中 exec ready-file が完全な JSON ではありません"
[ "$(json_value "$identity_change_sampler_ready" pid)" = "$identity_change_pid" ] \
  || fail "途中 exec ready-file の PID が target と一致しません"
[ "$(json_value "$identity_change_sampler_ready" completedSampleCount)" = "1" ] \
  || fail "途中 exec ready-file の completedSampleCount が 1 ではありません"
[ "$(json_value "$identity_change_sampler_ready" processIDVersion)" = \
  "$(json_value "$temporary_directory/identity-change.json" processIDVersion)" ] \
  || fail "途中 exec ready-file と report の初期 pidversion が一致しません"
grep -Fq 'pidversion が変化しました' "$temporary_directory/identity-change.stderr.log" \
  || fail "path が変わる途中 exec のエラー理由が pidversion を示していません"

same_path_target_ready="$temporary_directory/same-path-exec-target.ready"
same_path_trigger="$temporary_directory/same-path-exec.trigger"
same_path_sampler_ready="$temporary_directory/same-path-exec-sampler.ready.json"
NAPE_SAMPLE_CPU_SELF_EXEC_COUNT=0 /bin/bash "$self_exec_fixture" \
  "$same_path_target_ready" "$same_path_trigger" \
  > "$temporary_directory/same-path-exec-process.stdout.log" \
  2> "$temporary_directory/same-path-exec-process.stderr.log" &
same_path_pid=$!
remember_child "$same_path_pid"

wait_for_file "$same_path_target_ready" "同一 path exec target"
"$tool_path" sample-cpu \
  --pid "$same_path_pid" \
  --expected-executable /bin/bash \
  --duration 2 \
  --interval 0.2 \
  --mode idle \
  --ready-file "$same_path_sampler_ready" \
  --json \
  --assert-baseline \
  > "$temporary_directory/same-path-exec.json" \
  2> "$temporary_directory/same-path-exec.stderr.log" &
same_path_sampler_pid=$!
remember_child "$same_path_sampler_pid"
wait_for_file "$same_path_sampler_ready" "同一 path exec sampler"
: > "$same_path_trigger"
wait "$same_path_sampler_pid" 2>/dev/null
same_path_status=$?
forget_child "$same_path_sampler_pid"
if [ "$same_path_status" -eq 0 ]; then
  fail "同一 executable path へ exec した PID が同じ実行主体として合格しました"
fi
stop_child "$same_path_pid"

[ -s "$temporary_directory/same-path-exec.json" ] \
  || fail "同一 path exec で JSON report が出力されませんでした"
same_path_expected=$(json_value "$temporary_directory/same-path-exec.json" expectedExecutablePath)
[ "$same_path_expected" = "$(json_value "$temporary_directory/same-path-exec.json" resolvedExecutablePath)" ] \
  || fail "同一 path exec テストで executable path が変化しました"
[ "$(json_value "$temporary_directory/same-path-exec.json" executableIdentityMatched)" = "false" ] \
  || fail "同一 path exec の executableIdentityMatched が false ではありません"
[ "$(json_value "$temporary_directory/same-path-exec.json" processIdentityStable)" = "false" ] \
  || fail "同一 path exec の processIdentityStable が false ではありません"
[ "$(json_value "$temporary_directory/same-path-exec.json" baseline.passed)" = "false" ] \
  || fail "同一 path exec の baseline.passed が false ではありません"
[ "$(json_value "$temporary_directory/same-path-exec.json" sampleCount)" -ge 1 ] \
  || fail "同一 path exec report に ready 公開前の有効 sample がありません"
[ "$(json_value "$same_path_sampler_ready" ready)" = "true" ] \
  || fail "同一 path exec ready-file が完全な JSON ではありません"
[ "$(json_value "$same_path_sampler_ready" pid)" = "$same_path_pid" ] \
  || fail "同一 path exec ready-file の PID が target と一致しません"
[ "$(json_value "$same_path_sampler_ready" completedSampleCount)" = "1" ] \
  || fail "同一 path exec ready-file の completedSampleCount が 1 ではありません"
[ "$(json_value "$same_path_sampler_ready" resolvedExecutablePath)" = "$same_path_expected" ] \
  || fail "同一 path exec ready-file の executable path が report と一致しません"
[ "$(json_value "$same_path_sampler_ready" processIDVersion)" = \
  "$(json_value "$temporary_directory/same-path-exec.json" processIDVersion)" ] \
  || fail "同一 path exec ready-file と report の初期 pidversion が一致しません"
grep -Fq 'pidversion が変化しました' "$temporary_directory/same-path-exec.stderr.log" \
  || fail "同一 path exec のエラー理由が pidversion を示していません"

printf '%s\n' "sample-cpu duration・PID 境界・実行主体同一性テスト: 合格"
