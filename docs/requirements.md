# ゴール要件

この文書をNape Gestureの製品要件の正本とする。Issue、ADR、README、GUI、runtime、test、release判定が矛盾する場合は、本書と[ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md)へ揃える。

## 最終ゴール

Nape Gestureを、Nape Proなどの通常mouse入力を、固定buttonに対応するmacOSの上位trackpad gestureへ変換する常駐GUIアプリとして完成させる。

製品はraw touch contactを生成しない。button 3 / 4 / 5は、物理trackpad driverが認識後に上位へ生成するgestureの意味classを固定選択する。各class固有のevent type、subtype、field、phase、companion lifecycle、単位変換を用い、system-wide event streamへ投稿する。

## 固定GestureClass

| mouse入力 | 固定GestureClass | 必須ProductOutput |
| --- | --- | --- |
| button 3押下中 | 2本指スクロール / スワイプ相当 | type 22 scrollと必要なgesture companion lifecycle |
| button 4押下中 | 3本指システムスワイプ相当 | type 30 `DockSwipe`、motion 1 / 2 |
| button 5押下中 | 4本指system pinch相当 | type 30 `DockSwipe`、motion 4 |
| 上記button未押下 | 変換なし | 通常mouse入力を改変せず通過させる |
| 上記以外のbutton | 変換なし | 通常mouse入力を改変せず通過させる |

「2 / 3 / 4本指」はユーザー向け固定GestureClassの意味であり、raw digitizer contact count、generic `fingerCount` field、または一つのgeneric eventに格納するtransport fieldではない。classごとに低レベルevent type、field、phase、companion lifecycle、単位変換が異なることを必須設計とする。

この対応は固定であり、次を持たない。

- buttonごとの無効化またはmode selector
- ユーザー変更可能な割り当て、感度、dead zone、加速度
- 方向別bindingまたはOS機能別action
- applicationごとの有効・無効、感度、割り当て

## 入力保存契約

- 対象button押下中のmove / wheel sampleを発生順に受理する。
- 各source sampleからちょうど1つの内部commandを生成し、欠落、重複、coalescing、並べ替えを行わない。
- commandはsource kind、X/Y量、符号、取得timestamp、0始まりのcapture order、session ID、固定GestureClassを保持する。
- source timestampをsampleごとの投稿時刻で上書きしない。rebaseが必要ならsession全体へ単一offsetを適用する。
- direction reversal、軸変更、move / wheel混在を別action、別mode、別sessionへ再解釈しない。
- source commandから生成する低レベルevent数はclass contractに従う。scroll companionなど、1 commandから複数eventをbatch生成してよい。
- class固有のfield、phase、progress、velocity、motion、単位変換は、Apple公式資料、Apple OSS、自前fixtureから再導出したversioned contractに限定する。
- class間で同じevent type、field、単位変換を強制しない。class固有encodingをapplication別routingとみなさない。
- threshold、dead zone、感度、ユーザー加速度によって有効なsource sampleを破棄または改変しない。
- gesture session中はmouseとcursorのQuartz連動を停止し、画面上のmouse cursorを移動させない。
- button解放、cancel、tap中断、runtime停止、出力失敗では連動を必ず復元し、通常のcursor追従へ戻す。

## ProductOutput要件

### 2本指スクロール / スワイプ

- button 3のclassを`scroll` adapterへ接続する。
- input lifecycleではtype 22 scrollと、物理contractが要求するgesture envelope / companion eventを整合したbatchで生成する。
- 縦横成分を同じscroll sessionで扱う。
- 水平scrollによるページ移動などはapplicationの標準解釈に任せる。
- `NavigationSwipe`を別class、別button、別製品capabilityとして追加しない。

- event typeはscrollが22、envelope / companionが29で、scroll phase field 99とcompanion phase field 132を別々に持つ。
- line / fixed-point / point deltaとcompanion motionは、登録済みscroll contractと変換modelの単位に従う。

### 3本指システムスワイプ

- button 4のclassを`DockSwipe` adapterへ接続する。
- type 30、classifier field 110 = 23、phase fields 132 / 134 = began 1、changed 2、ended 4、cancelled 8とする。
- 水平と垂直のsource入力をIOHID `DockSwipe` motion 1 / 2、累積progress、XY position、終端XY velocityへ変換する。motionとprogress増分はsource delta / 300、終端velocityはsource delta / 経過秒 / 300を基準とする。
- Spaces、Mission Control、App ExposeはmacOSが解釈するOS結果として別途受入する。

### 4本指system pinch

- button 5のclassを`dockSwipePinch` payloadへ接続し、認識済みtype 30 / classifier 23のIOHID `DockSwipe`をmotion 4で構成する。
- phase fieldsは3本指classと同じ1 / 2 / 4 / 8を使う一方、XY positionと終端XY velocityは0、pinch progressはYが非0なら`-Y / 300`、それ以外は`X / 300`を累積し、同じ符号規則のsource velocity / 300を終端Z velocityへ設定する。
- application magnification event、generic finger count field、3本指classのmotion 1 / 2へ置き換えない。

### 共通投稿境界

- eventはsystem-wideへだけ投稿する。
- 対象PID投稿、AX操作、keyboard shortcut、frontmost application分岐を製品fallbackにしない。
- DriverKit、virtual HID、virtual trackpad、raw digitizer contactを使わない。
- 通常SDK非公開のcontractは最小compatibility adapterへ隔離する。
- 25F80の正負方向別認識済みDockSwipe templateはfixture ID `recognized-dockswipe-templates-25F80-v2`、contract ID `recognized-dockswipe-template-v2`、SHA-256 `852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6`を登録値とする。
- output contractはfixture ID、SHA-256、schema、contract ID、OS version `26.5.1` / build `25F80`、fixture実体が完全一致した場合だけ`supported`とする。認識済みtype 30 templateからIOHID eventを復元し、timestamp、sender ID、phase flags、motion、flavor、progress、position、終端velocityを更新後に再検証する。
- scroll contract、変換model、DockSwipe templateのいずれかが欠落、未知、未登録、改変済み、またはcontract不一致なら全ProductOutput familyを無効にし、元入力を抑制する前にruntime全体をfail closedする。明示path不正時は別fixtureへfallbackしない。
- 診断出力を製品fallback、readiness、完成証跡に使わない。

## session要件

- button pressから対応releaseまたはcancelまでを一つのsessionとし、source buttonとGestureClassを固定する。
- session中の追加buttonでclass、session ID、adapterを切り替えない。曖昧な同時押下は安全に拒否する。
- `began / changed / ended / cancelled`を表現し、物理contractが必要とする補助lifecycleをclass adapterで生成する。
- release、cancel、kill switch、runtime stop、sleep、device切断、権限喪失、event作成失敗、投稿失敗のすべてでsingle terminalへ収束する。
- terminal後に同じsessionのeventを生成しない。
- batchを全件構築・検証してから投稿する。部分投稿後は未投稿offsetと順序を保持し、同じsessionのterminalだけを再試行する。
- 生成eventのfeedback loop、二重terminal、stuck session、古いdaemon generationからの遅延callbackを防ぐ。
- `Control + Option + Command + G`のkill switchでactive sessionを閉じ、runtimeを停止できる。

## 通常mouseとdevice境界

- 対象deviceを識別し、対象外deviceを変換または抑制しない。
- button 3 / 4 / 5未押下時はclick、move、drag、wheel、その他buttonを通常どおり通す。
- active sessionの元button、move、wheelだけを必要範囲で抑制する。
- session終了、cancel、kill switch、runtime停止後は通常mouse状態へ戻る。
- 生成可能性を確定する前に元入力を抑制しない。

## GUIと設定

- Dockに表示される通常GUIアプリとして起動し、設定windowとmenubar状態を持つ。
- GUIにはbutton 3、4、5の固定GestureClassを読み取り専用で表示する。
- mode selector、感度、方向別binding、application別設定を表示しない。
- 対象device条件、cancel時間、diagnostics、安全停止などgesture意味を変えない運用項目だけを設定可能にする。
- 旧mode、旧action、旧button assignment、旧感度値を読込時にcanonical設定へ原子的に移行し、保存時に除去する。
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

固定GestureClass recognizer、exact timestamp、capture order、session machine、3 classから既存ProductOutputへの接続、固定GUI、canonical migration、doctor、system-wide投稿経路は実装済みである。release buildの`/Applications/Nape Gesture.app`をインストールし、現在の署名identityへAccessibility / Input Monitoringを付与してGUI runtimeを稼働している。system-testではDockが3本指の水平`DockSwipe`で左右のSpaceを切り替え、垂直`DockSwipe`とmotion 4の正負両方向を受理済みである。現在のmacOS設定ではApp Exposéがオフのため、その画面結果は未確認である。

Nape Pro実機ではbutton 3 / 4 / 5の3 classを合計23 session収録し、beganとendedが各sessionで1対1、生成event 5473件、event作成失敗0件、欠落投稿0件であることを確認した。button 4のSpace切替とMission Control、button 5のDock system control遷移、session後の通常操作復帰も同じ稼働中runtimeで確認している。ただし、純正trackpadとの最終比較、異常終了後の復旧、App Exposéの設定依存結果、公開配布署名は未完了である。次をすべて満たしたときだけ製品完成とする。

- 日常利用する`.app`で3 buttonが常に固定GestureClassとして動く。
- source sample 1対1 command化、exact timestamp、capture order、single terminalを再現可能な証跡で説明できる。
- 3 class固有のevent contractが純正trackpad fixtureと一致する。
- 未押下、正常終了、異常終了後の通常mouse passthroughを実機で確認する。
- Nape Pro、純正trackpad、generated event、OS / App結果を同一OS buildで受入する。
- suppression、kill switch、sleep、抜き差し、権限変更、未知OS fail closed、migration、性能を検証する。
- Developer ID署名、公証、stapler、Gatekeeper評価まで配布物を検証する。
- README、ADR、completion checklist、GUI、runtime、test、CIが同じGestureClassモデルを説明する。
