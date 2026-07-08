# ADR-0002: GitHub labels / milestones / Issue close 方針

- 状態: 採択
- 日付: 2026-07-08

## 背景

Issue、label、milestone の運用が揺れると、サブエージェントへの分担、レビュー順序、外部ブロッカーの扱いが追跡しにくくなる。
また、完了した Issue を証跡なしで close すると、なぜ完了扱いにしたかを後から確認できない。

## 決定

- label は `docs/github-issues.md` の初期セットを基準に、次の分類で使う。
  - `area:*`: 変更領域を示す。
  - `type:*`: feature、bug、research、qa など作業種別を示す。
  - `priority:*`: メインスレッドが統合順序を決めるための優先度を示す。
  - `parallel:ready`: サブエージェントへ独立投入しやすい Issue に付ける。
  - `blocked:external`: 実機、権限、外部状態など、ローカル変更だけでは完了できない Issue に付ける。
  - `need:human`: 人間の物理作業が最後の手段として必要な Issue に付ける。
- `need:human` は「人に確認してほしい」ではなく、純正トラックパッド操作、Nape Pro 実機操作、スリープ、抜き差し、権限変更など、自動化や dry-run では代替しきれない物理作業を表す。
- `need:human` は最後の手段として使う。CGEvent 投稿、dry-run、fixtures、ログ解析、Reference Target App、System Behavior Test で代替できる作業には先に自動化または半自動化を試す。
- `need:human` が付いた Issue でも、人間作業に依存しない前処理、検証ツール整備、ログ形式整備、dry-run 生成、解析ロジック改善はサブエージェントで先に進める。
- 人間作業が不要になった場合は、理由を Issue コメントへ残して `need:human` を外す。
- GitHub の既定 label は、この taxonomy と重複するため未使用なら削除する。
- 新しい label を追加する場合は、先に ADR または `docs/github-issues.md` に分類上の理由を残す。
- milestone はリリースや完成判定に向かう段階を表す。単なる担当者や作業場所としては使わない。
- label、milestone、Issue の作成、更新、コメント、close は、基本的に `gh api` を使う。
- 再投入や再同期では、既存の title、label name、milestone title を先に取得し、差分だけを作成または更新する。
- Issue は完了条件を満たし、証跡コメントを残してから close する。
- 証跡コメントには、対応 PR、主要 commit、実行した検証、未検証事項、残る外部ブロッカーを含める。
- CI 失敗、必要な実機検証の未実施、所有範囲外の未説明な変更がある場合は、完了扱いで close しない。

## 影響

- Issue の状態は、実装進捗だけでなく検証と証跡の有無で判断する。
- close 済み Issue は、後から PR と検証結果をたどれる状態になる。
- 外部ブロッカーが残る Issue は、完了に見せず `blocked:external` と未検証事項を明示する。

## 関連

- [Issue による orchestration と証跡付き close 方針](0005-issue-orchestration-and-evidence-close.md)
- [nape-gesture Issue 管理一覧](../github-issues.md)
- [リポジトリ運用記録](../repository-setup.md)
