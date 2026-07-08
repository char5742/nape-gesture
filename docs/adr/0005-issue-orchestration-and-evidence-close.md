# ADR-0005: Issue による orchestration と証跡付き close 方針

- 状態: 採択
- 日付: 2026-07-08

## 背景

このリポジトリでは、実装、検証、実機確認、配布準備を複数の Issue とサブエージェントに分けて進める。
Issue が単なる TODO になると、依存関係、完了条件、証跡、未検証事項が失われ、最終的な完成判定が曖昧になる。

## 決定

- Issue は orchestration の単位として扱う。
- 各 Issue には、目的、完了条件、依存関係、並列化可否、必要な証跡を持たせる。
- サブエージェントへの投入は、Issue の所有範囲と完了条件を明示して行う。
- PR は対応 Issue を明記し、必要に応じて `Closes #NN` を本文に含める。
- `Closes #NN` を使う場合でも、merge 前レビューでは Issue の完了条件と PR の検証結果を照合する。
- Issue を手動 close する場合は、`gh api` で証跡コメントを投稿してから close する。
- 証跡コメントには、次を含める。
  - 対応 PR URL
  - merge された commit または検証対象 commit
  - 実行した検証
  - 未検証事項
  - 後続 Issue または残る外部ブロッカー
- 実機や権限が必要な項目は、dry-run やモックだけで完了扱いにしない。
- 完成判定は、個別 Issue の close 数ではなく、`docs/verification.md` と関連 ADR の証跡がそろっているかで判断する。

## 影響

- サブエージェントの作業結果を、Issue、PR、commit、検証ログで追跡できる。
- close 済み Issue が、後続作業の前提として使える。
- 外部依存の未検証事項を完了済みとして扱う事故を避けられる。

## 関連

- [GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [並列開発運用](../parallel-development.md)
- [検証方針](../verification.md)
