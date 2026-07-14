#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
binary=${1:-"$repo_root/.build/debug/nape-gesture"}
case "$binary" in
  /*) ;;
  *) binary="$repo_root/$binary" ;;
esac

if [ ! -x "$binary" ]; then
  printf '%s\n' "nape-gesture実行ファイルがありません: $binary" >&2
  exit 1
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/nape-gesture-doctor-stability.XXXXXX")
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM

config="$temporary_root/config.json"
report="$temporary_root/doctor.json"
assert_report="$temporary_root/doctor-assert.json"

"$binary" init-config --out "$config" >/dev/null
"$binary" doctor --config "$config" --benchmark-events 32 --json > "$report"

jq -e '
  .runtimeReadiness.ready == false
  and any(.runtimeReadiness.failures[]; .code == "inputMonitoring.notProbed")
  and .tccStatus.inputMonitoring == {
    "checked": false,
    "remediation": "`doctor --probe-hid` を実行して入力監視の状態を確認してください。",
    "service": "inputMonitoring",
    "status": "notProbed"
  }
  and .tccStatus.permissionTarget.executablePath == .runtimeIdentity.executablePath
  and .tccStatus.permissionTarget.bundlePath == .runtimeIdentity.bundlePath
  and .tccStatus.permissionTarget.isAppBundle == .runtimeIdentity.isAppBundle
  and .tccStatus.permissionTarget.launchContext == .runtimeIdentity.launchContext
  and .tccStatus.permissionTarget.processName == .runtimeIdentity.processName
  and (.outputContract.requiredFamilies | sort) == ["dockSwipe", "dockSwipePinch", "scroll"]
  and ((.runtimeReadiness.failures | map(.code) | unique | length) == (.runtimeReadiness.failures | length))
  and (
    if .tccStatus.accessibility.granted == true
    then all(.runtimeReadiness.failures[]; .code != "accessibility.missing")
    else any(.runtimeReadiness.failures[]; .code == "accessibility.missing")
    end
  )
  and (
    if .requireMatchingTargetDevice and .matchedTargetDeviceCount == 0
    then any(.runtimeReadiness.failures[]; .code == "targetDevice.notFound")
    else true
    end
  )
  and (
    if .outputContract.supported
    then (.outputContract.missingRequiredFamilies | length) == 0
      and (. as $root | [
        $root.outputContract.requiredFamilies[] as $family
        | $root.outputContract.supportedFamilies
        | index($family) != null
      ] | all)
      and all(.runtimeReadiness.failures[]; (.code | startswith("outputContract.")) | not)
    else any(.runtimeReadiness.failures[]; .code | startswith("outputContract."))
    end
  )
' "$report" >/dev/null

if "$binary" doctor --config "$config" --benchmark-events 32 --json --assert-runtime-ready > "$assert_report" 2> "$temporary_root/doctor-assert.err"; then
  printf '%s\n' "入力監視未確認のdoctorをruntime readyとして受理しました。" >&2
  exit 1
fi
jq -e '
  .runtimeReadiness.ready == false
  and any(.runtimeReadiness.failures[]; .code == "inputMonitoring.notProbed")
' "$assert_report" >/dev/null
grep -Eq 'inputMonitoring\.notProbed|HID 入力監視プローブが未実行' "$temporary_root/doctor-assert.err"

if "$binary" doctor --config "$config" --benchmark-events 0 --json >/dev/null 2>&1; then
  printf '%s\n' "0件のbenchmarkをdoctorが受理しました。" >&2
  exit 1
fi
if "$binary" doctor --config "$config" --benchmark-events invalid --json >/dev/null 2>&1; then
  printf '%s\n' "非数値のbenchmark件数をdoctorが受理しました。" >&2
  exit 1
fi
if "$binary" doctor --config "$config" --assert-runtime-read --json >/dev/null 2>&1; then
  printf '%s\n' "未知のdoctor optionを無視しました。" >&2
  exit 1
fi
if "$binary" doctor --config "$config" --config "$config" --json >/dev/null 2>&1; then
  printf '%s\n' "重複した--configをdoctorが受理しました。" >&2
  exit 1
fi
if (cd "$temporary_root" && "$binary" doctor --config --json >/dev/null 2>&1); then
  printf '%s\n' "--jsonを--configの値としてdoctorが受理しました。" >&2
  exit 1
fi
test ! -e "$temporary_root/--json"
if "$binary" doctor unexpected-value --json >/dev/null 2>&1; then
  printf '%s\n' "位置引数をdoctorが黙認しました。" >&2
  exit 1
fi

printf '%s\n' "doctor readiness整合性テストに成功しました。"
