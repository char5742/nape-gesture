# ADR-0049: buttonごとにGestureClassを割り当てる

- 状態: 採択
- 日付: 2026-07-12
- 更新日: 2026-07-14

## 背景

製品runtimeには以前、buttonごとに結果別modeを選ぶ設定があった。その後、button 3 / 4 / 5をそれぞれ2本指scroll / swipe、3本指system swipe、4本指system pinchへ固定するモデルへ移行した。この移行では、GestureClassごとに異なる上位event contractを使い、結果別action、application別routing、方向別bindingを製品surfaceから除去した。

3つのGestureClassはraw finger count transportではない。2本指scroll、3本指system swipe、4本指system pinchではevent type、field、phase、companion、単位が異なり、4本指classはapplication magnification eventではなく認識済みDockSwipe motion 4を使う。このclass固有ProductOutputは維持する。

一方、物理buttonとGestureClassの対応まで固定する必要はない。ユーザーはbutton 3 / 4 / 5それぞれについて3つの入力classから選択したい。同じclassを複数buttonへ割り当てる場合も、class固有contract、安全なsession lifecycle、通常mouse passthroughを損なわず扱える。

## 決定

### 1. buttonごとにGestureClassを選択する

button 3 / 4 / 5のそれぞれに、次の3 GestureClassから1つをGUIで割り当てる。

| GestureClass | ProductOutput family |
| --- | --- |
| 2本指スクロール / スワイプ相当 | `scroll` |
| 3本指システムスワイプ相当 | `dockSwipe`、type 30 DockSwipe motion 1 / 2 |
| 4本指システムピンチ相当 | `dockSwipePinch`、type 30 DockSwipe motion 4 |

既定割り当てはbutton 3が2本指、button 4が3本指、button 5が4本指とする。これは初期値であり、固定対応ではない。同じGestureClassを複数buttonへ割り当ててよい。各buttonには常に1 classを割り当て、無効または未割り当てを表す値は設けない。

button 3 / 4 / 5のいずれも未押下の場合と、対象外buttonだけが押されている場合は通常mouse入力を通す。割り当てはapplication、移動方向、source kind、OS画面結果によって自動変更しない。

「2 / 3 / 4本指」はraw digitizer contact countでもgeneric `fingerCount` fieldでもない。ユーザーが選ぶ上位GestureClassであり、ProductOutputへ一つのfinger-count fieldだけを渡す契約にしない。

### 2. source sampleとoutput encodingを分ける

accepted move / wheel sampleごとに1つの`FixedGestureInputCommand`を生成する。commandはsource kind、X/Y量、符号、exact timestamp、capture order、session ID、source button、session開始時に選択したGestureClassを保持する。

source commandはdrop、duplicate、coalesce、reorderしない。方向反転、軸変更、move / wheel混在を別actionまたは別sessionへ変換しない。

ProductOutput adapterはclass固有のevent contractを生成する。

- 2本指classはtype 22 scrollとtype 29 gesture envelope / companion lifecycleを生成し、scroll phase field 99、companion phase field 132、line / fixed / point / gesture motion単位を使う。
- 3本指classはtype 30 / classifier 23、phase fields 132 / 134、IOHID DockSwipe motion 1 / 2へ変換する。progress / XY positionは`(source delta / 600) * systemGestureSensitivity`、終端XY velocityは`(source velocity / 600) * systemGestureSensitivity`とする。
- 4本指classは同じtype 30 / classifier 23とphase 1 / 2 / 4 / 8を使うが、IOHID DockSwipe motion 4へ変換する。progressはY優先の`(signed source delta / 600) * systemGestureSensitivity`、終端Z velocityは同じ符号規則の`(source velocity / 600) * systemGestureSensitivity`とする。

同じsource系列でもgenerated event type、event count、field、phase、unit conversionはclassごとに異なり得る。button割り当てを変更しても、選択したclassからProductOutputへのcontractは変更しない。

### 3. 割り当てと感度をcanonical設定に保存する

canonical設定は`gesture.buttonAssignments.button3` / `button4` / `button5`にGestureClassを保存する。GUIは各buttonに3 classだけを提示し、重複選択を許可する。無効、未割り当て、結果別action、方向別binding、application別設定を選択肢に含めない。

唯一のgesture調整値として共通の「システムジェスチャー感度」を提供する。canonical設定`gesture.systemGestureSensitivity`は0.25から2.0、既定値1.0とする。感度は物理button番号ではなくsessionに保存したGestureClassで判定し、3本指・4本指classへ適用して2本指classには適用しない。button別または方向別の感度、dead zone、加速度、結果別係数は設けない。

割り当てがない固定モデルのcanonical設定には既定割り当てを補う。有効なcanonical割り当ては重複を含めて保持する。旧`button3Mode` / `button4Mode` / `button5Mode`、旧action / binding、`dragSensitivity`、`wheelSensitivity`などは現行割り当てまたは共通感度へ推測変換せず、canonical設定から原子的に除去する。migration失敗時は原本を保持してruntimeを開始しない。

### 4. system-wide ProductOutputを維持する

- coordinatorはsessionに保存されたGestureClassから既存ProductOutput familyを一意に選ぶ。
- eventはsystem-wideへ投稿し、macOSまたは前面applicationの標準gesture処理へ渡す。
- 水平scrollからページ移動が起きる場合はapplicationの通常解釈に任せる。
- Spaces、Mission Control、App Expose、DockSwipe motion 4のsystem pinch解釈はOS / App受入結果として別に記録する。
- `NavigationSwipe`を独立class、ページ移動専用routing、割り当て候補にしない。
- AX、対象PID、keyboard shortcut、application別分岐をfallbackにしない。
- DriverKit、virtual HID、raw digitizer contactを使わない。

### 5. session safetyを共通化する

- button press時に保存済み割り当てを解決し、releaseまたはcancelまでsource buttonとGestureClassを固定する。
- 設定変更は新規sessionから反映し、active sessionのclassを途中で変更しない。
- session中に別buttonが追加されてもclass、session ID、adapterを切り替えない。
- session ID、capture order、source timestamp、terminal stateを共通session machineで検証する。
- class固有adapterは低レベルphaseとbatchを管理し、共通machineはsource identityとsingle terminalを保証する。
- release、cancel、kill switch、runtime stop、sleep、disconnect、TCC喪失、作成 / 投稿失敗で一度だけterminalへ収束する。
- partial batch後は未投稿offsetを保持し、同じterminalを再試行する。
- terminal後は通常mouse状態へ戻る。
- 製品入力tapは、Nape ProのIOHID入力とCGEventの関連付け順序を維持できる`.cgSessionEventTap`のhead insertを使う。
- 対象button downのevent locationをsession固有の絶対cursor anchorとして1回だけ保存し、同じanchorへの`CGWarpMouseCursorPosition`が成功してからProductOutputを開始する。
- moveのX/Y delta、timestamp、capture orderをsource commandへ保存した直後、同じevent tap callback内でanchorへwarpし、その成功後にGestureClass出力を投稿して元moveを抑制する。wheelではwarpしない。
- button解放、cancel、timeout、tap中断、kill switch、runtime停止、出力失敗ではanchor stateを必ず破棄する。anchor取得またはwarpに失敗した場合はactive ProductOutput sessionをcancelへ収束させ、別方式へfallbackせずruntimeをfail closedにする。

### 6. 抑制前にreadinessを確定する

- 対象device、TCC、3 buttonの有効な割り当て、scroll contract、変換model、正負方向別の認識済みDockSwipe template fixtureを検証する。25F80で収録したtemplateはID `recognized-dockswipe-templates-25F80-v2`、contract ID `recognized-dockswipe-template-v2`、SHA-256 `852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6`を登録値とする。実行中OS buildは診断へ記録するがreadiness条件にしない。
- 3 classを安全に生成・終了できる場合だけevent tapと元入力抑制を開始する。
- 割り当て、fixture、model、adapterが欠落、未知、改変済み、または不一致なら全ProductOutput familyを無効にし、通常mouse入力を保持してruntime全体をfail closedする。診断出力や別配送へfallbackしない。

## 検証と完成判定

- 9通りのbutton-class対応、27通りの割り当て組み合わせ、既定値、保存、再起動後の復元を自動検査する。
- 無効・未割り当て値、button別感度、方向別binding、application別設定がcanonical設定とGUIにないことを検査する。
- button press時に選択classをsessionへ固定し、設定変更や追加buttonで途中切替しないことを検査する。
- 物理button番号に関係なく、3本指・4本指classだけへ共通感度が適用され、2本指classへ適用されないことを検査する。
- source sample 1対1 command化、exact timestamp、capture order、session ID、single terminalを検査する。
- 3 classのevent type、field、phase、batch、単位変換とIOHID motion 1 / 2 / 4をregistered fixtureへ照合する。
- system-wide posting、禁止経路非到達、unknown build / fixture mismatchのfail closedを検査する。
- Nape Gesture以外をforegroundにした署名済みRelease `.app`で、button 3 / 4 / 5の実cursor座標、高頻度move時の逸脱継続時間、wheel非移動、全terminal後の通常mouse復帰を検査する。
- Nape Proと純正trackpadでsource、selected class、generated event、OS / App結果、terminal、passthroughを物理受入する。

固定された既定割り当ての旧binaryでは、Nape Pro実機の3 class合計23 session、generated event 5473件、作成失敗0件、欠落投稿0件、全sessionのsingle terminalを確認した。この証跡はclass固有ProductOutputの履歴比較には使えるが、変更可能な割り当ての完成証跡には使わない。選択、保存、復元、重複割り当て、class基準の感度適用を現行release候補で再受入するまで、本変更を実装済みまたは完成とはしない。

## 影響

- exact timestamp、capture order、source command、session ID、single terminalのCore成果を維持する。
- GestureClassからProductOutput familyへの既存mappingとevent contractを変更しない。
- button 3 / 4 / 5からGestureClassへの対応だけをcanonical設定とGUIで選択可能にする。
- `TrackpadGestureMode`など旧型がmigrationまたは非製品診断の読込に残っても、現行割り当て、daemon分岐、GUI選択肢として使わない。
- requirements、README、completion checklist、verification、release、既存guardを同じ仕様へ同期する。

## 採用しない設計

- 物理buttonとGestureClassの対応を変更不能にする設計
- 無効または未割り当てのbuttonを設ける設計
- buttonごとに異なる感度を持つ設計
- 方向別actionまたはapplication別の有効・無効、感度、割り当て
- button間で出力上変更できる意味情報をfinger countだけに限定する設計
- 一つのgeneric finger-count eventをProductOutput contractにする設計
- raw digitizer、virtual HID、DriverKitを必要条件とする設計
- AX、対象PID、keyboard shortcutによる製品fallback

## 関連

- [ゴール要件](../requirements.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [ADR-0034](0034-reject-driverkit-virtual-trackpad.md)
- [ADR-0036](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0038](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0043](0043-trackpad-scroll-product-output.md)
