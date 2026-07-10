#!/bin/sh

# sample-cpu が数値 PID だけで別の実行主体を合格させないことを確認する。
# 実行ビットは不要です。sh scripts/test-sample-cpu.sh で実行してください。

set -u

tool_path=${1:-.build/debug/nape-gesture}
case "$tool_path" in
  /*) ;;
  *) tool_path="$PWD/$tool_path" ;;
esac

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

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

/bin/sleep 5 &
correct_pid=$!
remember_child "$correct_pid"
if ! "$tool_path" sample-cpu \
  --pid "$correct_pid" \
  --expected-executable /bin/sleep \
  --duration 0.2 \
  --interval 0.1 \
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
[ "$(json_value "$temporary_directory/correct.json" sampleCount)" -gt 0 ] \
  || fail "正しい /bin/sleep の CPU sample がありません"
correct_start_token=$(json_value "$temporary_directory/correct.json" processStartToken)
[ -n "$correct_start_token" ] \
  || fail "processStartToken が JSON にありません"
[ "$correct_start_token" = "$(json_value "$temporary_directory/correct.json" samples.0.processStartToken)" ] \
  || fail "report と sample の processStartToken が一致しません"

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

identity_change_ready="$temporary_directory/identity-change.ready"
identity_change_trigger="$temporary_directory/identity-change.trigger"
/bin/sh -c ': > "$1"; while [ ! -f "$2" ]; do /bin/sleep 0.05; done; exec /bin/sleep 5' \
  sh "$identity_change_ready" "$identity_change_trigger" \
  > "$temporary_directory/identity-change-process.stdout.log" \
  2> "$temporary_directory/identity-change-process.stderr.log" &
identity_change_pid=$!
remember_child "$identity_change_pid"

ready_attempt=0
while [ ! -f "$identity_change_ready" ]; do
  ready_attempt=$((ready_attempt + 1))
  if [ "$ready_attempt" -ge 100 ]; then
    fail "途中 exec テストの shell が準備完了になりません"
  fi
  /bin/sleep 0.01
done
identity_change_expected=$(
  /usr/bin/swift -e '
    import Darwin

    let pid = Int32(CommandLine.arguments[1])!
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let result = proc_pidpath(pid, &path, UInt32(path.count))
    if result <= 0 {
        exit(1)
    }
    print(String(cString: path))
  ' "$identity_change_pid"
)
[ -x "$identity_change_expected" ] \
  || fail "途中 exec テストの初期 executable を解決できません: $identity_change_expected"

/bin/sh -c '/bin/sleep 0.5; : > "$1"' sh "$identity_change_trigger" &
identity_change_trigger_pid=$!
remember_child "$identity_change_trigger_pid"
"$tool_path" sample-cpu \
  --pid "$identity_change_pid" \
  --expected-executable "$identity_change_expected" \
  --duration 2 \
  --interval 0.2 \
  --mode idle \
  --json \
  --assert-baseline \
  > "$temporary_directory/identity-change.json" \
  2> "$temporary_directory/identity-change.stderr.log"
identity_change_status=$?
wait "$identity_change_trigger_pid" 2>/dev/null || true
forget_child "$identity_change_trigger_pid"
if [ "$identity_change_status" -eq 0 ]; then
  fail "測定中に exec した PID が同じ実行主体として合格しました"
fi
stop_child "$identity_change_pid"

[ "$(json_value "$temporary_directory/identity-change.json" executableIdentityMatched)" = "false" ] \
  || fail "途中 exec の executableIdentityMatched が false ではありません"
[ "$(json_value "$temporary_directory/identity-change.json" processIdentityStable)" = "false" ] \
  || fail "途中 exec の processIdentityStable が false ではありません"
[ "$(json_value "$temporary_directory/identity-change.json" resolvedExecutablePath)" = "/bin/sleep" ] \
  || fail "途中 exec 後の resolvedExecutablePath が /bin/sleep ではありません"
[ "$(json_value "$temporary_directory/identity-change.json" baseline.passed)" = "false" ] \
  || fail "途中 exec の baseline.passed が false ではありません"
grep -Fq '実行ファイルが変化しました' "$temporary_directory/identity-change.stderr.log" \
  || fail "途中 exec のエラー理由が不明確です"

printf '%s\n' "sample-cpu 実行主体同一性テスト: 合格"
