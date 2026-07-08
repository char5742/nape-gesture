# ADR-0018: targetDevice.notFound の matcher 詳細診断

- 状態: 採択
- 日付: 2026-07-09

## 背景

Issue #4 と Issue #16 では、Nape Pro 実機ログ取得前に対象デバイス条件をできるだけ機械で切り分ける必要がある。
`doctor --json --assert-runtime-ready` は `targetDevice.notFound` を返せるが、従来はどの matcher 条件が、どの HID 候補のどの field で外れたかを JSON から追えなかった。
この状態では、人間が `devices --all --json` を見比べて推測する余地が残り、`need:human` の作業が増える。

## 決定

- `DeviceMatcher.evaluate(_:)` を core に追加し、`conditionCount`、`matchedConditions`、`mismatches[]`、`isMatch` を構造化する。
- `doctor --json` は `targetDeviceDiagnostics` を出力する。
- `targetDeviceDiagnostics` は、設定済み matcher、matcher 条件数、診断 status、候補 device、最も近い matcher index、`bestEvaluation` を含める。
- 候補 device は、完全一致、部分一致、または pointing device を優先して出す。
- `targetDevice.notFound` の期待失敗では、`targetDeviceDiagnostics` と `bestEvaluation` の存在も completion evidence で確認する。
- `devices --all --json` は既存の配列契約を維持し、matcher 診断の正本は `doctor --json` に置く。

## 影響

- 実機が未接続、matcher が不正、usage が違う、文字列条件が外れている、といった原因を JSON で切り分けやすくなる。
- `need:human` は Nape Pro の接続や操作に限定し、設定条件の見比べは `doctor --json` の終了コードと構造化診断へ寄せられる。
- 既存の `targetDevice.notFound` code は維持するため、ADR-0011 の runtime ready 契約とは互換である。

## 関連

- [GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [Runtime recovery 境界条件の機械証跡化](0008-runtime-recovery-boundary-evidence.md)
- [doctor runtime ready の機械判定](0011-doctor-runtime-ready-assertion.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
