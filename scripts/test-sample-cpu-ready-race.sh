#!/bin/sh

# ready-file の排他的 atomic 公開を16並列で確認する。
# 実行ビットは不要です。sh scripts/test-sample-cpu-ready-race.sh で実行してください。

set -u

tool_path=${1:-.build/debug/nape-gesture}
case "$tool_path" in
  /*) ;;
  *) tool_path="$PWD/$tool_path" ;;
esac

if [ ! -x "$tool_path" ]; then
  printf '%s\n' "sample-cpu 並列テスト対象が見つからないか実行できません: $tool_path" >&2
  exit 1
fi

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/nape-sample-cpu-ready-race.XXXXXX") || exit 1
child_pids=""
target_pid=""

cleanup() {
  for child_pid in $child_pids; do
    kill "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  done
  if [ -n "$target_pid" ]; then
    kill "$target_pid" 2>/dev/null || true
    wait "$target_pid" 2>/dev/null || true
  fi
  rm -rf "$temporary_directory"
}

fail() {
  printf '%s\n' "sample-cpu ready 並列テスト失敗: $1" >&2
  exit 1
}

trap cleanup EXIT
trap 'exit 1' HUP INT TERM

ready_path="$temporary_directory/shared-ready.json"
/bin/sleep 10 &
target_pid=$!

preserved_ready_path="$temporary_directory/preserved-ready.json"
preserved_ready_content='{"sentinel":"既存内容を保持"}'
printf '%s\n' "$preserved_ready_content" > "$preserved_ready_path"
if "$tool_path" sample-cpu \
  --pid "$target_pid" \
  --expected-executable /bin/sleep \
  --duration 0.2 \
  --interval 0.1 \
  --mode idle \
  --ready-file "$preserved_ready_path" \
  --json \
  > "$temporary_directory/preserved-report.json" \
  2> "$temporary_directory/preserved-report.stderr.log"; then
  fail "既存 ready-file への公開が成功しました"
fi
grep -Fq -- '--ready-file の値が不正です: 既に存在するため排他的に公開できません' \
  "$temporary_directory/preserved-report.stderr.log" \
  || fail "既存 ready-file 競合のエラー理由が不明確です"
[ "$(sed -n '1p' "$preserved_ready_path")" = "$preserved_ready_content" ] \
  || fail "既存 ready-file の内容が上書きされました"
if find "$temporary_directory" -name '.preserved-ready.json.*.tmp' -print -quit | grep -q .; then
  fail "既存 ready-file 競合後に sibling temp が残っています"
fi

parallel_index=1
while [ "$parallel_index" -le 16 ]; do
  "$tool_path" sample-cpu \
    --pid "$target_pid" \
    --expected-executable /bin/sleep \
    --duration 0.2 \
    --interval 0.1 \
    --mode idle \
    --ready-file "$ready_path" \
    --json \
    --assert-baseline \
    > "$temporary_directory/report-$parallel_index.json" \
    2> "$temporary_directory/report-$parallel_index.stderr.log" &
  child_pids="$child_pids $!"
  parallel_index=$((parallel_index + 1))
done

success_count=0
winner_index=""
parallel_index=1
for child_pid in $child_pids; do
  if wait "$child_pid" 2>/dev/null; then
    child_status=0
  else
    child_status=$?
  fi

  if [ "$child_status" -eq 0 ]; then
    success_count=$((success_count + 1))
    winner_index=$parallel_index
  else
    grep -Fq -- '--ready-file の値が不正です: 既に存在するため排他的に公開できません' \
      "$temporary_directory/report-$parallel_index.stderr.log" \
      || fail "競合敗者 $parallel_index のエラー理由が排他公開失敗ではありません"
  fi
  if grep -Fq 'Fatal error' "$temporary_directory/report-$parallel_index.stderr.log"; then
    fail "競合プロセス $parallel_index で Fatal error が発生しました"
  fi
  parallel_index=$((parallel_index + 1))
done
child_pids=""

[ "$success_count" -eq 1 ] \
  || fail "16並列の成功数が1ではありません: $success_count"
[ -n "$winner_index" ] \
  || fail "ready-file 公開成功プロセスを特定できません"
[ -s "$ready_path" ] \
  || fail "ready-file が完全な JSON として公開されていません"
[ "$(/usr/bin/plutil -extract ready raw -o - "$ready_path")" = "true" ] \
  || fail "ready-file の ready が true ではありません"
[ "$(/usr/bin/plutil -extract completedSampleCount raw -o - "$ready_path")" = "1" ] \
  || fail "ready-file の completedSampleCount が 1 ではありません"
[ "$(/usr/bin/plutil -extract baseline.passed raw -o - "$temporary_directory/report-$winner_index.json")" = "true" ] \
  || fail "排他公開の勝者が baseline に合格していません"

if find "$temporary_directory" -name '.shared-ready.json.*.tmp' -print -quit | grep -q .; then
  fail "ready-file 公開後に sibling temp が残っています"
fi

printf '%s\n' "sample-cpu ready 16並列排他公開テスト: 合格"
