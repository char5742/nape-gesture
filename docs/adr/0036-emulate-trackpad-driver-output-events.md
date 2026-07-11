# ADR-0036: trackpad driver上位出力eventを再現する

- 状態: 採択（scroll companionのtimestamp同値要件はADR-0040で置換）
- 日付: 2026-07-11

## 背景

Nape Gestureの完成形は、特定ボタン押下中のmouse操作を、scroll / page navigation、Spaces / Mission Control、magnificationに対応するtrackpad driver上位出力相当のevent列としてmacOSへ認識させることである。AX scrollbar、対象PIDへのevent配送、keyboard shortcutによるgesture代替は、前面applicationごとの分岐と不完全な挙動を生むため採用しない。

外部 reference implementation の構成は設計方向の確認にだけ用い、通常配布物がinput event tapとhelper内の出力moduleで構成される点を参考にした。二本指相当の経路はcontinuous scroll eventと対応するgesture eventをphase / momentum付きで送り、Spaces / Mission Control相当の経路は連続progressとphaseを持つDockSwipe eventを送る。page navigationとmagnificationもtrackpad driverの上位出力に相当するgesture eventとして扱う。

外部 reference implementation は製品実装の正本にせず、第三者プロジェクトのコード、field番号、定数、係数、調整値、状態遷移をコピーしない。実装由来を混ぜない境界を維持し、Apple公式資料、Apple OSS、このリポジトリの純正trackpad / Nape Proログからevent contractを再導出する。

## 決定

- 入力側は既存のIOHID device識別、CGEvent tap、対象device association、gesture recognizerを基礎にする。
- 製品出力は次のtrackpad driver上位出力eventへ限定する。
  - trackpad scroll: continuous scroll eventと対応するscroll gesture eventの系列。timestamp同値という当初仮定は純正実測に基づき[ADR-0040](0040-capture-order-and-event-timestamp.md)で置き換えた
  - Spaces / Mission Control: progress、motion、phase、終了速度を持つDockSwipe event系列
  - page navigation: NavigationSwipe event系列
  - zoom: magnification / zoom event系列
- scroll phaseとmomentum phaseを混同せず、begin / change / end / cancelとmomentum begin / continue / endを欠落なく送る。
- 出力はsystem-wide event streamだけへ送り、対象PID、frontmost application、AX elementを配送判断に使わない。
- applicationごとの出力分岐、keyboard shortcut fallback、AX fallbackを持たない。
- DriverKit virtual trackpad、digitizer contact、System Extensionを前提にしない。
- event type、subtype、field、順序、timestamp、phase、momentumの正本は、AppleのIOHIDFamily OSSにあるevent taxonomyと、このリポジトリのlisten-only loggerで取得した純正trackpad logから再導出する。
- 通常SDKに公開されていないevent fieldやbridgeが必要な場合は、最小のcompatibility adapterへ隔離し、OS versionごとのfixtureと実機証跡を持つ。未知versionやcontract不一致では誤ったeventを送らずfail closedにする。
- 第三者プロジェクト由来の名前、field番号、定数、係数、調整値、状態遷移、header、実装断片はproduction code、fixture、testへ持ち込まない。
- [ADR-0037](0037-separate-product-and-diagnostic-event-output.md)に従い、製品adapterと旧単純scroll / shortcut /対象PID配送を含む診断出力をmodule境界で分離する。

## 影響

- 現行`EventPoster`の単純pixel scrollとMission Control / page / zoom向けkeyboard shortcutは完成形ではなく、上記adapterへ置換する。
- 既存のCGEvent runtime証跡は入力認識、元入力抑制、GUI、診断toolの前段証跡として残るが、trackpad driver出力の完成証跡にはしない。
- 純正trackpad event contractの取得は物理操作を必要とするが、logger、analyzer、fixture比較、output state machineは先に自動化する。
- macOS更新でprivate contractが変わる可能性をrelease riskとして明示し、version別compatibility testを必須にする。
- [ADR-0034](0034-reject-driverkit-virtual-trackpad.md)に従い、DriverKit entitlement、`.dext`、System Extension lifecycleは完成要件に含めない。

## 関連

- [Apple IOHIDFamily event taxonomy](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/tools/hidartraceutil)
- [repo-local由来ガード](0023-repo-local-provenance-guard.md)
- [ゴール要件](../requirements.md)
- [検証手順](../verification.md)
- [製品gesture出力と診断event出力を分離する](0037-separate-product-and-diagnostic-event-output.md)
