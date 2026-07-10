#!/bin/sh

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
test_dir=$(mktemp -d /tmp/nape-system-behavior-post-result.XXXXXX) || {
  printf '%s\n' "失敗: 投稿結果テストの一時ディレクトリを作成できません。" >&2
  exit 1
}
test_source="$test_dir/main.swift"
test_binary="$test_dir/check-system-behavior-post-result"

cleanup() {
  rm -rf "$test_dir"
}
trap cleanup EXIT HUP INT TERM

cat > "$test_source" <<'SWIFT'
import Darwin
import Foundation

var failureCount = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("失敗: \(message)\n", stderr)
        failureCount += 1
        return
    }
}

let success = SystemBehaviorPostResultSnapshot(
    generatedEventCount: 1,
    failedEventCreationCount: 0
).status
let creationFailure = SystemBehaviorPostResultSnapshot(
    generatedEventCount: 1,
    failedEventCreationCount: 2
).status
let noGeneratedEvents = SystemBehaviorPostResultSnapshot(
    generatedEventCount: 0,
    failedEventCreationCount: 0
).status

expect(success == .success, "生成成功を成功状態にする")
expect(success.failureName == nil, "生成成功にエラー名を付けない")
expect(success.failureDescription == nil, "生成成功にエラー説明を付けない")

expect(
    creationFailure == .eventCreationFailure(count: 2),
    "failedEventCreationCount をCGEvent作成失敗として保持する"
)
expect(creationFailure.failureName == "CGEvent timestamp", "timestamp / CGEvent作成失敗の契約を維持する")
expect(
    creationFailure.failureDescription == "現在の起動後単調時刻から60秒以内の値を生成できませんでした。",
    "timestamp / CGEvent作成失敗の既存診断を維持する"
)

expect(noGeneratedEvents == .noGeneratedEvents, "生成0件を独立した失敗状態にする")
expect(noGeneratedEvents.failureName == "system-test posting", "生成0件をtimestamp不正と報告しない")
expect(
    noGeneratedEvents.failureDescription?.contains("配送できなかったか、対象に変化がなかった") == true,
    "生成0件を配送不能または変化なしと診断する"
)
expect(
    noGeneratedEvents.failureDescription?.contains("timestamp") == false,
    "生成0件の説明にtimestampを含めない"
)

if failureCount != 0 {
    exit(1)
}
SWIFT

if ! swiftc \
  -swift-version 5 \
  -D SYSTEM_BEHAVIOR_POST_RESULT_TESTING \
  "$repo_root/Sources/nape-gesture/SystemBehaviorTestCommand.swift" \
  "$test_source" \
  -o "$test_binary"; then
  printf '%s\n' "失敗: 投稿結果テストをコンパイルできません。" >&2
  exit 1
fi

if ! "$test_binary"; then
  printf '%s\n' "失敗: 投稿結果の3状態契約に違反しました。" >&2
  exit 1
fi

printf '%s\n' "成功: system-test 投稿結果の生成成功・生成失敗・生成0件契約"
