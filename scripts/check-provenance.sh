#!/bin/sh

# 既知の第三者プロジェクト固有名と、第三者コード非取込方針の退行を確認する。
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

name_part_1='[Mm][Aa][Cc]'
name_part_2='[Mm][Oo][Uu][Ss][Ee]'
name_part_3='[Ff][Ii][Xx]'
name_separator='[[:space:]_-]*'
full_name_pattern="${name_part_1}${name_separator}${name_part_2}${name_separator}${name_part_3}"
short_name_pattern="${name_part_2}${name_separator}${name_part_3}"
reverse_domain_pattern="com\\.[[:alnum:]._-]*${name_part_2}[[:alnum:]._-]*${name_part_3}"

specific_name_matches=$(
  git grep -n -I -E "${full_name_pattern}|${short_name_pattern}|${reverse_domain_pattern}" -- . 2>/dev/null || true
)
report_matches "禁止: 既知の第三者プロジェクト固有名が tracked files に含まれています。" "$specific_name_matches"

require_text \
  "README.md" \
  "第三者プロジェクトのコード、定数、field番号、状態遷移、係数、調整値は取り込みません。" \
  "README に由来方針を明記する"

require_text \
  ".github/pull_request_template.md" \
  "第三者プロジェクトのコード、定数、field番号、状態遷移、係数、調整値をコピーしていない" \
  "PR template に由来確認を残す"

require_text \
  "docs/pr-review-checklist.md" \
  "第三者プロジェクト由来のコード、field番号、定数、状態遷移、係数、調整値を持ち込んでいる" \
  "PR review checklist に由来混入の差し戻し基準を残す"

if [ "$failure_count" -ne 0 ]; then
  printf '%s\n' "provenance check failed: $failure_count 件の問題があります。" >&2
  exit 1
fi

printf '%s\n' "provenance check passed"
