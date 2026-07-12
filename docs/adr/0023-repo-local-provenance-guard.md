# ADR-0023: repo-local 由来ガード

- 状態: 採択
- 日付: 2026-07-09

## 背景

Nape Gestureのevent contractとパラメータは、Apple公式資料、Apple OSS、このリポジトリの純正trackpad / Nape Proログを正本とする。
製品surfaceの識別子は、Nape Gesture自身の仕様と、実際の依存関係・法定通知に必要なものへ限定する。文書だけでは、tracked filesへ不要な外部固有識別子が混入する退行をCIで止められない。

このリポジトリの自動検証では、tracked filesの中だけを対象に、正本方針と識別子境界を確認する早期検出ガードを置く。

## 決定

- `scripts/check-provenance.sh` を追加し、`sh scripts/check-provenance.sh` で実行する。
- CI は build / test 前に provenance guard を実行する。
- completion evidence は `provenance/check-provenance.log` として同じ guard の実行結果を保存する。
- guard は製品surfaceから除外する外部固有名について、大文字小文字、空白、hyphen、underscore の表記揺れと reverse-domain 形式を tracked files 全体で禁止する。
- guard 自身に固有名を残さないため、検出 pattern は固有名の各語要素から実行時に組み立て、allowlist を設けない。
- guard は README、PR template、PR review checklist に、一般化したrepo-local由来方針が残っていることも確認する。`THIRD_PARTY_NOTICES.md`と配布通知 fallbackは、実際に同梱する依存関係の通知だけに使う。

## 影響

- tracked filesだけで、正本方針の削除や不要な固有名の混入をCIで止められる。
- このguardは法的な非侵害証明ではない。採用根拠の追跡、PRレビュー、テスト、ログからの再導出を補助する機械チェックとして扱う。
- 新しい依存関係または派生物を追加する場合は、必要な著作権表示や由来通知を消さず、先にライセンス要件、ADR、通知方針、guardの例外範囲を更新する。
- 完成判定では、ライセンス / 由来行の機械証跡として採用するが、公開配布物の最終目視や法務判断が必要な場合は別の人間作業として扱う。

## 関連

- [ログ由来チューニング候補の再導出](0007-log-derived-tuning-parameters.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [PR レビューとマージ判断](../pr-review-checklist.md)
- [サードパーティ通知](../../THIRD_PARTY_NOTICES.md)
