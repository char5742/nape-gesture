# ADR-0046: 残るtrackpad familyを25F80試用出力として有効化する

> 置換済み: 4 familyを製品capabilityとする判断と結果名ベースの試用範囲は[ADR-0048](0048-separate-input-mode-event-family-os-result-and-evidence.md)で置換した。現行の製品runtime capabilityは`scroll`、`DockSwipe`、`magnification`の3経路であり、`NavigationSwipe`は2本指系列で観測された低レベル候補として扱う。本ADRは2026-07-12時点のcandidate builder試用記録として保持する。

- 状態: 採択
- 日付: 2026-07-12

## 背景

25F80の`scroll` familyは確定済みcontractと自前計測modelで製品出力まで実装した一方、`DockSwipe`、`NavigationSwipe`、`magnification`は候補raw fieldを観測済みでも、方向ラベルを分離した物理収録が未完了だった。そのため既定bindingが`DockSwipe`を要求すると起動前に停止し、実機で操作感を試せなかった。

## 決定

- 検証済み25F80 identityでだけ、4 familyをproduct capabilityとして公開する。
- `DockSwipe`はtype 29 / classifier 32、`NavigationSwipe`はtype 30 / classifier 23、`magnification`はtype 29 / classifier 8としてsystem-wideへ投稿する。
- 全eventへsession phase、monotonic timestamp、生成markerを付け、投稿前raw field 39 / 40が0であることを検証する。
- 非scroll familyも既存`TrackpadOutputSessionMachine`で`began -> changed* -> ended/cancelled`を検証し、terminal metadataを必須にする。
- gesture量は入力deltaとvelocityから正規化し、25F80で試用可能な初期値とする。方向・係数はNape Pro実機試用で調整し、純正同等contract確定値とは扱わない。
- 未知OS build、contract/model不一致では従来どおりfail closedにする。

## 影響

- 既定bindingを含む設定で`missingFamilies`にならず、GUIアプリからSpaces、Mission Control、page navigation、zoomを試用できる。
- `doctor`は4 familyをsupportedとして表示する。
- 自動テストはevent type、classifier、phase、terminal、生成marker、system-wide traceを固定する。
- 物理結果と方向・体感の最終合格は未完了であり、試用結果をもとに調整する。

## 関連

- [trackpad driver上位出力eventを再現する](0036-emulate-trackpad-driver-output-events.md)
- [25F80 trackpad scroll製品出力](0043-trackpad-scroll-product-output.md)
- [検証手順](../verification.md)
