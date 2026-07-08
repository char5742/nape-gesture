# docs/AGENTS.md

`docs/` 配下は、会話や PR 本文だけに残すと失われる方針、検証、完成判定の正本を置く場所です。実装の都合に合わせて証跡要件を弱めないでください。

## 文書更新

- 継続運用に影響する判断は、必要に応じて ADR に残す。
- 同じ方針を複数文書へ重複させず、正本文書へのリンクで示す。
- 実機、TCC、公証、人間作業が必要な項目は、dry-run や fixture の結果と明確に分ける。
- 完成判定は [completion-checklist.md](completion-checklist.md) を正本とし、未検証事項を完了扱いにしない。
- 検証手順を変えた場合は [verification.md](verification.md)、PR review 条件を変えた場合は [pr-review-checklist.md](pr-review-checklist.md) を合わせて更新する。

## 検証

- docs のみの変更でも、`git diff --check` を実行する。
- markdown link、Issue / PR URL、artifact path、コマンド例が古くなっていないか確認する。
- コマンド例に `chmod` を追加しない。スクリプトは `sh scripts/<name>.sh` で実行する形にする。
