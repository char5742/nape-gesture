# Sources/NapeGestureCore/AGENTS.md

この階層は `NapeGestureCore` の純粋ロジックを担当します。macOS の実イベント投稿や HID 接続状態から独立して、決定的にテストできる状態を保ってください。

## 境界

- `Foundation` 以外の macOS 実行環境依存を追加しない。
- AppKit、CoreGraphics、IOKit、TCC、実ファイル I/O、プロセス起動、時刻取得を直接持ち込まない。
- UI や doctor で使う文言・表示状態は、可能な限り presenter / value object としてここで固定し、実表示は `Sources/nape-gesture/` に置く。

## 不変条件

- ジェスチャーボタン未押下時の通常入力通過を壊さない。
- ボタン解放、キャンセル、キルスイッチ後に状態が復帰することをテストで固定する。
- Settings validation は保存前または起動前に不正値を止める。
- `GestureAction` や `SettingsUIField` を増減したら、settings selectable actions、JSON round-trip、アプリ別設定なしのテストも更新する。
- benchmark に影響する処理では、意図しない O(n) 増加や不要な allocation を避ける。
