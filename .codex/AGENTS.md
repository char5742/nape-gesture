# .codex/AGENTS.md

このディレクトリは repo-local な Codex ハーネス設定を置く場所です。ここにあるルールは補助ガードであり、最終判断は root の `AGENTS.md`、関連 ADR、CI、証跡スクリプトを正とします。

## ルールファイル

- `rules/project.rules` は、誤実行時の被害が大きいコマンドを Codex 側で止めるための補助ルールです。
- ルールは Codex の実行環境やバージョンに依存する可能性があるため、これだけを安全性の根拠にしないでください。
- 禁止事項は root の `AGENTS.md` にも必ず残し、CI や review checklist で検出できるものは機械検証へ寄せます。

## 更新方針

- このディレクトリに秘密値、個人 token、ローカル絶対パス依存の設定を入れない。
- プロジェクト全体に影響するハーネス変更は、必要に応じて ADR または `docs/parallel-development.md` へ理由を残す。
- hook でしか守れない運用は避け、`sh scripts/...`、CI、PR template、review checklist で再現できる形にする。
