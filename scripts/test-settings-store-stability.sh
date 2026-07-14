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

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/nape-gesture-settings-stability.XXXXXX")
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM

canonical="$temporary_root/canonical.json"
legacy="$temporary_root/legacy.json"
invalid_legacy="$temporary_root/invalid-legacy.json"
malformed="$temporary_root/malformed.json"
concurrent="$temporary_root/concurrent.json"
created="$temporary_root/new/nested/config.json"
locked="$temporary_root/locked/config.json"
symlink_locked="$temporary_root/symlink-locked/config.json"

"$binary" init-config --out "$canonical" >/dev/null
cp "$canonical" "$legacy"
ruby -rjson -e '
  path = ARGV.fetch(0)
  document = JSON.parse(File.read(path))
  gesture = document.fetch("gesture")
  gesture["button3Mode"] = "scrollAndNavigate"
  gesture["button4Mode"] = "spacesAndMissionControl"
  gesture["button5Mode"] = "zoom"
  gesture["deadZonePoints"] = 8
  gesture["dragSensitivity"] = 1
  gesture["wheelSensitivity"] = 1
  gesture["directionLockRatio"] = 1.4
  gesture["cancellation"]["offAxisCancelRatio"] = 1.2
  document["applicationSettings"] = {"com.example.Legacy" => {"enabled" => false}}
  File.write(path, JSON.pretty_generate(document) + "\n")
' "$legacy"

"$binary" doctor --config "$legacy" --benchmark-events 1 --json > "$temporary_root/legacy-doctor.json"
jq -e '
  .gesture == {
    "cancellation": {
      "maximumDuration": 10,
      "maximumInactivityInterval": 2
    }
  }
  and .requireMatchingTargetDevice == true
  and .targetDeviceAssociation.associationWindow == 0.12
  and .targetDevices == [{"productContains":"Nape Pro"}]
  and (keys | sort) == [
    "gesture",
    "requireMatchingTargetDevice",
    "targetDeviceAssociation",
    "targetDevices"
  ]
' "$legacy" >/dev/null
if grep -Eq 'button[345]Mode|deadZonePoints|Sensitivity|directionLockRatio|offAxisCancelRatio|applicationSettings' "$legacy"; then
  printf '%s\n' "canonical移行後も廃止済み設定が残っています。" >&2
  exit 1
fi

canonical_inode=$(stat -f '%i' "$legacy")
canonical_hash=$(shasum -a 256 "$legacy" | awk '{print $1}')
"$binary" doctor --config "$legacy" --benchmark-events 1 --json > "$temporary_root/canonical-doctor.json"
test "$canonical_inode" = "$(stat -f '%i' "$legacy")"
test "$canonical_hash" = "$(shasum -a 256 "$legacy" | awk '{print $1}')"

cp "$canonical" "$invalid_legacy"
ruby -rjson -e '
  path = ARGV.fetch(0)
  document = JSON.parse(File.read(path))
  document.fetch("gesture")["deadZonePoints"] = -1
  File.write(path, JSON.pretty_generate(document) + "\n")
' "$invalid_legacy"
invalid_hash=$(shasum -a 256 "$invalid_legacy" | awk '{print $1}')
if "$binary" doctor --config "$invalid_legacy" --benchmark-events 1 --json > "$temporary_root/invalid-doctor.json" 2> "$temporary_root/invalid-doctor.err"; then
  printf '%s\n' "不正な旧設定を移行してdoctorを開始しました。" >&2
  exit 1
fi
test "$invalid_hash" = "$(shasum -a 256 "$invalid_legacy" | awk '{print $1}')"
grep -Eq 'gesture\.deadZonePoints' "$temporary_root/invalid-doctor.err"

printf '%s\n' '{"gesture":{"button3Mode":"unknown-mode"}}' > "$malformed"
malformed_hash=$(shasum -a 256 "$malformed" | awk '{print $1}')
if "$binary" doctor --config "$malformed" --benchmark-events 1 --json > "$temporary_root/malformed-doctor.json" 2> "$temporary_root/malformed-doctor.err"; then
  printf '%s\n' "decode不能な旧modeを受理しました。" >&2
  exit 1
fi
test "$malformed_hash" = "$(shasum -a 256 "$malformed" | awk '{print $1}')"
test -s "$temporary_root/malformed-doctor.err"

cp "$canonical" "$concurrent"
ruby -rjson -e '
  path = ARGV.fetch(0)
  document = JSON.parse(File.read(path))
  document.fetch("gesture")["button3Mode"] = "twoFingerSwipe"
  File.write(path, JSON.pretty_generate(document) + "\n")
' "$concurrent"
pids=""
for index in 1 2 3 4; do
  "$binary" doctor --config "$concurrent" --benchmark-events 1 --json > "$temporary_root/concurrent-$index.json" &
  pids="$pids $!"
done
for pid in $pids; do
  wait "$pid"
done
jq -e '
  .gesture == {
    "cancellation": {
      "maximumDuration": 10,
      "maximumInactivityInterval": 2
    }
  }
  and (keys | sort) == [
    "gesture",
    "requireMatchingTargetDevice",
    "targetDeviceAssociation",
    "targetDevices"
  ]
' "$concurrent" >/dev/null

mkdir -p "$(dirname "$locked")"
lock_ready="$temporary_root/lock-ready"
ruby -e '
  lock = File.open(ARGV.fetch(0), File::RDWR | File::CREAT, 0600)
  lock.flock(File::LOCK_EX)
  File.write(ARGV.fetch(1), "ready")
  sleep 1
' "$locked.lock" "$lock_ready" &
lock_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  test -f "$lock_ready" && break
  sleep 0.05
done
test -f "$lock_ready"
"$binary" init-config --out "$locked" > "$temporary_root/locked-init.out" &
writer_pid=$!
sleep 0.2
if ! kill -0 "$writer_pid" 2>/dev/null; then
  printf '%s\n' "別processの設定lockを待たずに書き込みました。" >&2
  wait "$lock_pid"
  wait "$writer_pid"
  exit 1
fi
wait "$lock_pid"
wait "$writer_pid"
jq -e '.gesture.cancellation.maximumDuration == 10' "$locked" >/dev/null
test "$(stat -f '%Lp' "$locked.lock")" = "600"

mkdir -p "$(dirname "$symlink_locked")"
lock_victim="$temporary_root/lock-victim"
printf '%s\n' sentinel > "$lock_victim"
ln -s "$lock_victim" "$symlink_locked.lock"
if "$binary" init-config --out "$symlink_locked" > "$temporary_root/symlink-lock.out" 2> "$temporary_root/symlink-lock.err"; then
  printf '%s\n' "symlinkの設定lock fileを受理しました。" >&2
  exit 1
fi
test "$(cat "$lock_victim")" = sentinel
test ! -e "$symlink_locked"
test -s "$temporary_root/symlink-lock.err"

"$binary" doctor --config "$created" --benchmark-events 1 --json > "$temporary_root/created-doctor.json"
test -f "$created"
jq -e '
  .gesture.cancellation.maximumDuration == 10
  and .gesture.cancellation.maximumInactivityInterval == 2
  and .targetDevices == [{"productContains":"Nape Pro"}]
  and .requireMatchingTargetDevice == true
' "$created" >/dev/null

cp "$canonical" "$temporary_root/invalid-canonical.json"
ruby -rjson -e '
  path = ARGV.fetch(0)
  document = JSON.parse(File.read(path))
  document.fetch("gesture").fetch("cancellation")["maximumDuration"] = -1
  File.write(path, JSON.pretty_generate(document) + "\n")
' "$temporary_root/invalid-canonical.json"
"$binary" doctor --config "$temporary_root/invalid-canonical.json" --benchmark-events 1 --json > "$temporary_root/invalid-canonical-doctor.json"
jq -e '
  .runtimeReadiness.ready == false
  and any(.runtimeReadiness.failures[]; .code == "settings.invalid")
  and any(.settingsValidationIssues[]; .path == "gesture.cancellation.maximumDuration")
' "$temporary_root/invalid-canonical-doctor.json" >/dev/null
if "$binary" check-config --config "$temporary_root/invalid-canonical.json" > "$temporary_root/invalid-check.out" 2> "$temporary_root/invalid-check.err"; then
  printf '%s\n' "runtime用設定検証が負の最大継続時間を受理しました。" >&2
  exit 1
fi
grep -Eq 'gesture\.cancellation\.maximumDuration' "$temporary_root/invalid-check.err"

printf '%s\n' "設定store安定性テストに成功しました。"
