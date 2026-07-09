# ADR-0034: HID usage から対象デバイス活動への変換を純粋ロジックに分離する

- 状態: 採択
- 日付: 2026-07-10

## 背景

対象デバイスの入力安全性は、IOHID の生値を `TargetDeviceGate` へどの活動として渡すかに依存する。
従来は `HIDInputMonitor` の IOHID callback 内で usage 分岐していたため、Nape Pro 実機と入力監視権限なしでは、button release、pointer のゼロ値、wheel、runtime 非対応 AC Pan などの境界を直接テストしにくかった。

Issue #4 / #5 の実機証跡は引き続き必要だが、実機前に固定できる変換規則は純粋ロジックとして先に機械判定する。

## 決定

- IOHID の `usagePage` / `usage` / `integerValue` / `time` から `TargetDeviceActivity` への変換は `HIDTargetActivityMapper` に分離する。
- HID Button page は `MouseButton(hidButtonUsage:)` で button usage を `buttonNumber + 1` として扱う。
- Button の非ゼロ値は `buttonDown`、ゼロ値は `buttonUp` として扱い、release を失わない。
- Generic Desktop X / Y は非ゼロ値だけを `pointer` として扱う。
- Generic Desktop Wheel は非ゼロ値だけを `wheel` として扱う。
- Consumer AC Pan など runtime が記録しない usage、未対応 button usage、pointer / wheel のゼロ値は対象活動として採用しない。
- `HIDInputMonitor` は IOHID から値を読み、mapper の結果だけを `SharedTargetDeviceGate` に記録する。

## 影響

- Nape Pro 実機なしでも、HID usage 境界を core test で回帰確認できる。
- `analyze-association` の期待 usage と runtime gate に入る usage の説明を揃えやすくなる。
- 実機ログで usage が異なる場合は、mapper と analyzer の両方を同じ根拠で更新する。
- これは実機識別や associationWindow 妥当化の代替ではない。Nape Pro 操作ログによる最終採否は引き続き必要。

## 関連

- [ADR-0009: 対象デバイス紐づけ秒の機械判定](0009-target-device-association-window-assertion.md)
- [検証手順](../verification.md)
- [完成判定チェックリスト](../completion-checklist.md)
