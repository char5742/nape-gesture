# ADR-0021: 設定 UI 編集項目 catalog の機械証跡化

> 一部置換済み: `gesture.bindings.*`、方向ロック、軸ずれcancelは廃止した。現在の方針は[ADR-0047](0047-fixed-continuous-2d-trackpad-input.md)を正とする。

- 状態: 採択
- 日付: 2026-07-09

## 背景

完成判定では、設定 UI から activation button、感度、加速度、慣性、キャンセル条件、対象デバイス、対象入力の紐づけ秒、主要割り当てを編集できる必要がある。
[ADR-0012](0012-settings-ui-gesture-action-coverage.md) で `GestureAction` 候補の網羅性は固定したが、UI が扱う編集項目全体は AppKit の画面コードに散らばっており、目視確認まで漏れを検出しにくい。

また、`.app` の最終 UI 操作確認は人間作業として残るが、編集項目の存在、設定パス、入力種類、アプリ別設定を含まないことは実機や TCC なしで機械判定できる。

## 決定

- `NapeGestureCore` に `SettingsUIField` と `SettingsUIFieldDescriptor` を置き、設定 UI の編集対象 catalog とする。
- catalog は表示名、section、control kind、設定パス、割り当て popup の `GestureAction.settingsSelectableActions` を持つ。
- `SettingsWindowController` の表示ラベルは catalog の `label` を使う。
- core tests で、catalog が次の編集対象を網羅することを固定する。
  - `gesture.activationButton`
  - `targetDeviceAssociation.associationWindow`
  - `gesture.deadZonePoints`
  - `gesture.directionLockRatio`
  - `gesture.dragSensitivity`
  - `gesture.wheelSensitivity`
  - `gesture.acceleration.*`
  - `gesture.momentum.*`
  - `gesture.cancellation.*`
  - `targetDevices[0].*`
  - `requireMatchingTargetDevice`
  - `gesture.bindings.*`
- core tests で、catalog の表示名と設定パスが重複せず、アプリ別設定の label / path を含まず、JSON round-trip できることを固定する。
- 新しい設定 UI 項目を追加する場合は、先に catalog、core tests、completion checklist を更新する。

## 影響

- 設定 UI の編集対象漏れを `.app` の目視操作前に CI で検出できる。
- Issue #11 / #16 の機械証跡は、`GestureAction` 候補だけでなく、設定 UI の編集対象 catalog まで含めて説明できる。
- 最終的な `.app` UI の表示崩れや保存操作は引き続き人間作業または UI 実行環境での別証跡が必要であり、この ADR だけでは完成扱いにしない。

## 関連

- [設定 UI の GestureAction 網羅性](0012-settings-ui-gesture-action-coverage.md)
- [GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [PR レビューチェックリスト](../pr-review-checklist.md)
