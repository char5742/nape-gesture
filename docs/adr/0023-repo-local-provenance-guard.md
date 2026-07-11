# ADR-0023: repo-local 由来ガード

- 状態: 採択
- 日付: 2026-07-09

## 背景

Nape Gesture は Mac Mouse Fix のコード、定数、状態遷移、調整値をコピーしない。
この方針は README、`THIRD_PARTY_NOTICES.md`、PR template、PR review checklist に明記しているが、文書だけでは実装や設定へ誤って由来識別子を持ち込む退行を CI で止められない。

一方で、外部プロジェクトのソースを取得して比較するチェックは、由来混入の調査対象をむやみに広げる。
このリポジトリの自動検証では、外部ソースを読まず、tracked files の中だけを対象にした早期検出ガードを置く。

## 決定

- `scripts/check-provenance.sh` を追加し、`sh scripts/check-provenance.sh` で実行する。
- CI は build / test 前に provenance guard を実行する。
- completion evidence は `provenance/check-provenance.log` として同じ guard の実行結果を保存する。
- guard は `MacMouseFix`、`macmousefix`、`mac-mouse-fix`、`mac_mouse_fix`、`MouseFix`、`mousefix`、`com.*mouse.*fix` などの code-like identifier を tracked files で禁止する。
- 検出パターンを説明する`scripts/check-provenance.sh`とこのADR、設計調査の固定reference URLを記録する[ADR-0036](0036-emulate-trackpad-driver-output-events.md)だけをcode-like identifierのallowlistに入れる。ADR-0036の例外は文書URLに限り、実装identifierの例外にしない。
- `Mac Mouse Fix` という説明文は、README、`THIRD_PARTY_NOTICES.md`、`docs/**`、PR template、配布通知 fallback に限定する。
- `Sources/NapeGestureCore` と通常の実装ファイルには `Mac Mouse Fix` への言及を置かない。配布通知 fallback を持つ `BundleAppCommand.swift` だけを例外にする。
- guard は README、`THIRD_PARTY_NOTICES.md`、配布通知 fallback、PR template、PR review checklist に由来方針が残っていることも確認する。

## 影響

- 外部ソースを読まなくても、由来方針の削除や code-like identifier の混入を CI で止められる。
- この guard は法的な非侵害証明ではない。コピーなし方針、PR レビュー、テスト、ログ由来の再導出方針を補助する機械チェックとして扱う。
- `Mac Mouse Fix` への説明が必要な場合は、方針文書または配布通知へ置く。実装へ置く必要がある場合は、新しい ADR で理由と例外範囲を先に決める。
- 完成判定では、ライセンス / 由来行の機械証跡として採用するが、公開配布物の最終目視や法務判断が必要な場合は別の人間作業として扱う。

## 関連

- [ログ由来チューニング候補の再導出](0007-log-derived-tuning-parameters.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [PR レビューとマージ判断](../pr-review-checklist.md)
- [サードパーティ通知](../../THIRD_PARTY_NOTICES.md)
