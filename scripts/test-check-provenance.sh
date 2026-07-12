#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/nape-provenance-policy-test.XXXXXX")
temporary_root=$(CDPATH= cd -- "$temporary_root" && pwd -P)
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM

fixture_root="$temporary_root/repository"
mkdir -p "$fixture_root/.github" "$fixture_root/docs" "$fixture_root/scripts"

cp "$repo_root/Package.swift" "$fixture_root/Package.swift"
cp "$repo_root/README.md" "$fixture_root/README.md"
cp "$repo_root/AGENTS.md" "$fixture_root/AGENTS.md"
cp "$repo_root/.github/pull_request_template.md" "$fixture_root/.github/pull_request_template.md"
cp "$repo_root/docs/requirements.md" "$fixture_root/docs/requirements.md"
cp "$repo_root/docs/pr-review-checklist.md" "$fixture_root/docs/pr-review-checklist.md"
cp "$repo_root/scripts/check-provenance.sh" "$fixture_root/scripts/check-provenance.sh"
git -C "$fixture_root" init -q

positive_output=$(sh "$fixture_root/scripts/check-provenance.sh" 2>&1) || {
  printf '%s\n' "完全な方針fixtureでprovenance checkが失敗しました。" >&2
  printf '%s\n' "$positive_output" >&2
  exit 1
}
if [ "$positive_output" != "provenance check passed" ]; then
  printf '%s\n' "完全な方針fixtureの出力が一致しません: $positive_output" >&2
  exit 1
fi

printf '%s\n' "# AGENTS.md" > "$fixture_root/AGENTS.md"
if sh "$fixture_root/scripts/check-provenance.sh" > "$temporary_root/missing-policy.stdout" 2> "$temporary_root/missing-policy.stderr"; then
  printf '%s\n' "必須方針を欠くfixtureをprovenance checkが受理しました。" >&2
  exit 1
fi
if ! grep -Fq "不足: AGENTS にrepo-localの正本方針を残す" "$temporary_root/missing-policy.stderr"; then
  printf '%s\n' "必須方針欠落の診断が一致しません。" >&2
  cat "$temporary_root/missing-policy.stderr" >&2
  exit 1
fi

printf '%s\n' "provenance policy guard tests passed"
