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

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/nape-gesture-bundle-safety.XXXXXX")
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM

app="$temporary_root/NapeGesture.app"
rebundled_app="$temporary_root/Rebundled.app"
symlink_app="$temporary_root/SymlinkResource.app"
intermediate_symlink_app="$temporary_root/IntermediateSymlinkResource.app"
identity_app="$temporary_root/InvalidIdentity.app"
hostile_rebundled_app="$temporary_root/HostileRebundled.app"
signed_app="$temporary_root/Signed.app"
tampered_resource_app="$temporary_root/TamperedResource.app"
tampered_executable_app="$temporary_root/TamperedExecutable.app"
destination_symlink_app="$temporary_root/DestinationSymlink.app"
destination_symlink_target="$temporary_root/DestinationSymlinkTarget.app"
victim="$temporary_root/victim.app"

"$binary" bundle-app --out "$app" >/dev/null
"$binary" verify-bundle "$app" >/dev/null
if "$binary" verify-bundle --require-signature "$app" >/dev/null 2>&1; then
  printf '%s\n' "未署名bundleを署名必須検証が受理しました。" >&2
  exit 1
fi

cp -R "$app" "$signed_app"
codesign --force --deep --sign - "$signed_app" >/dev/null 2>&1
"$binary" verify-bundle --require-signature "$signed_app" >/dev/null

cp -R "$signed_app" "$tampered_resource_app"
printf '%s\n' "tampered" >> "$tampered_resource_app/Contents/Resources/LICENSE.txt"
if "$binary" verify-bundle --require-signature "$tampered_resource_app" >/dev/null 2>&1; then
  printf '%s\n' "署名後にresourceを改変したbundleを受理しました。" >&2
  exit 1
fi

cp -R "$signed_app" "$tampered_executable_app"
printf '\0' >> "$tampered_executable_app/Contents/MacOS/nape-gesture"
if "$binary" verify-bundle --require-signature "$tampered_executable_app" >/dev/null 2>&1; then
  printf '%s\n' "署名後に実行ファイルを改変したbundleを受理しました。" >&2
  exit 1
fi

before_inode=$(stat -f '%i' "$app")
"$binary" bundle-app --out "$app" --replace >/dev/null
after_inode=$(stat -f '%i' "$app")
if [ "$before_inode" = "$after_inode" ]; then
  printf '%s\n' "原子的swap後もbundle inodeが変化していません。" >&2
  exit 1
fi
if find "$temporary_root" -maxdepth 1 -name '.nape-gesture-bundle-*.app' -print -quit | grep -q .; then
  printf '%s\n' "bundle作成後に一時.appが残っています。" >&2
  exit 1
fi

mkdir "$victim"
printf '%s\n' sentinel > "$victim/sentinel.txt"
if "$binary" bundle-app --out "$victim" --replace >/dev/null 2>&1; then
  printf '%s\n' "Nape Gestureではない既存directoryを置換しました。" >&2
  exit 1
fi
if [ "$(cat "$victim/sentinel.txt")" != sentinel ]; then
  printf '%s\n' "拒否した既存directoryを変更しました。" >&2
  exit 1
fi

if (cd "$temporary_root" && "$binary" bundle-app --out --replace >/dev/null 2>&1); then
  printf '%s\n' "--outの欠落値を受理しました。" >&2
  exit 1
fi
if [ -e "$temporary_root/--replace" ]; then
  printf '%s\n' "--replaceを誤って出力pathとして作成しました。" >&2
  exit 1
fi
if "$binary" bundle-app --out "$temporary_root/Duplicate.app" --out "$temporary_root/Other.app" >/dev/null 2>&1; then
  printf '%s\n' "重複した--outを受理しました。" >&2
  exit 1
fi
if "$binary" bundle-app --out "$temporary_root/DuplicateReplace.app" --replace --replace >/dev/null 2>&1; then
  printf '%s\n' "重複した--replaceを受理しました。" >&2
  exit 1
fi
if "$binary" bundle-app --out "$temporary_root/not-an-app" >/dev/null 2>&1; then
  printf '%s\n' ".app以外の出力先を受理しました。" >&2
  exit 1
fi
if "$binary" verify-bundle --require-signatures "$app" >/dev/null 2>&1; then
  printf '%s\n' "未知の署名optionを無視しました。" >&2
  exit 1
fi

mkdir "$destination_symlink_target"
printf '%s\n' sentinel > "$destination_symlink_target/sentinel.txt"
ln -s "$destination_symlink_target" "$destination_symlink_app"
if "$binary" bundle-app --out "$destination_symlink_app" --replace >/dev/null 2>&1; then
  printf '%s\n' "symlinkのdestinationを置換しました。" >&2
  exit 1
fi
test -L "$destination_symlink_app"
test "$(cat "$destination_symlink_target/sentinel.txt")" = sentinel

"$binary" bundle-app --out "$symlink_app" >/dev/null
model_dir="$symlink_app/Contents/Resources/TrackpadContracts/25F80"
mv "$model_dir/scroll-output-model.json" "$model_dir/scroll-output-model.real.json"
ln -s scroll-output-model.real.json "$model_dir/scroll-output-model.json"
if "$binary" verify-bundle "$symlink_app" >/dev/null 2>&1; then
  printf '%s\n' "bundle外参照可能なsymlink resourceを受理しました。" >&2
  exit 1
fi

"$binary" bundle-app --out "$intermediate_symlink_app" >/dev/null
intermediate_contracts="$intermediate_symlink_app/Contents/Resources/TrackpadContracts"
mv "$intermediate_contracts/25F80" "$temporary_root/external-25F80"
ln -s "$temporary_root/external-25F80" "$intermediate_contracts/25F80"
if "$binary" verify-bundle "$intermediate_symlink_app" >/dev/null 2>&1; then
  printf '%s\n' "必須resourceの中間directory symlinkを受理しました。" >&2
  exit 1
fi

(cd "$temporary_root" && "$app/Contents/MacOS/nape-gesture" bundle-app --out "$rebundled_app" >/dev/null)
"$binary" verify-bundle "$rebundled_app" >/dev/null

hostile_directory="$temporary_root/hostile-working-directory"
mkdir "$hostile_directory"
ln -s /etc/hosts "$hostile_directory/LICENSE"
(cd "$hostile_directory" && "$app/Contents/MacOS/nape-gesture" bundle-app --out "$hostile_rebundled_app" >/dev/null)
cmp "$app/Contents/Resources/LICENSE.txt" "$hostile_rebundled_app/Contents/Resources/LICENSE.txt"
if cmp -s /etc/hosts "$hostile_rebundled_app/Contents/Resources/LICENSE.txt"; then
  printf '%s\n' "作業directoryの任意LICENSEを配布bundleへ混入しました。" >&2
  exit 1
fi

"$binary" bundle-app --out "$identity_app" >/dev/null
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier example.invalid.bundle' "$identity_app/Contents/Info.plist"
codesign --force --deep --sign - "$identity_app" >/dev/null 2>&1
if "$binary" verify-bundle --require-signature "$identity_app" >/dev/null 2>&1; then
  printf '%s\n' "異なるbundle identityを署名済みNape Gestureとして受理しました。" >&2
  exit 1
fi

executable_before=$(shasum -a 256 "$app/Contents/MacOS/nape-gesture")
plist_before=$(shasum -a 256 "$app/Contents/Info.plist")
model_before=$(shasum -a 256 "$app/Contents/Resources/TrackpadContracts/25F80/scroll-output-model.json")
if (cd "$temporary_root" && "$binary" bundle-app --out "$app" --replace >/dev/null 2>&1); then
  printf '%s\n' "必須resource不在の構築を成功扱いしました。" >&2
  exit 1
fi
test "$executable_before" = "$(shasum -a 256 "$app/Contents/MacOS/nape-gesture")"
test "$plist_before" = "$(shasum -a 256 "$app/Contents/Info.plist")"
test "$model_before" = "$(shasum -a 256 "$app/Contents/Resources/TrackpadContracts/25F80/scroll-output-model.json")"
"$binary" verify-bundle "$app" >/dev/null

printf '%s\n' "bundle app safety tests passed"
