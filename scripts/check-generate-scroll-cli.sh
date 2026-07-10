#!/bin/sh

set -u

binary=${1:-.build/debug/nape-gesture}
failure_count=0

expect_failure() {
  title=$1
  expected_message=$2
  shift 2

  stdout_file=$(mktemp /tmp/nape-generate-scroll-stdout.XXXXXX)
  stderr_file=$(mktemp /tmp/nape-generate-scroll-stderr.XXXXXX)
  if "$binary" generate-scroll "$@" > "$stdout_file" 2> "$stderr_file"; then
    printf '%s\n' "失敗: $title が成功終了しました。" >&2
    failure_count=$((failure_count + 1))
  elif ! grep -F -- "$expected_message" "$stderr_file" >/dev/null; then
    printf '%s\n' "失敗: $title の診断が期待値と一致しません。" >&2
    cat "$stderr_file" >&2
    failure_count=$((failure_count + 1))
  else
    printf '%s\n' "成功: $title"
  fi
  rm -f "$stdout_file" "$stderr_file"
}

expect_failure \
  "--post-to-pid の末尾値欠落" \
  "--post-to-pid の値がありません。" \
  --x 1 --dry-run --post-to-pid

expect_failure \
  "--ax-delivery の末尾値欠落" \
  "--ax-delivery の値がありません。" \
  --x 1 --dry-run --ax-delivery

expect_failure \
  "未知 option" \
  "未知の option です: --unknown" \
  --x 1 --dry-run --unknown value

expect_failure \
  "--post-to-pid の重複" \
  "同じ option は複数回指定できません。" \
  --x 1 --dry-run --post-to-pid 1 --post-to-pid 2

expect_failure \
  "--ax-delivery の重複" \
  "同じ option は複数回指定できません。" \
  --x 1 --dry-run --ax-delivery sync --ax-delivery async

expect_failure \
  "余分な positional argument" \
  "generate-scroll positional argument の値が不正です: extra" \
  --x 1 --dry-run extra

expect_failure \
  "flag option の重複" \
  "同じ option は複数回指定できません。" \
  --x 1 --dry-run --dry-run

if [ "$failure_count" -ne 0 ]; then
  printf '%s\n' "$failure_count 件の generate-scroll CLI 検査が失敗しました。" >&2
  exit 1
fi

printf '%s\n' "generate-scroll CLI の期待失敗を確認しました。"
