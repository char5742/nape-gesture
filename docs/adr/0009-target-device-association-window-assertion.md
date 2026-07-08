# ADR-0009: 対象デバイス紐づけ秒の機械判定

- 状態: 採択
- 日付: 2026-07-09

## 背景

Issue #5 の対象デバイス紐づけでは、Nape Pro の HID 入力と event tap 入力の時刻差を実測し、`targetDeviceAssociation.associationWindow` の妥当性を説明する必要がある。
表示だけの解析では、人間が `outsideWindowCount` や `missingHIDCandidateEventCount` を見落とす余地が残る。

## 決定

- `analyze-association` は `--assert-valid-window` を持つ。
- `--assert-valid-window` は、解析対象 event tap 入力が 1 件以上あり、HID 候補なしが 0 件で、associationWindow 外が 0 件の場合だけ成功する。
- 空ログ、HID 候補なし、associationWindow 外の入力を、完了証跡として扱わない。
- 実機ログ取得後の採否は、`analyze-association --json --assert-valid-window` の終了コードと `matches` の時刻差で行う。
- completion evidence では、成功 fixture と期待失敗 fixture の両方を残し、判定が甘くならないことを確認する。

## 影響

- `need:human` は Nape Pro 実機操作や TCC などの外部作業に限定し、ログ取得後の採否は機械判定へ寄せられる。
- associationWindow の調整は、表示値の目視ではなく、非ゼロ終了した `matches` を根拠に行う。
- 空ログや部分一致ログを「実測済み」として扱う事故を防ぐ。

## 関連

- [GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [Issue による orchestration と証跡付き close 方針](0005-issue-orchestration-and-evidence-close.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
