# ゴール要件

この文書をNape Gestureの製品要件の正本とする。Issue、ADR、README、GUI、runtime、test、release判定が矛盾する場合は、本書と[ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md)へ揃える。

## 最終ゴール

Nape Gestureを、Nape Proなどの通常mouse入力を、button 3 / 4 / 5ごとにユーザーが選択したmacOSの上位trackpad gestureへ変換する常駐GUIアプリとして完成させる。

製品はraw touch contactを生成しない。button 3 / 4 / 5のそれぞれに、物理trackpad driverが認識後に上位へ生成する3つのGestureClassから1つを割り当てる。選択後は各class固有のevent type、subtype、field、phase、companion lifecycle、単位変換を用い、system-wide event streamへ投稿する。

## button別GestureClass割り当て

| 対象button | 選択できるGestureClass | 既定値 |
| --- | --- | --- |
| button 3 | 2本指スクロール / スワイプ、3本指システムスワイプ、4本指システムピンチ | 2本指スクロール / スワイプ |
| button 4 | 2本指スクロール / スワイプ、3本指システムスワイプ、4本指システムピンチ | 3本指システムスワイプ |
| button 5 | 2本指スクロール / スワイプ、3本指システムスワイプ、4本指システムピンチ | 4本指システムピンチ |

同じGestureClassを複数buttonへ割り当ててよい。各buttonには常に1 classを割り当て、無効または未割り当てを表す値は持たない。button 3 / 4 / 5のいずれも未押下の場合と、それ以外のbuttonだけが押されている場合は、通常mouse入力を改変せず通過させる。

「2 / 3 / 4本指」はユーザー向けGestureClassの意味であり、raw digitizer contact count、generic `fingerCount` field、または一つのgeneric eventに格納するtransport fieldではない。classごとにevent family、event type、field、phase、companion lifecycle、motion、axis、符号規則を含むencodingを固定する。button割り当てを変更しても、GestureClassからProductOutputへのevent contractは変更しない。

GUIで編集できるgesture調整値は「システムジェスチャー感度」だけとする。canonical設定pathは`gesture.systemGestureSensitivity`、範囲は0.25から2.0（25%から200%）、既定値は1.0（100%）である。同じ倍率を、物理button番号に関係なく3本指system swipeと4本指system pinchを選択したsessionへ適用し、2本指scrollを選択したsessionには適用しない。100%時の変換は`(source / 600) * systemGestureSensitivity`とする。

製品は次を持たない。

- buttonごとの無効化または未割り当て
- button別感度、dead zone、加速度
- 方向別bindingまたはOS機能別action
- applicationごとの有効・無効、感度、割り当て

## 入力保存契約

- 対象button押下中のmove / wheel sampleを発生順に受理する。
- 各source sampleからちょうど1つの内部commandを生成し、欠落、重複、coalescing、並べ替えを行わない。
- commandはsource kind、X/Y量、符号、取得timestamp、0始まりのcapture order、session ID、source button、session開始時に選択したGestureClassを保持する。
- source timestampをsampleごとの投稿時刻で上書きしない。rebaseが必要ならsession全体へ単一offsetを適用する。
- direction reversal、軸変更、move / wheel混在を別action、別mode、別sessionへ再解釈しない。
- source commandから生成する低レベルevent数はclass contractに従う。scroll companionなど、1 commandから複数eventをbatch生成してよい。
- class固有のfield、phase、progress、velocity、motion、単位変換は、Apple公式資料、Apple OSS、自前fixtureから再導出したversioned contractに限定する。
- class間で同じevent type、field、単位変換を強制しない。class固有encodingをapplication別routingとみなさない。
- threshold、dead zone、ユーザー加速度によって有効なsource sampleを破棄または改変しない。`systemGestureSensitivity`は保存済みsource値を変えず、選択された3本指 / 4本指classのProductOutput変換時にだけ適用する。
- 対象button downのevent locationをsession固有の絶対cursor anchorとして1回だけ保存し、同じanchorへの`CGWarpMouseCursorPosition`成功後にだけProductOutputを開始する。
- 各moveではX/Y量、timestamp、capture orderを先に保存し、同じevent tap callback内でanchorへwarpしてからGestureClass出力へ渡し、元mouse eventを抑制する。
- wheel sampleではcursorを移動させず、不要なwarpを行わない。
- button解放、cancel、timeout、tap中断、kill switch、runtime停止、出力失敗ではanchorを必ず破棄し、terminal後は通常mouse入力をそのまま通す。
- anchor取得またはwarpに失敗した場合はactive ProductOutput sessionをcancelへ収束させ、別のcursor固定方式へfallbackせずruntimeをfail closedにする。
- cursor固定のためにforeground化、focus移動、逆delta、AX、対象PID、keyboard shortcut、DriverKitを使わない。

## ProductOutput要件

### 2本指スクロール / スワイプ

- `twoFingerScrollSwipe` classを`scroll` adapterへ接続する。どのbuttonから選択されたかでcontractを変えない。
- input lifecycleではtype 22 scrollと、物理contractが要求するgesture envelope / companion eventを整合したbatchで生成する。
- 縦横成分を同じscroll sessionで扱う。
- 水平scrollによるページ移動などはapplicationの標準解釈に任せる。
- `NavigationSwipe`を別class、別button、別製品capabilityとして追加しない。

- event typeはscrollが22、envelope / companionが29で、scroll phase field 99とcompanion phase field 132を別々に持つ。
- line / fixed-point / point deltaとcompanion motionは、登録済みscroll contractと変換modelの単位に従う。

### 3本指システムスワイプ

- `threeFingerSystemSwipe` classを`DockSwipe` adapterへ接続する。どのbuttonから選択されたかでcontractを変えない。
- type 30、classifier field 110 = 23、phase fields 132 / 134 = began 1、changed 2、ended 4、cancelled 8とする。
- 水平と垂直のsource入力をIOHID `DockSwipe` motion 1 / 2、累積progress、XY position、終端XY velocityへ変換する。motionとprogress増分は`(source delta / 600) * systemGestureSensitivity`、終端velocityは`(source velocity / 600) * systemGestureSensitivity`とする。
- Spaces、Mission Control、App ExposeはmacOSが解釈するOS結果として別途受入する。

### 4本指system pinch

- `pinch` classを`dockSwipePinch` payloadへ接続し、認識済みtype 30 / classifier 23のIOHID `DockSwipe`をmotion 4で構成する。どのbuttonから選択されたかでcontractを変えない。
- phase fieldsは3本指classと同じ1 / 2 / 4 / 8を使う一方、XY positionと終端XY velocityは0、pinch progressはYが非0なら`(-Y / 600) * systemGestureSensitivity`、それ以外は`(X / 600) * systemGestureSensitivity`を累積し、同じ符号規則の`(source velocity / 600) * systemGestureSensitivity`を終端Z velocityへ設定する。
- application magnification event、generic finger count field、3本指classのmotion 1 / 2へ置き換えない。

### 共通投稿境界

- eventはsystem-wideへだけ投稿する。
- 対象PID投稿、AX操作、keyboard shortcut、frontmost application分岐を製品fallbackにしない。
- DriverKit、virtual HID、virtual trackpad、raw digitizer contactを使わない。
- 通常SDK非公開のcontractは最小compatibility adapterへ隔離する。
- 25F80の正負方向別認識済みDockSwipe templateはfixture ID `recognized-dockswipe-templates-25F80-v2`、contract ID `recognized-dockswipe-template-v2`、SHA-256 `852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6`を登録値とする。
- output contractはfixture ID、SHA-256、schema、contract ID、fixture実体、および収録元OS version `26.5.1` / build `25F80`を含む同梱asset間のprovenanceが完全一致した場合だけ`supported`とする。収録元OS情報を実行中macOSのversion / buildとは比較しない。認識済みtype 30 templateからIOHID eventを復元し、timestamp、sender ID、phase flags、motion、flavor、progress、position、終端velocityを更新後に再検証する。
- scroll contract、変換model、DockSwipe templateのいずれかが欠落、未知、未登録、改変済み、またはcontract不一致なら全ProductOutput familyを無効にし、元入力を抑制する前にruntime全体をfail closedする。明示path不正時は別fixtureへfallbackしない。
- 診断出力を製品fallback、readiness、完成証跡に使わない。

## session要件

- button press時にそのbuttonの保存済み割り当てを解決し、対応releaseまたはcancelまでを一つのsessionとしてsource buttonと選択済みGestureClassを固定する。
- 設定変更は新規sessionから反映し、active sessionのclassを途中で変更しない。
- session中の追加buttonでclass、session ID、adapterを切り替えない。曖昧な同時押下は安全に拒否する。
- `began / changed / ended / cancelled`を表現し、物理contractが必要とする補助lifecycleをclass adapterで生成する。
- release、cancel、kill switch、runtime stop、sleep、device切断、権限喪失、event作成失敗、投稿失敗のすべてでsingle terminalへ収束する。
- terminal後に同じsessionのeventを生成しない。
- batchを全件構築・検証してから投稿する。部分投稿後は未投稿offsetと順序を保持し、同じsessionのterminalだけを再試行する。
- 生成eventのfeedback loop、二重terminal、stuck session、古いdaemon generationからの遅延callbackを防ぐ。
- `Control + Option + Command + G`のkill switchでactive sessionを閉じ、runtimeを停止できる。

## 通常mouseとdevice境界

- 対象deviceを識別し、対象外deviceを変換または抑制しない。
- 複合HID deviceは`Generic Desktop / Mouse`のtop-levelインターフェースだけを列挙、open、入力受理の対象にする。同じ物理deviceのkeyboard、consumer control、vendor-definedインターフェースを開かない。
- button 3 / 4 / 5未押下時はclick、move、drag、wheel、その他buttonを通常どおり通す。
- active sessionの元button、move、wheelだけを必要範囲で抑制する。
- session終了、cancel、kill switch、runtime停止後は通常mouse状態へ戻る。
- 生成可能性を確定する前に元入力を抑制しない。

## GUIと設定

- Dockに表示される通常GUIアプリとして起動し、設定windowとmenubar状態を持つ。
- GUIにはbutton 3、4、5ごとに3 GestureClassだけを選べるselectorを表示する。
- selectorは同じclassの重複選択を許可し、無効・未割り当てを選択肢に含めない。
- 「システムジェスチャー感度」を25%から200%、既定100%の共通sliderとして表示する。
- button別または方向別の感度、方向別binding、application別設定を表示しない。
- 共通のシステムジェスチャー感度以外では、対象device条件、cancel時間、diagnostics、安全停止などgesture意味を変えない運用項目だけを設定可能にする。
- canonical割り当ては`gesture.buttonAssignments.button3` / `button4` / `button5`へ保存する。割り当てがない固定モデルの設定には既定割り当てを補い、有効なcanonical割り当ては重複を含めそのまま保持する。
- 旧mode、旧action、`dragSensitivity`、`wheelSensitivity`などの旧感度値は、現行割り当てまたは共通感度へ推測移行せず、読込時にcanonical設定から原子的に除去する。`gesture.systemGestureSensitivity`がない旧設定には1.0を補い、既存のcanonical値は範囲検証後に保持する。
- migration失敗時は原本を保持し、runtimeを開始しない。
- GUIと`doctor --json`で実行主体、Accessibility、Input Monitoring、対象device、OS build、必須ProductOutput family `scroll` / `dockSwipe` / `dockSwipePinch`、fail-closed理由を確認できる。

## OS / application結果

次は生成した上位gestureを受けたmacOSまたはapplicationの結果であり、Nape Gestureのmodeではない。

- 縦横scroll、nested scroll target
- 水平scrollに対するページ戻る・進むなどのapplication標準動作
- Spaces、Mission Control、App Expose
- DockSwipe motion 4に対するDockのsystem pinch解釈

各scenarioで、低レベルevent contract、OS / App結果、純正trackpadとの体感差を別々に判定する。画面が動いたことだけをcontract一致の証明にせず、contract一致だけを画面結果の証明にしない。

## 証跡要件

純正trackpad、Nape Pro source、Nape Gesture generated eventを同じversioned schemaで記録する。最低限、次を保存する。

- source device、button、GestureClass、source kind
- X/Y量、符号、capture order、source timestamp、generated timestamp
- event type、subtype、field、phase、companion relation
- session ID、terminal種別、cancel理由
- 抑制、passthrough、生成、drop、retryの件数
- OS version / build、contract ID、fixture ID、SHA-256
- run UUID、repo SHA、binary SHA-256、system-wide post trace

人間作業は、Nape Proや純正trackpadの物理操作、本人しか通せない認証などcomputer-useで代替できないものだけに限定する。

## 品質・性能

- 常駐CPU、memory、event tap latency、tap-to-post latency、terminal latency、drop率を計測する。
- pure logicと実機runtimeを分け、p50、p95、p99、最大値、sample数を保存する。
- 3 GestureClassと通常mouse passthroughを同じ基準で測る。
- 入力速度やsession長でqueueが無制限に増えない。
- sleep復帰、device抜き差し、runtime再起動、権限変更後に安全に復旧する。
- setting migration、recognizer、session、ProductOutput、suppression、doctorにessential testを持つ。

## 由来とライセンス

- 実装contractとパラメータはApple公式資料、Apple OSS、自前ログから再導出する。
- field、状態遷移、係数、許容誤差を資料または自前fixtureまで追跡可能にする。
- 第三者成果物由来のコード、定数、状態遷移、係数を取り込まない。
- 実装と製品surfaceに置く外部固有名は、実装上必要な実依存の識別子と法定通知に限定する。
- 公開fixtureにkeyboard data、個人情報、不要なdevice識別子を含めない。

## 現在位置と完成判定

button割り当てのCore、runtime、GUI、canonical migrationは同じ署名済みRelease候補へ接続済みである。全9 button-class対応、全27割り当てのcanonical round-trip、重複割り当て、active session固定、選択classに応じた感度、GUI保存と再起動後復元を機械検証したため試用可能とする。既定button以外からのNape Pro物理受入が終わるまでは完成とは表現しない。

固定された既定割り当ての旧binaryではNape Pro実機の3 classを合計23 session収録し、beganとendedが各sessionで1対1、生成event 5473件、event作成失敗0件、欠落投稿0件であることを確認した。この証跡はclass固有ProductOutputの履歴比較には使えるが、変更可能な割り当ての証跡には使わない。純正trackpadとの最終比較、異常終了後の復旧、App Exposeの設定依存結果、公開配布署名も未完了である。次をすべて満たしたときだけ製品完成とする。

- 日常利用する`.app`で9通りのbutton-class対応が動作し、27通りの割り当て組み合わせを選択・保存・復元できる。
- source sample 1対1 command化、exact timestamp、capture order、single terminalを再現可能な証跡で説明できる。
- 3 class固有のevent contractが純正trackpad fixtureと一致する。
- 未押下、正常終了、異常終了後の通常mouse passthroughを実機で確認する。
- Nape Pro、純正trackpad、generated event、OS / App結果を同一OS buildで受入する。
- suppression、kill switch、sleep、抜き差し、権限変更、未知OS fail closed、migration、性能を検証する。
- Developer ID署名、公証、stapler、Gatekeeper評価まで配布物を検証する。
- README、ADR、completion checklist、GUI、runtime、test、CIが同じGestureClassモデルを説明する。
