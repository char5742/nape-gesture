#!/bin/sh

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

cd "$repo_root" || {
  printf '%s\n' "リポジトリrootへ移動できません: $repo_root" >&2
  exit 1
}

files="
Sources/NapeGestureDiagnosticOutput/DiagnosticEventPoster.swift
Sources/nape-gesture/GenerateScrollCommand.swift
Sources/nape-gesture/SystemBehaviorTestCommand.swift
"

test_file=Sources/nape-gesture-diagnostic-output-tests/main.swift

for file_path in $files; do
  if [ ! -r "$file_path" ]; then
    printf '%s\n' "検査対象を読み取れません: $file_path" >&2
    exit 1
  fi
done

if [ ! -r "$test_file" ]; then
  printf '%s\n' "検査対象を読み取れません: $test_file" >&2
  exit 1
fi

forbidden_matches=$(
  grep -nEH \
    'timeIntervalSince1970|timeIntervalSinceReferenceDate|CFAbsoluteTimeGetCurrent|CACurrentMediaTime|mach_absolute_time|mach_continuous_time|clock_gettime|Date[[:space:]]*\(|ProcessInfo\.processInfo\.systemUptime|DispatchTime\.now' \
    $files 2>/dev/null || true
)

if [ -n "$forbidden_matches" ]; then
  printf '%s\n' "禁止: 診断event投稿経路へ共通clock以外の時刻取得が再混入しています。" >&2
  printf '%s\n' "$forbidden_matches" >&2
  exit 1
fi

for file_path in $files; do
  if ! grep -Fq 'MonotonicEventClock' "$file_path"; then
    printf '%s\n' "不足: 共通の起動後clockを使用していません: $file_path" >&2
    exit 1
  fi
done

if ! grep -Fq 'MonotonicEventClock.timestamp(' Sources/NapeGestureDiagnosticOutput/DiagnosticEventPoster.swift; then
  printf '%s\n' "不足: DiagnosticEventPosterが投稿timestampをfail closedで検証していません。" >&2
  exit 1
fi

if grep -nF 'event.timestamp = CGEventTimestamp' \
  Sources/nape-gesture/GenerateScrollCommand.swift \
  Sources/nape-gesture/SystemBehaviorTestCommand.swift; then
  printf '%s\n' "禁止: command側で予定時刻を実投稿eventへ直接設定しています。" >&2
  exit 1
fi

if ! grep -Fq 'postScrollSequence(' Sources/nape-gesture/GenerateScrollCommand.swift; then
  printf '%s\n' "不足: generate-scrollがterminal回復可能なsequence投稿を使っていません。" >&2
  exit 1
fi

if ! grep -Fq 'postPreparedSequence(' Sources/nape-gesture/SystemBehaviorTestCommand.swift; then
  printf '%s\n' "不足: system-testがrelease回復可能なsequence投稿を使っていません。" >&2
  exit 1
fi

required_test_calls="
testScrollSequenceValidatesStartAndOriginalOrder()
testScrollPostFailureRecoversTerminal()
testPreparedSequenceRecoversMouseUpAndKeyUp()
testAllSystemScenarioDryRuns()
testAllGenerateScrollPatterns()
"

for required_test_call in $required_test_calls; do
  if ! grep -Fq "$required_test_call" "$test_file"; then
    printf '%s\n' "不足: 診断時刻contractの実行テストが呼び出されていません: $required_test_call" >&2
    exit 1
  fi
done

printf '%s\n' "diagnostic event time check passed"
