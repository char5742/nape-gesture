#!/bin/sh

# Mac Mouse Fix 由来の識別子や説明が、許可した文書以外へ混入していないことを確認する。
# これは法的な完全証明ではなく、リポジトリ内の誤混入を早期に止めるための機械ガードです。
# 実行ビットは不要です。`sh scripts/check-provenance.sh` で実行してください。

set -u

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

cd "$repo_root" || {
  printf '%s\n' "リポジトリ root へ移動できません: $repo_root" >&2
  exit 1
}

git_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ ! -f Package.swift ] || [ "$git_root" != "$repo_root" ]; then
  printf '%s\n' "このスクリプトは nape-gesture のリポジトリ root で実行してください。" >&2
  exit 1
fi

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

report_matches() {
  title=$1
  matches=$2

  if [ -n "$matches" ]; then
    printf '%s\n' "$title" >&2
    printf '%s\n' "$matches" >&2
    record_failure
  fi
}

code_like_matches=$(
  git grep -n -I -E 'MacMouseFix|macMouseFix|macmousefix|mac-mouse-fix|mac_mouse_fix|MouseFix|mousefix|com\.[[:alnum:]._-]*mouse[[:alnum:]._-]*fix' -- . \
    ':(exclude)scripts/check-provenance.sh' \
    ':(exclude)docs/adr/0023-repo-local-provenance-guard.md' \
    ':(exclude)docs/adr/0036-emulate-trackpad-driver-output-events.md' 2>/dev/null || true
)
report_matches "禁止: Mac Mouse Fix 由来を示す code-like identifier が tracked files に含まれています。" "$code_like_matches"

phrase_matches=$(
  git grep -n -I 'Mac Mouse Fix' -- . \
    ':(exclude)README.md' \
    ':(exclude)THIRD_PARTY_NOTICES.md' \
    ':(exclude)docs/**' \
    ':(exclude).github/pull_request_template.md' \
    ':(exclude)scripts/check-provenance.sh' \
    ':(exclude)Sources/nape-gesture/BundleAppCommand.swift' 2>/dev/null || true
)
report_matches "禁止: Mac Mouse Fix への言及は、許可した方針文書または配布通知だけに置いてください。" "$phrase_matches"

implementation_phrase_matches=$(
  git grep -n -I 'Mac Mouse Fix' -- \
    Sources/NapeGestureCore \
    Sources/nape-gesture \
    ':(exclude)Sources/nape-gesture/BundleAppCommand.swift' 2>/dev/null || true
)
report_matches "禁止: 実装側に Mac Mouse Fix への言及を置かないでください。配布通知の同梱 fallback だけを例外にします。" "$implementation_phrase_matches"

require_text \
  "README.md" \
  "Mac Mouse Fix のコードや調整値は取り込みません。" \
  "README に由来方針を明記する"

require_text \
  "THIRD_PARTY_NOTICES.md" \
  "Mac Mouse Fix のソースコード、定数、状態遷移、調整値はこのプロジェクトへコピーしていません。" \
  "THIRD_PARTY_NOTICES にコピーなし方針を明記する"

require_text \
  "Sources/nape-gesture/BundleAppCommand.swift" \
  "Mac Mouse Fix のソースコード、定数、状態遷移、調整値はこのプロジェクトへコピーしていません。" \
  "バンドル fallback の THIRD_PARTY_NOTICES にコピーなし方針を含める"

require_text \
  ".github/pull_request_template.md" \
  "Mac Mouse Fix のコード、定数、状態遷移、係数をコピーしていない" \
  "PR template に由来確認を残す"

require_text \
  "docs/pr-review-checklist.md" \
  "Mac Mouse Fix 由来のコードや係数を持ち込んでいる" \
  "PR review checklist に由来混入の差し戻し基準を残す"

if [ "$failure_count" -ne 0 ]; then
  printf '%s\n' "provenance check failed: $failure_count 件の問題があります。" >&2
  exit 1
fi

printf '%s\n' "provenance check passed"
