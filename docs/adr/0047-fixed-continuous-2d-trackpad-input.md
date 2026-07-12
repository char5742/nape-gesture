# ADR-0047: 方向別bindingを廃止し固定trackpad gestureへ接続する

- 状態: 採択
- 日付: 2026-07-12

## 背景

従来の操作体系は、ジェスチャーボタン押下中の上下左右ドラッグを個別actionへ割り当て、確定方向に応じて出力familyを選択していた。この方式では、同じドラッグ中の方向転換が別actionへの切り替え候補となり、下方向だけscrollになるなど、トラックパッドの連続した2D入力と異なる挙動を生む。方向ロックと軸ずれキャンセルも、押下中のX / Y変化を連続的にmacOSへ渡すことを妨げる。

製品の目的はマウス移動を方向別actionへ割り当てることではない。特定ボタン押下中の連続移動を3本指`DockSwipe`系列としてsystem-wideに渡し、その軸、符号、進捗に応じた挙動をmacOSの標準gesture処理へ委ねることである。

## 決定

- 製品の操作体系は、ジェスチャーボタン未押下時の通常mouse passthroughと、押下中の固定trackpad gesture入力の2状態とする。
- ボタン押下中のmouse moveは開始時の優勢軸を3本指`DockSwipe`の軸として確定し、押下開始から解放または明示cancelまで単一sessionへ変換する。途中の符号反転は同じ軸・sessionで連続投稿する。
- session途中で方向が変わっても別actionへ切り替えず、同じsession IDとlifecycleを維持する。
- 上下左右の方向別binding、主要ジェスチャーの個別割り当て、familyを方向で選ぶ設定を製品設定と設定UIに持たない。
- 方向ロックと軸ずれ比によるcancelを製品入力経路に持たない。最大継続時間、無入力時間、kill switchなど方向に依存しない安全停止は維持する。
- ボタン押下中のwheelは2次元`scroll`として投稿する。mouse moveの`DockSwipe`とwheelの`scroll`の方向・進捗に応じた挙動はmacOSへ委ねる。
- `NavigationSwipe`と`magnification`はadapterの生成能力として維持するが、存在しない方向別bindingへ接続しない。固定入力からの明示的な起動操作が決まるまでは製品runtimeで到達可能とは扱わない。
- ボタン解放時はactive sessionを`ended`または`cancelled`で必ず閉じ、必要な場合だけmomentumへ移行して通常mouse状態へ戻る。
- 既存の方向別bindingを含む設定は、安全な移行処理で廃止項目を取り除く。旧bindingを暗黙の出力選択へ流用しない。

## 影響

- 設定UIと設定schemaから方向別action選択がなくなり、調整対象はactivation button、感度、加速度、慣性、方向非依存のキャンセル条件、対象device条件などに限定される。
- 方向反転や斜め移動を含む入力は、別actionの再認識ではなく開始時に固定した同一軸・session内の連続サンプルとして検証する。
- `GestureAction`全ケースを設定UIに露出することを決めた[ADR-0012](0012-settings-ui-gesture-action-coverage.md)を置き換える。
- trackpad event contract、system-wide投稿、未知contractでのfail closedは[ADR-0036](0036-emulate-trackpad-driver-output-events.md)以降の決定を維持する。

## 関連

- [Issue #144](https://github.com/char5742/nape-gesture/issues/144)
- [ゴール要件](../requirements.md)
- [trackpad driver上位出力eventを再現する](0036-emulate-trackpad-driver-output-events.md)
- [製品gesture出力と診断event出力を分離する](0037-separate-product-and-diagnostic-event-output.md)
