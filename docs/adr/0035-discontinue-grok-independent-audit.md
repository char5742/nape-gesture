# ADR-0035: Grokによる独立監査を廃止する

- 状態: 採択
- 日付: 2026-07-11

## 背景

Grok CLIをUI / UX発散、文言確認、第三者視点、PR差分レビューの補助に使う運用を採択していた。

実運用では、メインスレッドが持つコードベース、Issue、検証証跡、ユーザー要件の文脈より情報量が少なく、独立監査の出力が判断精度を上げずノイズになる。レビュー経路を増やすことで採否作業と証跡管理も増える。

## 決定

- Grok CLIによる独立監査、補助レビュー、UI / UX発散、文言確認、PR差分レビューを行わない。
- Grokの出力を設計判断、Issue要件、PR review、merge判断、完成判定、CI gate、runtime証跡に使わない。
- 新しい`artifacts/grok-review/`証跡を作らない。既存証跡は履歴として残っていても現在の判断根拠にしない。
- メインスレッドが設計、実装、レビュー、Issue整理、merge判断の責任を持つ。
- 並列化が必要な場合は、同じリポジトリ方針と証跡契約を共有できる通常のCodexサブエージェントを使う。
- Grokを再採用する場合は、ユーザーの明示的な方針変更と新しいADRを必要とする。

## 影響

- [ADR-0027](0027-grok-cli-auxiliary-review.md)と[ADR-0029](0029-grok-operational-surface.md)は置換済みになる。
- `AGENTS.md`、並列開発文書、PR review checklistからGrok実行手順を除く。
- `$grok-auxiliary-review` skillが環境に存在しても、このリポジトリでは実行しない。
- 完成判定は従来どおりbuild、tests、CI、runtime log、実機証跡で行う。

## 関連

- [メインスレッドとサブエージェントの役割分担](0004-main-thread-subagent-pr-and-merge-roles.md)
- [Issueによるorchestration](0005-issue-orchestration-and-evidence-close.md)
- [並列開発運用](../parallel-development.md)
- [PR review checklist](../pr-review-checklist.md)
