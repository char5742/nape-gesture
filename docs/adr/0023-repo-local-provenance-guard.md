# ADR-0023: repo-local 由来ガード

- 状態: 採択
- 日付: 2026-07-09

## 背景

Nape Gesture は第三者プロジェクトのコード、定数、field番号、状態遷移、係数、調整値をコピーしない。
この方針は README、PR template、PR review checklist に明記しているが、文書だけでは実装や設定へ誤って第三者固有の識別子を持ち込む退行を CI で止められない。

一方で、外部プロジェクトのソースを取得して比較するチェックは、由来混入の調査対象をむやみに広げる。
このリポジトリの自動検証では、外部ソースを読まず、tracked files の中だけを対象にした早期検出ガードを置く。

## 決定

- `scripts/check-provenance.sh` を追加し、`sh scripts/check-provenance.sh` で実行する。
- CI は build / test 前に provenance guard を実行する。
- completion evidence は `provenance/check-provenance.log` として同じ guard の実行結果を保存する。
- guard は既知の外部 reference implementation を特定する固有名について、大文字小文字、空白、hyphen、underscore の表記揺れと reverse-domain 形式を tracked files 全体で禁止する。
- guard 自身に固有名を残さないため、検出 pattern は固有名の各語要素から実行時に組み立て、allowlist を設けない。
- guard は README、PR template、PR review checklist に、一般化した第三者コード非取込方針が残っていることも確認する。`THIRD_PARTY_NOTICES.md`と配布通知 fallbackは、実際に同梱する依存関係の通知だけに使う。

## 影響

- 外部ソースを読まなくても、由来方針の削除や固有名の混入を CI で止められる。
- この guard は法的な非侵害証明ではない。コピーなし方針、PR レビュー、テスト、ログ由来の再導出方針を補助する機械チェックとして扱う。
- 第三者由来のコードまたは派生物を将来取り込む場合は、必要な著作権表示や由来通知を消さず、先にライセンス要件、ADR、通知方針、guard の例外範囲を更新する。
- 完成判定では、ライセンス / 由来行の機械証跡として採用するが、公開配布物の最終目視や法務判断が必要な場合は別の人間作業として扱う。

## 関連

- [ログ由来チューニング候補の再導出](0007-log-derived-tuning-parameters.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [PR レビューとマージ判断](../pr-review-checklist.md)
- [サードパーティ通知](../../THIRD_PARTY_NOTICES.md)
