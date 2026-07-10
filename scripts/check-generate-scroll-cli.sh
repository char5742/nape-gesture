#!/bin/sh

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
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

check_post_result_collector() {
  test_dir=$(mktemp -d /tmp/nape-generate-scroll-post-result.XXXXXX) || {
    printf '%s\n' "失敗: 投稿結果 collector の一時ディレクトリを作成できません。" >&2
    failure_count=$((failure_count + 1))
    return
  }
  source_file="$repo_root/Sources/nape-gesture/GenerateScrollCommand.swift"
  test_source="$test_dir/main.swift"
  test_binary="$test_dir/check-post-result-collector"

  cat > "$test_source" <<'SWIFT'
import Darwin
import Dispatch
import Foundation

var failureCount = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("失敗: \(message)\n", stderr)
        failureCount += 1
        return
    }
}

let completedSuccess = GenerateScrollPostResultSnapshot(
    generatedEventCount: 1,
    failedEventCreationCount: 0,
    deliveryDeferred: false
)
let deferredSuccess = GenerateScrollPostResultSnapshot(
    generatedEventCount: 1,
    failedEventCreationCount: 0,
    deliveryDeferred: true
)
let completedFailure = GenerateScrollPostResultSnapshot(
    generatedEventCount: 0,
    failedEventCreationCount: 1,
    deliveryDeferred: false
)
let completedNoOp = GenerateScrollPostResultSnapshot(
    generatedEventCount: 0,
    failedEventCreationCount: 0,
    deliveryDeferred: false
)

expect(completedSuccess.completedFailureDescription == nil, "同期成功を受理する")
expect(completedFailure.completedFailureDescription != nil, "同期投稿失敗を拒否する")
expect(completedNoOp.completedFailureDescription == nil, "blocked / noChange の0件完了を受理する")
expect(deferredSuccess.completedFailureDescription != nil, "未完了 deferred を同期成功にしない")

let concurrentCollector = GenerateScrollPostCompletionCollector()
let commandCount = 64
let completionGroup = DispatchGroup()
for index in 0..<commandCount {
    completionGroup.enter()
    DispatchQueue.global().async {
        concurrentCollector.recordCompletion(index: index, result: completedSuccess)
        completionGroup.leave()
    }
}
completionGroup.wait()
expect(
    concurrentCollector.validationFailures(expectedCommandIndexes: Set(0..<commandCount)).isEmpty,
    "並行 completion を全件集約する"
)

let missingCollector = GenerateScrollPostCompletionCollector()
expect(
    missingCollector.validationFailures(expectedCommandIndexes: [0])
        .contains(where: { $0.contains("async completion がありません") }),
    "completion 欠落を拒否する"
)

let failedCompletionCollector = GenerateScrollPostCompletionCollector()
failedCompletionCollector.recordCompletion(index: 0, result: completedFailure)
expect(
    failedCompletionCollector.validationFailures(expectedCommandIndexes: [0])
        .contains(where: { $0.contains("async completion が失敗しました") }),
    "async completion の投稿失敗を拒否する"
)

expect(
    completedFailure.completedFailureDescription != nil,
    "async 指定時の非deferred投稿失敗も拒否する"
)

let duplicateCollector = GenerateScrollPostCompletionCollector()
duplicateCollector.recordCompletion(index: 0, result: completedSuccess)
duplicateCollector.recordCompletion(index: 0, result: completedSuccess)
expect(
    duplicateCollector.validationFailures(expectedCommandIndexes: [0])
        .contains(where: { $0.contains("async completion が重複しています") }),
    "重複 completion を拒否する"
)

if failureCount != 0 {
    exit(1)
}
SWIFT

  if ! swiftc \
    -swift-version 5 \
    -D GENERATE_SCROLL_POST_RESULT_TESTING \
    "$source_file" \
    "$test_source" \
    -o "$test_binary"; then
    printf '%s\n' "失敗: 投稿結果 collector のテストをコンパイルできません。" >&2
    failure_count=$((failure_count + 1))
  elif ! "$test_binary"; then
    printf '%s\n' "失敗: 投稿結果 collector の検査が失敗しました。" >&2
    failure_count=$((failure_count + 1))
  else
    printf '%s\n' "成功: 投稿結果 collector の同期・非同期失敗契約"
  fi

  rm -rf "$test_dir"
}

check_dry_run_json_lines() {
  stdout_file=$(mktemp /tmp/nape-generate-scroll-dry-run.XXXXXX)
  stderr_file=$(mktemp /tmp/nape-generate-scroll-dry-run-stderr.XXXXXX)
  analyze_file=$(mktemp /tmp/nape-generate-scroll-dry-run-analyze.XXXXXX)

  if ! "$binary" generate-scroll \
    --x 12 \
    --steps 2 \
    --dry-run \
    --log-json > "$stdout_file" 2> "$stderr_file"; then
    printf '%s\n' "失敗: dry-run JSON Lines が失敗しました。" >&2
    cat "$stderr_file" >&2
    failure_count=$((failure_count + 1))
  elif [ "$(wc -l < "$stdout_file" | tr -d ' ')" -ne 2 ]; then
    printf '%s\n' "失敗: dry-run JSON Lines が2件ではありません。" >&2
    cat "$stdout_file" >&2
    failure_count=$((failure_count + 1))
  elif ! "$binary" analyze-log \
    "$stdout_file" \
    --assert-current-uptime > "$analyze_file" 2>&1; then
    printf '%s\n' "失敗: dry-run JSON Lines の current uptime 検証が失敗しました。" >&2
    cat "$analyze_file" >&2
    failure_count=$((failure_count + 1))
  else
    printf '%s\n' "成功: dry-run JSON Lines の件数・current uptime 契約"
  fi

  rm -f "$stdout_file" "$stderr_file" "$analyze_file"
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

check_dry_run_json_lines
check_post_result_collector

if [ "$failure_count" -ne 0 ]; then
  printf '%s\n' "$failure_count 件の generate-scroll CLI 検査が失敗しました。" >&2
  exit 1
fi

printf '%s\n' "generate-scroll CLI の期待失敗を確認しました。"
