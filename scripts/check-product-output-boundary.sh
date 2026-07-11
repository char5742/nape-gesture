#!/bin/sh

# 製品gesture出力へ診断用のshortcut、PID配送、AX出力が逆流しないことを確認する。
# 実行ビットは不要です。`sh scripts/check-product-output-boundary.sh`で実行してください。

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

cd "$repo_root" || {
  printf '%s\n' "リポジトリrootへ移動できません: $repo_root" >&2
  exit 1
}

failure_count=0

record_failure() {
  failure_count=$((failure_count + 1))
}

require_text() {
  file_path=$1
  required_text=$2
  description=$3

  if ! grep -Fq -- "$required_text" "$file_path"; then
    printf '%s\n' "不足: $description" >&2
    printf '%s\n' "  file: $file_path" >&2
    record_failure
  fi
}

product_matches=$(
  grep -nEH \
    'keyboardEventSource|postToPid|AXUIElement|forcedHorizontal|DiagnosticEvent|GenerateScrollCommand|SystemBehaviorTestCommand|kVK_[[:alnum:]_]+' \
    Sources/NapeGestureProductOutput/*.swift \
    Sources/nape-gesture/GestureActionExecutor.swift \
    Sources/nape-gesture/NapeGestureDaemon.swift \
    Sources/nape-gesture/NapeGestureRuntime.swift 2>/dev/null || true
)

if [ -n "$product_matches" ]; then
  printf '%s\n' "禁止: 製品gesture出力境界に診断用配送またはshortcut依存があります。" >&2
  printf '%s\n' "$product_matches" >&2
  record_failure
fi

product_time_matches=$(
  grep -nEH \
    'timeIntervalSince1970|timeIntervalSinceReferenceDate|timeIntervalSinceNow|CFAbsoluteTimeGetCurrent|CACurrentMediaTime|mach_absolute_time|mach_continuous_time|clock_gettime|ContinuousClock|SuspendingClock|Date[[:space:]]*\(|systemUptime|uptimeNanoseconds' \
    Sources/NapeGestureProductOutput/*.swift \
    Sources/nape-gesture/GestureActionExecutor.swift \
    Sources/nape-gesture/NapeGestureDaemon.swift \
    Sources/nape-gesture/NapeGestureRuntime.swift 2>/dev/null || true
)

if [ -n "$product_time_matches" ]; then
  printf '%s\n' "禁止: 製品gesture出力境界ではMonotonicEventClock以外の時刻取得を直接使わないでください。" >&2
  printf '%s\n' "$product_time_matches" >&2
  record_failure
fi

diagnostic_product_matches=$(
  grep -nEH 'NapeGestureProductOutput|ProductGestureOutput' \
    Sources/NapeGestureDiagnosticOutput/*.swift 2>/dev/null || true
)

if [ -n "$diagnostic_product_matches" ]; then
  printf '%s\n' "禁止: 診断output targetから製品output targetへ依存しないでください。" >&2
  printf '%s\n' "$diagnostic_product_matches" >&2
  record_failure
fi

diagnostic_import_matches=$(
  for file_path in Sources/nape-gesture/*.swift; do
    file_name=${file_path##*/}
    if [ "$file_name" = "AnalyzeTrackpadEventLogCommand.swift" ] \
      || [ "$file_name" = "GenerateScrollCommand.swift" ] \
      || [ "$file_name" = "SystemBehaviorTestCommand.swift" ] \
      || [ "$file_name" = "TrackpadDriverEventLogger.swift" ]; then
      continue
    fi
    grep -nEH \
      'NapeGestureDiagnosticOutput|DiagnosticEventPoster|DiagnosticEventPostResult|forcedHorizontal' \
      "$file_path" 2>/dev/null || true
  done
)

if [ -n "$diagnostic_import_matches" ]; then
  printf '%s\n' "禁止: 診断output targetは許可したCLI command以外から参照できません。" >&2
  printf '%s\n' "$diagnostic_import_matches" >&2
  record_failure
fi

if [ -e "Sources/nape-gesture/EventPoster.swift" ]; then
  printf '%s\n' "禁止: 診断posterを製品実行targetへ置かないでください。" >&2
  record_failure
fi

require_text \
  "Package.swift" \
  'name: "NapeGestureProductOutput"' \
  "製品gesture出力を専用SwiftPM targetへ分離する"

require_text \
  "Package.swift" \
  'name: "NapeGestureDiagnosticOutput"' \
  "旧CGEvent posterを診断専用SwiftPM targetへ分離する"

require_text \
  "Sources/NapeGestureDiagnosticOutput/DiagnosticEventPoster.swift" \
  "public final class DiagnosticEventPoster" \
  "診断posterを診断専用targetに置く"

require_text \
  "Sources/nape-gesture/GestureActionExecutor.swift" \
  "import NapeGestureProductOutput" \
  "製品executorをproduct output targetへ接続する"

require_text \
  "Sources/nape-gesture/NapeGestureDaemon.swift" \
  "try actionExecutor.ensureOutputAvailable()" \
  "event tap開始前にoutput contractを検査する"

require_text \
  "Sources/NapeGestureCore/TrackpadOutputSession.swift" \
  "public struct TrackpadOutputSessionMachine" \
  "全event familyのsession lifecycleを共通modelへ集約する"

require_text \
  "Sources/NapeGestureCore/MonotonicEventClock.swift" \
  "public enum MonotonicEventClock" \
  "製品event時刻を共通の起動後時刻domainへ集約する"

require_text \
  "Sources/NapeGestureCore/MonotonicEventClock.swift" \
  "fileprivate init(uncheckedNanosecondsSinceStartup" \
  "未検証の起動後ナノ秒initializerをmodule外へ公開しない"

require_text \
  "Sources/NapeGestureCore/MonotonicEventClock.swift" \
  "private static func validatedTimestamp" \
  "任意referenceによるtimestamp検証迂回を外部APIへ公開しない"

require_text \
  "Sources/NapeGestureCore/TrackpadOutputSession.swift" \
  "timestampOutsideCurrentBoot" \
  "現在bootのuptimeを超えるsession timestampを拒否する"

require_text \
  "docs/adr/0037-separate-product-and-diagnostic-event-output.md" \
  "製品gesture出力と診断event出力を分離する" \
  "製品出力境界のADRを維持する"

require_text \
  "docs/adr/0038-trackpad-output-session-and-monotonic-clock.md" \
  "trackpad出力sessionとmonotonic clockを共通化する" \
  "output sessionと時刻domainのADRを維持する"

if [ "$failure_count" -ne 0 ]; then
  printf '%s\n' "product output boundary check failed: $failure_count 件の問題があります。" >&2
  exit 1
fi

printf '%s\n' "product output boundary check passed"
