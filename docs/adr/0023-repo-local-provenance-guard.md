# ADR-0023: repo-local 由来ガード

- 状態: 採択
- 日付: 2026-07-09

## 背景

Nape Gestureのevent contractとパラメータは、Apple公式資料、Apple OSS、このリポジトリの純正trackpad / Nape Proログを正本とする。
実装と製品surfaceに置く外部固有名は、実装上必要な実依存の識別子と法定通知に限定する。実際に利用する依存のimport名、module / API名、ライセンス上必要な文書は除外対象ではなく、参照実装として不要な外部固有名を持ち込むことだけを禁止する。

既知の外部プロジェクト名、コンポーネント名、作者名、domain、URLをdenylistとして保持すると、guard自体が特定プロジェクト専用の参照を残す。任意の外部固有名を一般的なpatternで正確に判定することもできない。このリポジトリの自動検証では、一般化した正本方針と識別子境界の必須文言を確認し、個別の固有名監査はtracked files全体のレビューで行う。

## 決定

- `scripts/check-provenance.sh` を追加し、`sh scripts/check-provenance.sh` で実行する。
- `scripts/test-check-provenance.sh` は隔離した一時リポジトリで、必須文言が揃う正常系と欠落時の失敗を検証する。
- CI は build / test 前に provenance guard を実行する。
- completion evidence は `provenance/check-provenance.log` と `provenance/test-check-provenance.log` に、guard本体と回帰テストの実行結果を独立して保存する。
- guard は README、AGENTS、requirements、PR template、PR review checklist に、一般化したrepo-local由来方針と、実装上必要な実依存識別子を許容する境界が残っていることを確認する。
- guard に特定の外部プロジェクトを識別する語断片、コンポーネント名、作者名、domain、URL、表記揺れpatternを持たせず、固有名denylistのallowlistも設けない。
- 実依存または派生物を追加した場合は、その利用に必要なimport名、module / API名、設定識別子と、`THIRD_PARTY_NOTICES.md`や配布通知に必要な固有名、著作権表示、通知を残す。この境界を不要な外部参照と混同しない。
- README、実装、コメント、テスト名、ユーザー向け文書を含むtracked files全体の不要な外部固有名監査は、PRレビューと完成判定で明示的に行う。

## 影響

- 一般化した正本方針やレビュー項目の削除はCIで止められる。
- このguardは任意の外部固有名の自動検出や法的な非侵害証明ではない。採用根拠の追跡、tracked files全体のPRレビュー、テスト、ログからの再導出を補助する機械チェックとして扱う。
- 新しい依存関係または派生物を追加する場合は、必要な著作権表示や由来通知を消さず、先にライセンス要件、ADR、通知方針、製品surfaceとの境界を更新する。
- 完成判定では、ライセンス / 由来行の機械証跡として採用するが、公開配布物の最終目視や法務判断が必要な場合は別の人間作業として扱う。

## 関連

- [25F80のfinger count付きtrackpad入力compatibility contract](0043-trackpad-scroll-product-output.md)
- [buttonを指本数へ固定しイベント量をtrackpad入力へ置換する](0049-fixed-button-to-finger-count-trackpad-input.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [PR レビューとマージ判断](../pr-review-checklist.md)
- [サードパーティ通知](../../THIRD_PARTY_NOTICES.md)
