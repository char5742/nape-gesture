#!/bin/sh

# verify-bundle の plist 型・固定 identity・filesystem 境界・CLI parse 契約を検査する。
# 実行ビットは不要です。`sh scripts/test-verify-bundle.sh <binary> <bundle> [artifact-dir]` で実行してください。

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

cd "$repo_root"

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  printf '%s\n' "使い方: sh scripts/test-verify-bundle.sh <nape-gesture binary> <source.app> [artifact-dir]" >&2
  exit 2
fi

binary=$1
source_app=$2
artifact_dir=${3:-.build/verify-bundle-contract}

case "$binary" in
  /*) ;;
  *) binary="$repo_root/$binary" ;;
esac
case "$source_app" in
  /*) ;;
  *) source_app="$repo_root/$source_app" ;;
esac
case "$artifact_dir" in
  /*) ;;
  *) artifact_dir="$repo_root/$artifact_dir" ;;
esac

if [ ! -x "$binary" ]; then
  printf '%s\n' "nape-gesture binary を実行できません: $binary" >&2
  exit 1
fi
if [ ! -d "$source_app" ]; then
  printf '%s\n' "検証元 bundle がありません: $source_app" >&2
  exit 1
fi
case "$artifact_dir" in
  /|"")
    printf '%s\n' "artifact directory が不正です: $artifact_dir" >&2
    exit 1
    ;;
esac

rm -rf "$artifact_dir"
mkdir -p "$artifact_dir"
summary_file="$artifact_dir/summary.log"
: > "$summary_file"

workspace=$(mktemp -d "${TMPDIR:-/tmp}/nape-verify-bundle.XXXXXX")
cleanup() {
  rm -rf "$workspace"
}
trap cleanup EXIT HUP INT TERM

report_success() {
  printf '成功: %s\n' "$1"
  printf '成功: %s\n' "$1" >> "$summary_file"
}

fail() {
  printf '失敗: %s\n' "$1" >&2
  printf '失敗: %s\n' "$1" >> "$summary_file"
  exit 1
}

run_success() {
  name=$1
  shift
  stdout_path="$artifact_dir/$name.stdout.log"
  stderr_path="$artifact_dir/$name.stderr.log"

  if "$@" > "$stdout_path" 2> "$stderr_path"; then
    report_success "$name"
    return
  else
    status=$?
  fi

  sed -n '1,80p' "$stderr_path" >&2
  fail "$name が終了コード $status で失敗しました。"
}

run_expected_failure() {
  name=$1
  expected_stderr=$2
  shift 2
  stdout_path="$artifact_dir/$name.stdout.log"
  stderr_path="$artifact_dir/$name.stderr.log"

  if "$@" > "$stdout_path" 2> "$stderr_path"; then
    fail "$name が期待に反して成功しました。"
  else
    status=$?
  fi

  if [ "$status" -eq 0 ]; then
    fail "$name の終了コードが 0 です。"
  fi
  if ! grep -F -- "$expected_stderr" "$stderr_path" >/dev/null; then
    sed -n '1,80p' "$stderr_path" >&2
    fail "$name の stderr に '$expected_stderr' がありません。"
  fi
  report_success "$name (expected failure, exit=$status)"
}

assert_log_contains() {
  name=$1
  log_path=$2
  expected=$3
  if ! grep -F -- "$expected" "$log_path" >/dev/null; then
    sed -n '1,80p' "$log_path" >&2
    fail "$name に '$expected' がありません。"
  fi
  report_success "$name"
}

assert_fixed_plist_value() {
  key=$1
  expected_type=$2
  expected_value=$3
  stdout_path="$artifact_dir/oracle-$key.stdout.log"
  stderr_path="$artifact_dir/oracle-$key.stderr.log"

  if ! /usr/bin/plutil -extract "$key" raw -expect "$expected_type" -o - \
    "$source_app/Contents/Info.plist" > "$stdout_path" 2> "$stderr_path"; then
    sed -n '1,80p' "$stderr_path" >&2
    fail "$key の固定値 oracle で $expected_type 型を確認できません。"
  fi
  actual_value=$(sed -n '1p' "$stdout_path")
  if [ "$actual_value" != "$expected_value" ]; then
    fail "$key の固定値 oracle が不一致です: actual=$actual_value expected=$expected_value"
  fi
  report_success "$key=$expected_value ($expected_type) 固定値 oracle"
}

fresh_bundle() {
  fixture_name=$1
  fixture_app="$workspace/$fixture_name.app"
  fixture_plist="$fixture_app/Contents/Info.plist"
  fixture_executable="$fixture_app/Contents/MacOS/nape-gesture"
  rm -rf "$fixture_app"
  cp -R "$source_app" "$fixture_app"
}

run_success "positive-bundle" "$binary" verify-bundle "$source_app"

# 生成側と verifier が共有する Swift 定数には依存しない、固定値かつ exact type の正例 oracle。
assert_fixed_plist_value "CFBundleIdentifier" "string" "dev.char5742.nape-gesture"
assert_fixed_plist_value "CFBundleExecutable" "string" "nape-gesture"
assert_fixed_plist_value "CFBundleName" "string" "Nape Gesture"
assert_fixed_plist_value "CFBundleDisplayName" "string" "Nape Gesture"
assert_fixed_plist_value "LSUIElement" "bool" "false"

assert_log_contains \
  "CFBundleIdentifier 固定値出力" \
  "$artifact_dir/positive-bundle.stdout.log" \
  "Info.plist: CFBundleIdentifier=dev.char5742.nape-gesture"
assert_log_contains \
  "CFBundleExecutable 固定値出力" \
  "$artifact_dir/positive-bundle.stdout.log" \
  "Info.plist: CFBundleExecutable=nape-gesture"
assert_log_contains \
  "CFBundleName 固定値出力" \
  "$artifact_dir/positive-bundle.stdout.log" \
  "Info.plist: CFBundleName=Nape Gesture"
assert_log_contains \
  "CFBundleDisplayName 固定値出力" \
  "$artifact_dir/positive-bundle.stdout.log" \
  "Info.plist: CFBundleDisplayName=Nape Gesture"
assert_log_contains \
  "LSUIElement 固定値出力" \
  "$artifact_dir/positive-bundle.stdout.log" \
  "Info.plist: LSUIElement=false"

while IFS='|' read -r key alternate fixture_prefix
do
  fresh_bundle "$fixture_prefix-alternate"
  /usr/bin/plutil -replace "$key" -string "$alternate" "$fixture_plist"
  run_expected_failure \
    "$fixture_prefix-alternate" \
    "$key" \
    "$binary" verify-bundle "$fixture_app"

  fresh_bundle "$fixture_prefix-missing"
  /usr/bin/plutil -remove "$key" "$fixture_plist"
  run_expected_failure \
    "$fixture_prefix-missing" \
    "$key" \
    "$binary" verify-bundle "$fixture_app"

  fresh_bundle "$fixture_prefix-integer"
  /usr/bin/plutil -replace "$key" -integer 0 "$fixture_plist"
  run_expected_failure \
    "$fixture_prefix-integer" \
    "$key" \
    "$binary" verify-bundle "$fixture_app"
done <<'EOF'
CFBundleIdentifier|dev.char5742.invalid-nape-gesture|bundle-identifier
CFBundleExecutable|invalid-nape-gesture|bundle-executable
CFBundleName|Invalid Nape Gesture|bundle-name
CFBundleDisplayName|Invalid Nape Gesture|bundle-display-name
EOF

fresh_bundle "ls-ui-element-integer-zero"
/usr/bin/plutil -replace LSUIElement -integer 0 "$fixture_plist"
run_expected_failure \
  "ls-ui-element-integer-zero" \
  "LSUIElement" \
  "$binary" verify-bundle "$fixture_app"

fresh_bundle "ls-ui-element-real-zero"
/usr/bin/plutil -replace LSUIElement -float 0 "$fixture_plist"
run_expected_failure \
  "ls-ui-element-real-zero" \
  "LSUIElement" \
  "$binary" verify-bundle "$fixture_app"

fresh_bundle "ls-ui-element-string-false"
/usr/bin/plutil -replace LSUIElement -string false "$fixture_plist"
run_expected_failure \
  "ls-ui-element-string-false" \
  "LSUIElement" \
  "$binary" verify-bundle "$fixture_app"

fresh_bundle "ls-ui-element-missing"
/usr/bin/plutil -remove LSUIElement "$fixture_plist"
run_expected_failure \
  "ls-ui-element-missing" \
  "LSUIElement" \
  "$binary" verify-bundle "$fixture_app"

fresh_bundle "ls-ui-element-true"
/usr/bin/plutil -replace LSUIElement -bool true "$fixture_plist"
run_expected_failure \
  "ls-ui-element-true" \
  "LSUIElement" \
  "$binary" verify-bundle "$fixture_app"

fresh_bundle "malformed-plist"
printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<plist version="1.0"><dict><key>CFBundleIdentifier</key>' \
  > "$fixture_plist"
run_expected_failure \
  "malformed-plist" \
  "Info.plist を解析できません" \
  "$binary" verify-bundle "$fixture_app"

fresh_bundle "non-dictionary-plist-root"
printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0">' \
  '<array><string>Nape Gesture</string></array>' \
  '</plist>' \
  > "$fixture_plist"
run_expected_failure \
  "non-dictionary-plist-root" \
  "Info.plist の形式が辞書ではありません" \
  "$binary" verify-bundle "$fixture_app"

fresh_bundle "bundle-root-symlink"
root_symlink_target="$workspace/bundle-root-symlink-target.app"
mv "$fixture_app" "$root_symlink_target"
ln -s "$root_symlink_target" "$fixture_app"
run_expected_failure \
  "bundle-root-symlink" \
  "アプリバンドル rootに symlink" \
  "$binary" verify-bundle "$fixture_app"

fresh_bundle "contents-symlink"
contents_symlink_target="$workspace/contents-symlink-target"
mv "$fixture_app/Contents" "$contents_symlink_target"
ln -s "$contents_symlink_target" "$fixture_app/Contents"
run_expected_failure \
  "contents-symlink" \
  "Contentsに symlink" \
  "$binary" verify-bundle "$fixture_app"

fresh_bundle "info-plist-symlink"
info_plist_symlink_target="$workspace/info-plist-symlink-target.plist"
mv "$fixture_plist" "$info_plist_symlink_target"
ln -s "$info_plist_symlink_target" "$fixture_plist"
run_expected_failure \
  "info-plist-symlink" \
  "Info.plistに symlink" \
  "$binary" verify-bundle "$fixture_app"

fresh_bundle "executable-directory"
rm "$fixture_executable"
mkdir "$fixture_executable"
run_expected_failure \
  "executable-directory" \
  "実行ファイルが通常ファイルではありません" \
  "$binary" verify-bundle "$fixture_app"

fresh_bundle "executable-external-symlink"
rm "$fixture_executable"
ln -s /usr/bin/true "$fixture_executable"
run_expected_failure \
  "executable-external-symlink" \
  "実行ファイルに symlink" \
  "$binary" verify-bundle "$fixture_app"
assert_log_contains \
  "executable bundle containment" \
  "$artifact_dir/executable-external-symlink.stderr.log" \
  "実行ファイルが bundle 内に収まっていません"

fresh_bundle "macos-external-symlink"
macos_symlink_target="$workspace/macos-symlink-target"
mv "$fixture_app/Contents/MacOS" "$macos_symlink_target"
ln -s "$macos_symlink_target" "$fixture_app/Contents/MacOS"
run_expected_failure \
  "macos-external-symlink" \
  "Contents/MacOSに symlink" \
  "$binary" verify-bundle "$fixture_app"

run_expected_failure \
  "unknown-option" \
  "未知の option" \
  "$binary" verify-bundle --require-signatur "$source_app"
run_expected_failure \
  "missing-bundle-path" \
  "アプリバンドル の値がありません" \
  "$binary" verify-bundle
run_expected_failure \
  "extra-positional" \
  "余分な引数" \
  "$binary" verify-bundle "$source_app" extra.app
run_expected_failure \
  "duplicate-option" \
  "option が重複" \
  "$binary" verify-bundle --require-signature --require-signature "$source_app"

printf '%s\n' "verify-bundle contract fixture: 全ケース成功"
