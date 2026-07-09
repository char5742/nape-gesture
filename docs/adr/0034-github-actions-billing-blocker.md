# ADR-0034: GitHub Actions 課金ブロッカーの扱い

- 状態: 採択
- 日付: 2026-07-10

## 背景

PR の GitHub Actions が、workflow の実行前に GitHub アカウントの支払い失敗または spending limit によって失敗することがある。
この失敗はコード、依存、runner 設定の問題ではないが、PR 上では通常の CI failure と同じように見えるため、未対応の実装不具合として誤読されやすい。

## 決定

- check-run annotation に `The job was not started because recent account payments have failed or your spending limit needs to be increased` が含まれる場合、その CI failure は GitHub Actions 課金ブロッカーとして扱う。
- 課金ブロッカーは外部状態なので、該当 PR または Issue には `blocked:external` を付ける。
- GitHub Billing / spending limit の復旧は、GitHub アカウント側で人間が作業する必要があるため、集約 Issue には `need:human` を付ける。
- 影響を受ける PR には、失敗した run URL、job URL、annotation、集約 Issue を PR 本文またはレビューコメントに残す。
- 課金ブロッカーの集約先は Issue #91 とする。新しい PR が同じ annotation で止まった場合は、Issue #91 へ追記する。
- ローカル検証と completion evidence は継続するが、GitHub Actions の代替として merge 条件を満たした扱いにはしない。
- 課金ブロッカーが復旧したら、影響 PR の CI を再実行し、成功を確認してから `blocked:external` と `need:human` の必要性を再判定する。
- PR が draft の場合は、課金ブロッカー復旧後に CI を再実行できる状態へ戻してから ready 化、再レビュー、merge 判断を行う。

## 影響

- CI failure の原因を、コード不具合と GitHub アカウント外部状態に分けて追跡できる。
- 人間作業は GitHub Billing / spending limit の復旧に限定され、レビュー待ちや判断待ちを `need:human` にしない方針を維持できる。
- 課金ブロッカー中も、メインスレッドとサブエージェントはローカルで可能な検証、証跡収集、独立 PR の準備を進められる。

## 関連

- [ADR-0002: GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [ADR-0004: メインスレッドとサブエージェントの役割分担、PR レビュー、merge 判断](0004-main-thread-subagent-pr-and-merge-roles.md)
- [ADR-0005: Issue による orchestration と証跡付き close 方針](0005-issue-orchestration-and-evidence-close.md)
- [PR レビューチェックリスト](../pr-review-checklist.md)
