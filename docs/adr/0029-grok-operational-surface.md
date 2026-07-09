# ADR-0029: Grok 運用知見を AGENTS.md と Codex skill に同期する

- 状態: 採択
- 日付: 2026-07-09

## 背景

Grok CLI の使い方と役割は [ADR-0027](0027-grok-cli-auxiliary-review.md) に保存している。
ただし ADR は参照文書であり、毎回の作業開始時に必ず読まれるとは限らない。
Grok を UI / 文言 / 第三者視点レビューで継続利用するには、実行時に自然に効く入口にも同じ方針を置く必要がある。

## 決定

- repo 直下の `AGENTS.md` に、Grok の役割、既定オプション、証跡保存、採否責任を短く記載する。
- ローカル Codex skill として `$grok-auxiliary-review` を作成し、Grok CLI の非対話レビュー手順、保存物、権限境界を再利用可能にする。
- `AGENTS.md` は毎回の実務で効く短いルール、ADR は背景と方針の正本、skill は実行手順という役割に分ける。
- Grok CLI の挙動、既定 model、推奨 option、証跡保存ルール、採否責任を変更した場合は、ADR-0027、`AGENTS.md`、skill の同期を確認する。
- repo 外の個人 skill が存在しない環境では、ADR-0027 と `AGENTS.md` を fallback の正本として使う。

## 影響

- 新しい Codex スレッドやサブエージェントが、Grok を「便利な別人格」ではなく、権限を絞った補助レビュー担当として扱いやすくなる。
- Grok の知見が会話だけに残らず、実務入口、設計判断、実行手順の 3 層に残る。
- 個人 skill はローカル環境依存のため、PR の再現性が必要な判断は引き続き repo 内の ADR と `AGENTS.md` にも残す。

## 関連

- [ADR-0027: Grok CLI を補助レビューと発散に使う](0027-grok-cli-auxiliary-review.md)
- [ADR-0028: README を製品入口兼状態ダッシュボードとして扱う](0028-readme-product-dashboard.md)
- [並列開発運用](../parallel-development.md)
- [PR レビューチェックリスト](../pr-review-checklist.md)
