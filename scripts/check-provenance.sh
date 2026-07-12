#!/bin/sh

# repo-localの正本方針と、実装上必要な実依存識別子・法定通知境界に関する必須文言の退行を確認する。
# これは法的な完全証明や固有名の自動判定ではなく、方針削除を早期に止めるための機械ガードです。
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

require_text \
  "README.md" \
  "第三者プロジェクトのコード、定数、field番号、状態遷移、係数、調整値は取り込みません。" \
  "README に由来方針を明記する"

require_text \
  "AGENTS.md" \
  "第三者プロジェクト由来のコード、定数、状態遷移、係数をコピーしない。実装契約とパラメータはApple公式資料、Apple OSS、このリポジトリの純正trackpad / Nape Proログから再導出する。" \
  "AGENTS にrepo-localの正本方針を残す"

require_text \
  "AGENTS.md" \
  "実装上必要な実依存の識別子と法定通知を除き、README、実装、コメント、テスト名、ユーザー向け文書へ不要な第三者プロジェクトの固有名、コンポーネント名、参照実装由来と読める表現を残さない。" \
  "AGENTS に製品surfaceの識別子境界を残す"

require_text \
  ".github/pull_request_template.md" \
  "第三者プロジェクトのコード、定数、field番号、状態遷移、係数、調整値をコピーしていない" \
  "PR template に由来確認を残す"

require_text \
  "docs/requirements.md" \
  "実装contractとパラメータはApple公式資料、Apple OSS、自前ログから再導出する" \
  "requirements にrepo-localの正本方針を残す"

require_text \
  "docs/requirements.md" \
  "実装と製品surfaceに置く外部固有名は、実装上必要な実依存の識別子と法定通知に限定する" \
  "requirements に実依存・法定通知の境界を残す"

require_text \
  "docs/pr-review-checklist.md" \
  "実装上必要な実依存の識別子と法定通知を除き、README、実装、コメント、テスト名、ユーザー向け文書に不要な第三者プロジェクトの固有名、コンポーネント名、参照実装由来と読める表現がない" \
  "PR review checklist に製品surfaceの監査項目を残す"

require_text \
  "docs/pr-review-checklist.md" \
  "第三者プロジェクト由来のコード、field番号、定数、状態遷移、係数、調整値を持ち込んでいる" \
  "PR review checklist に由来混入の差し戻し基準を残す"

if [ "$failure_count" -ne 0 ]; then
  printf '%s\n' "provenance check failed: $failure_count 件の問題があります。" >&2
  exit 1
fi

printf '%s\n' "provenance check passed"
