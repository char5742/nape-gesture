# ADR-0043: 25F80の固定GestureClass ProductOutput contractを構成する

- 状態: 採択
- 日付: 2026-07-12
- 更新日: 2026-07-13

## 背景

macOS 26.5.1（build 25F80）について、純正trackpad captureからtype 22 scroll + type 29 companionと、認識済みtype 30 / IOHID `DockSwipe`の上位event contractを再導出し、既存ProductOutput adapterとして実装している。4本指system pinchもapplication magnificationではなく、`DockSwipe` motion 4として構成する。

固定buttonモデルは、これらを一つのfinger-count eventへ統合しない。buttonからGestureClassを一意に決め、class固有adapterへ接続する。既存adapter、fixture、batch投稿、terminal retry、provenanceを維持し、ユーザー変更可能なmodeとapplication別routingだけを製品経路から除く。

## 決定

### contract identityとfail closed

- 25F80 contractはfixture ID、SHA-256、schema、contract ID、OS version / build、fixture実体、単位変換model identityを持つversioned contractとして登録する。正負方向別の認識済みDockSwipe templateはfixture ID `recognized-dockswipe-templates-25F80-v2`、contract ID `recognized-dockswipe-template-v2`、SHA-256 `852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6`とする。
- runtimeに必要なfamilyは`scroll`、`dockSwipe`、`dockSwipePinch`の3つとする。
- `supported`は、scroll contract、変換model、DockSwipe templateの登録identityと実際に読み込んだbytesが完全一致し、3 classの生成とterminalが成立する場合だけ返す。
- 明示pathがある場合はそのpathだけを検証し、不正pathからbundleまたはrepository fixtureへ黙ってfallbackしない。
- 未知OS build、未登録fixture、hash / schema / contract不一致、単位変換未確定では全ProductOutput familyを無効にし、event tapと入力抑制を開始せずruntime全体をfail closedする。

### class別ProductOutput

| GestureClass | family | encoding |
| --- | --- | --- |
| 2本指scroll / swipe | `scroll` | type 22 scrollとtype 29 envelope / companion。scroll phase field 99とcompanion phase field 132、line / fixed / point / gesture motion単位 |
| 3本指system swipe | `dockSwipe` | type 30 / classifier 23、phase fields 132 / 134、IOHID motion 1 / 2。progress / XY positionはsource delta / 300、終端XY velocityはsource delta / 経過秒 / 300 |
| 4本指system pinch | `dockSwipePinch` | type 30 / classifier 23、phase fields 132 / 134、IOHID motion 4。progressはY優先のsigned source delta / 300、終端Z velocityは同じ符号規則のsource velocity / 300 |

- fixed coordinatorはGestureClassからfamilyを一意に選ぶ。
- class固有のaxis選択、progress / position / velocity変換は、物理contractを再現するadapter encodingとして扱う。
- 認識済みtemplateからIOHID `DockSwipe` type 23を復元し、timestamp、sender ID、phase flags、mask = 0、motion、flavor = 3、progress、position、終端velocity childを更新してからCGEventとIOHID値を再検証する。
- class別係数をユーザー感度またはapplication別調整値として公開しない。
- accepted source sampleごとに1 commandを生成し、X/Y、符号、source kind、timestamp、capture order、session IDを保持する。
- 1 commandから生成するevent数はclassにより異なってよい。scroll input batchは全eventを構築・検証してから投稿する。
- batch部分投稿後は未投稿offsetと予約済みpost indexを保持し、同じsource eventまたは同じterminalだけを再試行する。
- `NavigationSwipe`はcapture / analyzerの観測分類に限定し、独立runtime familyまたはページ移動専用routingにしない。

### system-wide投稿とprovenance

- eventはsystem-wideへだけ投稿する。対象PID、AX element、application別配送、keyboard shortcutを選ばない。
- adapterは投稿前のraw配送先fieldが未指定であることを検査する。
- WindowServerが投稿後captureへ実配送先を付与しても、それだけを対象PID投稿の証拠または失敗理由にしない。
- direct post traceへsession、GestureClass、family、capture order、source timestamp、generated timestamp、event type、system-wide delivery、run / binary identityを記録する。
- capture、manifest、traceのSHA-256とidentityを照合し、生成markerとsource boundary guardでfeedback loopと診断出力混入を拒否する。

### 低レベルcontractとOS / App結果

- 低レベル判定ではsource-to-command対応、class、family、field、phase、timestamp、capture order、batch、terminalを純正trackpad fixtureと比較する。
- 縦横scroll、nested target、ページ戻る・進む、Spaces、Mission Control、App Expose、DockSwipe motion 4のsystem pinch解釈は別のsystem-wide受入scenarioとする。
- OS / App結果のために結果別係数、AX、PID、shortcut、別family fallbackを追加しない。
- ProductOutputの機械smoke成功は試用可能性を示すが、Nape Pro物理受入を代用しない。

## 検証

- button 3 / 4 / 5から固定classと`scroll` / `dockSwipe` / `dockSwipePinch`へのmappingを機械判定する。
- source sample 1対1 command化、X/Y、符号、timestamp、capture order、drop、duplicate、reorderを検査する。
- class別event type、field、phase、unit conversion、batch、single terminalをfixtureと比較する。
- scroll contract、model、DockSwipe template、OS identityを個別に改変し、runtime全体が抑制前にfail closedすることを確認する。
- batch作成失敗、部分投稿、terminal再試行、direct post trace、capture provenance、raw配送先fieldを検査する。
- 3 familyを同じProductOutputからsystem-wideへ投稿し、type 30のmotion 1 / 2 / 4とIOHID値を検査するsmokeを実行する。

## 影響

- PR #143から#147で成立していたProductOutput adapterを製品実装として維持する。
- runtime readinessは3 familyすべてを要求する。1 familyでもidentityまたは構築条件を満たさなければruntime全体を開始しない。
- GUIはfamily selectorを持たず、固定GestureClassを読み取り専用表示する。
- 25F80 contractが不完全な環境では通常mouse入力を保持して停止する。
- release buildの`/Applications/Nape Gesture.app`はインストール済みでdoctor runtime readyである。system-testではDockが3本指垂直とmotion 4の正負両方向を受理済みだが、Nape Pro実機button 4 / 5の入力、terminal、通常mouse復帰は別途物理受入する。

## 関連

- [ADR-0049: buttonを固定GestureClassへ接続する](0049-fixed-button-to-gesture-class-input.md)
- [ADR-0036: trackpad driver上位eventを安全に再現する](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0038: 固定GestureClass sessionとmonotonic clockを共通化する](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0039: trackpad eventログを厳格解析しcapture manifestへ固定する](0039-strict-trackpad-event-analysis-and-capture-manifest.md)
- [ADR-0040: capture順とevent timestampを独立して保持する](0040-capture-order-and-event-timestamp.md)
- [ゴール要件](../requirements.md)
