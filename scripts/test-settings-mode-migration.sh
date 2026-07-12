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

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/nape-gesture-mode-migration.XXXXXX")
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM
config="$temporary_root/config.json"

"$binary" init-config --allow-unmatched --out "$config" >/dev/null
ruby -rjson -e '
  path = ARGV.fetch(0)
  document = JSON.parse(File.read(path))
  gesture = document.fetch("gesture")
  gesture["button3Mode"] = "scrollAndNavigate"
  gesture["button4Mode"] = "spacesAndMissionControl"
  gesture["button5Mode"] = "zoom"
  gesture["dragSensitivity"] = 1.75
  File.write(path, JSON.pretty_generate(document))
' "$config"

"$binary" check-config --config "$config" >/dev/null
ruby -rjson -e '
  document = JSON.parse(File.read(ARGV.fetch(0)))
  gesture = document.fetch("gesture")
  expected = {
    "button3Mode" => "twoFingerSwipe",
    "button4Mode" => "systemSwipe",
    "button5Mode" => "pinch"
  }
  expected.each do |key, value|
    abort("#{key}がcanonical modeへ移行されていません。") unless gesture.fetch(key) == value
  end
  abort("mode以外の設定値を保持していません。") unless gesture.fetch("dragSensitivity") == 1.75
  legacy = %w[scrollAndNavigate spacesAndMissionControl zoom]
  abort("旧mode値が再保存後も残っています。") unless (gesture.values & legacy).empty?
' "$config"

printf '%s\n' "settings mode migration tests passed"
