# ADR-0049: buttonを固定GestureClassへ接続する

- 状態: 採択
- 日付: 2026-07-12
- 更新日: 2026-07-14

## 背景

従来の製品runtimeには、buttonごとにユーザー変更可能なmodeを持ち、modeから結果別event familyを選ぶ設計があった。固定mappingへ移行する際、「2 / 3 / 4本指」というユーザー向け概念をraw finger count transportとして字義どおり扱い、button間で出力上変更できる情報はfinger countだけ、一つのgeneric trackpad eventを生成する、という抽象へ変更した。

この抽象は誤りである。物理trackpadはgesture認識後、gesture classに応じて異なる上位event contractを生成する。2本指scroll、3本指system swipe、4本指system pinchではevent type、field、phase、単位が異なる。4本指classはapplication magnification eventではなく認識済みDockSwipe motion 4である。class固有adapterを持つことは結果別routingではなく、異なる物理gestureの再現に必要である。

一方、固定button mapping、source sampleのexact timestampとcapture order、session identity、single terminal、fail closed、system-wide投稿、第三者成果物非流用は維持する。

## 決定

### 1. buttonは固定GestureClassを選ぶ

| button | 固定GestureClass | ProductOutput family |
| --- | --- | --- |
| 3 | 2本指スクロール / スワイプ相当 | `scroll` |
| 4 | 3本指システムスワイプ相当 | `dockSwipe`、type 30 DockSwipe motion 1 / 2 |
| 5 | 4本指system pinch相当 | `dockSwipePinch`、type 30 DockSwipe motion 4 |

button未押下または対象外buttonでは通常mouse入力を通す。このmappingは設定、方向、source kind、application、OS画面結果で変更しない。

「2 / 3 / 4本指」はraw digitizer contact countでもgeneric `fingerCount` fieldでもない。固定GestureClassのユーザー向け説明であり、ProductOutputへ一つのfinger-count fieldだけを渡す契約にしない。

### 2. source sampleとoutput encodingを分ける

accepted move / wheel sampleごとに1つの`FixedGestureInputCommand`を生成する。commandはsource kind、X/Y量、符号、exact timestamp、capture order、session ID、source button、GestureClassを保持する。

source commandはdrop、duplicate、coalesce、reorderしない。方向反転、軸変更、move / wheel混在を別actionまたは別sessionへ変換しない。

ProductOutput adapterはclass固有のevent contractを生成する。

- 2本指classはtype 22 scrollとtype 29 gesture envelope / companion lifecycleを生成し、scroll phase field 99、companion phase field 132、line / fixed / point / gesture motion単位を使う。
- 3本指classはtype 30 / classifier 23、phase fields 132 / 134、IOHID DockSwipe motion 1 / 2へ変換する。progress / XY positionは`(source delta / 600) * systemGestureSensitivity`、終端XY velocityは`(source velocity / 600) * systemGestureSensitivity`とする。
- 4本指classは同じtype 30 / classifier 23とphase 1 / 2 / 4 / 8を使うが、IOHID DockSwipe motion 4へ変換する。progressはY優先の`(signed source delta / 600) * systemGestureSensitivity`、終端Z velocityは同じ符号規則の`(source velocity / 600) * systemGestureSensitivity`とする。

このため、同じsource系列でもgenerated event type、event count、field、phase、unit conversionはclassごとに異なり得る。3本指と4本指はevent family、motion、axis、符号規則が異なる一方、100%時の`/ 600`基準と共通の`systemGestureSensitivity`を共有する。このencodingを各classの純正trackpad fixtureへ照合する。2本指classは登録済みscroll contractをそのまま使い、共通感度を適用しない。

### 3. 固定classとユーザーmodeを区別する

内部でGestureClassからadapterを選ぶ処理は必要である。一方、次の製品surfaceは設けない。

- buttonごとのmode selectorまたは無効化
- ユーザー変更可能なbutton割り当て
- button別または方向別の感度、dead zone、加速度、結果別係数
- 方向別binding
- applicationごとの有効・無効、感度、割り当て

GUIは固定mappingを読み取り専用で表示し、唯一のgesture調整値としてbutton 4 / 5共通の「システムジェスチャー感度」を提供する。canonical設定`gesture.systemGestureSensitivity`は0.25から2.0、既定値1.0とする。`dragSensitivity`、`wheelSensitivity`などの旧調整値は新しい共通感度へ移行せずcanonical設定から原子的に除去し、新しいcanonical値がない旧設定には1.0を補う。migration失敗時は原本を保持してruntimeを開始しない。

### 4. system-wide ProductOutputを使う

- fixed coordinatorはbutton由来GestureClassから既存ProductOutput familyを一意に選ぶ。
- eventはsystem-wideへ投稿し、macOSまたは前面applicationの標準gesture処理へ渡す。
- 水平scrollからページ移動が起きる場合はapplicationの通常解釈に任せる。
- Spaces、Mission Control、App Expose、DockSwipe motion 4のsystem pinch解釈はOS / App受入結果として別に記録する。
- `NavigationSwipe`を独立class、独立button、ページ移動専用routingにしない。
- AX、対象PID、keyboard shortcut、application別分岐をfallbackにしない。
- DriverKit、virtual HID、raw digitizer contactを使わない。

### 5. session safetyを共通化する

- button pressからreleaseまたはcancelまでsource buttonとGestureClassを固定する。
- session ID、capture order、source timestamp、terminal stateを共通session machineで検証する。
- class固有adapterは低レベルphaseとbatchを管理し、共通machineはsource identityとsingle terminalを保証する。
- release、cancel、kill switch、runtime stop、sleep、disconnect、TCC喪失、作成 / 投稿失敗で一度だけterminalへ収束する。
- partial batch後は未投稿offsetを保持し、同じterminalを再試行する。
- terminal後は通常mouse状態へ戻る。
- 製品入力tapは、Nape ProのIOHID入力とCGEventの関連付け順序を維持できる`.cgSessionEventTap`のhead insertを使う。
- 対象button downのevent locationをsession固有の絶対cursor anchorとして1回だけ保存し、同じanchorへの`CGWarpMouseCursorPosition`が成功してからProductOutputを開始する。
- moveのX/Y delta、timestamp、capture orderをsource commandへ保存した直後、同じevent tap callback内でanchorへwarpし、その成功後にGestureClass出力を投稿して元moveを抑制する。wheelではwarpしない。
- button解放、cancel、timeout、tap中断、kill switch、runtime停止、出力失敗ではanchor stateを必ず破棄する。anchor取得またはwarpに失敗した場合はactive ProductOutput sessionをcancelへ収束させ、別方式へfallbackせずruntimeをfail closedにする。
- cursor固定のためにapplicationをforegroundへ移動せず、focusを奪わない。逆delta、AX、対象PID、keyboard shortcut、DriverKitを使わない。

### 6. 抑制前にreadinessを確定する

- 対象device、TCC、scroll contract、変換model、正負方向別の認識済みDockSwipe template fixtureを検証する。25F80で収録したtemplateはID `recognized-dockswipe-templates-25F80-v2`、contract ID `recognized-dockswipe-template-v2`、SHA-256 `852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6`を登録値とする。実行中OS buildは診断へ記録するがreadiness条件にしない。
- 3 classを安全に生成・終了できる場合だけevent tapと元入力抑制を開始する。
- いずれかのfixture、model、adapterが欠落、未知、改変済み、または不一致なら全ProductOutput familyを無効にし、通常mouse入力を保持してruntime全体をfail closedする。診断出力や別配送へfallbackしない。

## 検証と完成判定

- buttonからGestureClass、GestureClassからProductOutput familyへの固定mappingを自動検査する。
- source sample 1対1 command化、exact timestamp、capture order、session ID、single terminalを検査する。
- 3 classのevent type、field、phase、batch、単位変換とIOHID motion 1 / 2 / 4をregistered fixtureへ照合する。
- GUIがmappingをread-only表示し、共通感度の25%から200%・既定100%・button 3非適用を満たし、canonical設定に旧modeや旧感度が残らないことを検査する。
- system-wide posting、禁止経路非到達、unknown build / fixture mismatchのfail closedを検査する。
- Nape Gesture以外をforegroundにした署名済みRelease `.app`で、button 3 / 4 / 5の実cursor座標、高頻度move時の逸脱継続時間、wheel非移動、全terminal後の通常mouse復帰を検査する。
- Nape Proと純正trackpadでsource、generated event、OS / App結果、terminal、passthroughを物理受入する。

release buildの`/Applications/Nape Gesture.app`はインストール済みで、現在の署名identityに対するTCC付与後のGUI runtimeが稼働している。Nape Pro実機では3 class合計23 session、generated event 5473件、作成失敗0件、欠落投稿0件、全sessionのsingle terminalを確認し、DockはSpace切替、Mission Control、motion 4のsystem control遷移を受理した。純正trackpadとの最終比較、異常終了後の復旧、App Exposéの設定依存結果、公開配布署名が完了するまで製品完成とはしない。

## 影響

- exact timestamp、capture order、source command、session ID、single terminalのCore成果を維持する。
- ProductOutput adapter、固定class coordinator、認識済みDockSwipe compatibility adapterを同じruntime readiness境界へ統合する。
- generic finger-count-onlyのrequirements、guard、完成条件を本ADRのGestureClassモデルへ訂正する。
- `TrackpadGestureMode`など旧型がmigrationまたは非製品診断の読込に残っても、daemon、executor、GUI、canonical設定から到達させない。
- requirements、README、completion checklist、performance baseline、既存guardを同じ実装差分で同期する。

## 廃止する設計

- button間で出力上変更できる意味情報をfinger countだけに限定する設計
- 一つのgeneric finger-count eventをProductOutput contractにする設計
- class固有event familyを結果routingとして一律禁止する設計
- raw digitizer、virtual HID、DriverKitを必要条件とする設計
- ユーザー変更可能なmode、割り当て、button別・方向別・application別の感度設定
- AX、対象PID、keyboard shortcutによる製品fallback

## 関連

- [ゴール要件](../requirements.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [ADR-0034](0034-reject-driverkit-virtual-trackpad.md)
- [ADR-0036](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0038](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0043](0043-trackpad-scroll-product-output.md)
