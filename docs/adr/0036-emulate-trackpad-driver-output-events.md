# ADR-0036: trackpad driver上位eventを安全に再現する

- 状態: 採択
- 日付: 2026-07-12
- 更新日: 2026-07-13

## 背景

[ADR-0049](0049-fixed-button-to-gesture-class-input.md)は、button 3 / 4 / 5を固定GestureClassへ接続する。classはraw finger countではなく、物理trackpad driver認識後の上位event semanticsである。

物理gestureが異なれば、必要なevent family、field、phase、companion lifecycle、単位変換も異なる。これを一つのgeneric eventへ統一すると、再現すべき物理contractを失う。一方、通常SDKに公開されないevent contractを安全に投稿するには、OS build別compatibility adapter、由来追跡、投稿前検査、fail closedが必要である。

## 決定

### 固定classとadapter

| button | GestureClass | adapter contract |
| --- | --- | --- |
| 3 | 2本指scroll / swipe | type 22 scrollとtype 29 gesture envelope / companion |
| 4 | 3本指system swipe | type 30 `DockSwipe`、IOHID motion 1 / 2 |
| 5 | 4本指system pinch | type 30 `DockSwipe`、IOHID motion 4 |

- mappingは設定、方向、source kind、application、OS画面結果によって変更しない。
- `NavigationSwipe`を別button class、独立製品capability、ページ移動専用routingにしない。水平scrollの解釈はapplicationへ任せる。
- adapterがclassごとに異なるevent type、field、phase、companion、axis、progress、position、velocity、単位を生成することを必須とする。
- button 5は`dockSwipePinch` familyを使う固定GestureClassであり、application magnification eventまたはgeneric `fingerCount` fieldへ変換しない。
- class固有encodingは物理gestureの再現であり、application別routingまたはユーザー変更可能なmodeではない。

### source input境界

- accepted move / wheel sampleごとに1つのsource commandを生成する。
- commandはX/Y量、符号、source kind、exact timestamp、capture order、session ID、固定GestureClassを保持する。
- sampleをdrop、duplicate、coalesce、sortしない。方向反転や軸変更で別classまたは別sessionへ切り替えない。
- 1 commandから生成する低レベルevent数はadapter contractに従う。scroll companion batchなどの複数eventは正常である。
- class固有の単位変換と係数はApple公式資料、Apple OSS、自前の純正trackpad / Nape Pro fixtureから再導出し、identityをversion管理する。
- 感度、dead zone、ユーザー加速度、結果別係数で有効sampleを破棄または意味変更しない。

### 投稿境界

- 製品eventはsystem-wide event streamだけへ投稿する。
- 対象PID、frontmost application、AX element、keyboard shortcut、診断eventを配送判断またはfallbackに使わない。
- DriverKit、virtual HID、raw digitizer contactを使わない。
- 通常SDK非公開のfieldとbridgeは最小compatibility adapterへ隔離する。
- event contract、field、定数、状態遷移、係数はApple公式資料、Apple OSS、自前fixtureまで追跡可能にし、第三者成果物由来の値を取り込まない。
- 25F80の正負方向別認識済みtype 30 template fixtureはID `recognized-dockswipe-templates-25F80-v2`、contract ID `recognized-dockswipe-template-v2`、SHA-256 `852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6`を登録値とする。各templateはevent type 30、field 55 = 30、classifier field 110 = 23、phase fields 132 / 134 = 1 / 2 / 4を満たさなければならない。
- 検証済みtemplateからIOHID `DockSwipe` type 23を復元し、timestamp、sender ID、phase flags、mask = 0、motion = 1 / 2 / 4、flavor = 3、progress、position、終端velocity childを更新する。phaseはbegan 1、changed 2、ended 4、cancelled 8とする。
- scroll contract、変換model、DockSwipe templateのfixture ID、SHA-256、schema、contract ID、OS version / build、fixture実体がすべて一致した場合だけ`supported`とする。
- 未知OS build、未登録fixture、hash不一致、contract不一致、adapter不備、権限不足では全ProductOutput familyを無効にし、event tapと入力抑制を開始せずruntime全体をfail closedする。
- 生成marker、投稿前raw配送先field検査、direct post trace、capture provenanceによりfeedback loopと禁止経路混入を拒否する。

### sessionと結果

- session、capture order、timestamp、single terminalは[ADR-0038](0038-trackpad-output-session-and-monotonic-clock.md)と[ADR-0040](0040-capture-order-and-event-timestamp.md)を正とする。
- 縦横scroll、ページ戻る・進む、Spaces、Mission Control、App Expose、DockSwipe motion 4のsystem pinch解釈はsystem-wide受入scenarioとして記録する。
- 低レベルcontract、OS / App結果、純正trackpadとの体感差を別々に判定する。
- 画面結果を成立させるため、別family、AX、PID、shortcutへfallbackしない。

## 検証

- button 3 / 4 / 5が固定classと`scroll` / `dockSwipe` / `dockSwipePinch`へ一意に接続される。
- source sample件数、X/Y、符号、capture order、timestamp、session IDがcommand境界までlosslessに保持される。
- class別のevent type、field、phase、batch、単位変換、terminalを登録fixtureと比較する。
- partial batch、作成失敗、投稿失敗、terminal retryで順序を失わずsingle terminalへ収束する。
- 未知build、fixture改変、明示path不正、権限不足で抑制前にfail closedする。
- source boundaryとdirect post traceでsystem-wide以外の製品配送がないことを検査する。

## 影響

- GUIと設定は固定class名だけを読み取り専用で表示し、event family selectorを公開しない。
- doctorは製品runtimeに必要な`scroll`、`dockSwipe`、`dockSwipePinch`の3 familyを共通readiness contractで検査する。
- 既存ProductOutput adapter、fixture、state machineは、固定class coordinatorから到達する製品実装として再利用する。
- compatibility contractを安全に構成できない環境では、通常mouse入力を壊さず停止する。

## 関連

- [ADR-0049: buttonを固定GestureClassへ接続する](0049-fixed-button-to-gesture-class-input.md)
- [ADR-0034: DriverKit virtual trackpadを製品出力に使わない](0034-reject-driverkit-virtual-trackpad.md)
- [ADR-0037: 製品gesture出力と診断event出力を分離する](0037-separate-product-and-diagnostic-event-output.md)
- [ADR-0038: 固定GestureClass sessionとmonotonic clockを共通化する](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0043: 25F80の固定GestureClass ProductOutput contract](0043-trackpad-scroll-product-output.md)
- [ゴール要件](../requirements.md)
