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

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/nape-gesture-settings-gui-smoke.XXXXXX")
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM

config="$temporary_root/config.json"
snapshot="$temporary_root/gui-smoke.json"

"$binary" init-config --out "$config" >/dev/null
ruby -rjson -e '
  path = ARGV.fetch(0)
  document = JSON.parse(File.read(path))
  document.fetch("gesture")["buttonAssignments"] = {
    "button3" => "pinch",
    "button4" => "twoFingerScrollSwipe",
    "button5" => "threeFingerSystemSwipe"
  }
  File.write(path, JSON.pretty_generate(document) + "\n")
' "$config"

config_hash=$(shasum -a 256 "$config" | awk '{print $1}')
"$binary" gui-smoke --config "$config" --json --assert > "$snapshot"
test "$config_hash" = "$(shasum -a 256 "$config" | awk '{print $1}')"

jq -e '
  .settingsWindowSmoke.buttonAssignmentSelections == [
    "4本指システムピンチ",
    "2本指スクロール／スワイプ",
    "3本指システムスワイプ"
  ]
  and .settingsWindowSmoke.buttonAssignmentOptionCounts == [3, 3, 3]
  and .settingsWindowSmoke.buttonAssignmentEditEnablesApply == true
  and .settingsWindowSmoke.buttonAssignmentRevertDisablesApply == true
  and .settingsWindowSmoke.buttonAssignmentIncludedInUpdatedSettings == true
  and .settingsWindowSmoke.initiallyApplyEnabled == false
' "$snapshot" >/dev/null

printf '%s\n' "設定GUI smokeテストに成功しました。"
