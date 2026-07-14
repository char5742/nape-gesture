# 検証手順と既知の失敗条件

この文書は、button 3 / 4 / 5を固定された上位`GestureClass`へ接続する製品runtimeの検証手順を定義する。完成状態の正本は[完成判定チェックリスト](completion-checklist.md)、製品モデルの正本は[ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md)とする。

## 検証対象

| mouse入力 | 固定GestureClass | 期待ProductOutput |
| --- | --- | --- |
| button 3押下中 | 2本指scroll / swipe相当 | type 22 scrollと必要なtype 29 companion lifecycle |
| button 4押下中 | 3本指system swipe相当 | type 30 `DockSwipe`、motion 1 / 2 |
| button 5押下中 | 4本指system pinch相当 | type 30 `DockSwipe`、motion 4 |
| button 3 / 4 / 5未押下 | 変換なし | 通常mouse入力をそのまま通す |

「2 / 3 / 4本指」はraw contact数やgeneric `fingerCount` transportではない。物理trackpad driverがgestureを認識した後に生成する上位gestureの意味classである。したがって、classごとにevent type、field、phase、companion、event件数、単位変換が異なることを正常かつ必須とする。

buttonから選ぶclassは固定であり、mode selector、方向別binding、button別・方向別・application別の感度設定を持たない。GUIの「システムジェスチャー感度」だけをbutton 4 / 5へ共通適用し、button 3は変更しない。内部でclass固有adapterを選ぶことは、ユーザー向けroutingではなく上位event contractのencodingである。

## 現在の確認状態

製品runtimeは次の経路で接続済みである。

```text
CGEventUtilities
  -> FixedGestureInputRecognizer
  -> FixedGestureSessionMachine
  -> FixedGestureProductSessionCoordinator
  -> ProductGestureOutput
  -> system-wide event stream
```

Nape Proの主要経路は、3 class合計23 session、5473 generated event、作成失敗0件、欠落投稿0件、全sessionのsingle terminal、終了後の通常mouse復帰まで受入済みである。Space切替、Mission Control、DockSwipe motion 4のsystem control遷移も確認済みである。

次は別の未完了gateとして扱う。

- 現行release候補と純正trackpad fixtureの最終比較
- kill switch、device切断、sleep、TCC喪失後の物理passthrough復旧
- macOS設定で無効なApp Exposeの画面結果
- Developer ID署名、公証、stapler、Gatekeeperによる公開配布

## 自動検証

同じworktreeからDebug、Release、bundleを生成し、次を実行する。

```sh
ruby scripts/check-product-model-documentation.rb
ruby scripts/check-fixed-gesture-class-product-model.rb
sh scripts/check-provenance.sh
sh scripts/test-check-provenance.sh
sh scripts/check-product-output-boundary.sh
sh scripts/check-diagnostic-event-time.sh

swift build --scratch-path .build -Xswiftc -warnings-as-errors
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture-product-output-tests
.build/debug/nape-gesture-diagnostic-output-tests
sh scripts/test-settings-store-stability.sh .build/debug/nape-gesture
sh scripts/test-doctor-readiness.sh .build/debug/nape-gesture
sh scripts/test-bundle-app-safety.sh .build/debug/nape-gesture
.build/debug/nape-gesture gui-smoke --json --assert

swift build -c release --scratch-path .build -Xswiftc -warnings-as-errors
.build/release/nape-gesture-core-tests
.build/release/nape-gesture-product-output-tests
.build/release/nape-gesture-diagnostic-output-tests
```

CIでは同じ回帰testを反復し、Address SanitizerとUndefined Behavior Sanitizerを別jobで実行する。ローカルOSのsanitizer runtime自体が最小プログラムで起動不能な場合は成功へ読み替えず、対応runnerのCI結果を必要gateとして残す。

## source sample保存

accepted move / wheel sampleごとに1つのsource commandを生成し、次を保持する。

- source kind
- X / Y量と符号
- exact monotonic timestamp
- capture order
- session ID
- source button
- 固定GestureClass

合格条件:

- source sampleを欠落、重複、coalesce、並べ替えしない
- 正負X、正負Y、斜め、停止、方向反転、move / wheel混在を保持する
- sample間隔を現在時刻で再生成しない
- terminal用zero frameやcompanion eventをsource量として数えない
- 1 source commandから複数の低レベルeventを生成する場合も、batch内順序と同じsource timestampを保持する

最終delta合計だけの一致では不十分である。途中で符号が相殺される系列でも、各sampleとgenerated batchを対応付ける。

## class固有ProductOutput

### 2本指scroll / swipe class

- type 22 scrollと必要なtype 29 companionを1 batchとして生成する
- scroll phaseとcompanion phaseをそれぞれのfieldへ設定する
- X / Yの符号、point / fixed / line / gesture motion単位を登録contractへ照合する
- `systemGestureSensitivity`を0.25 / 1.0 / 2.0へ変えても出力が変わらない
- horizontal scrollのページ移動はapplicationの標準解釈に任せる

### 3本指system swipe class

- type 30 / classifier 23の認識済み`DockSwipe`を使う
- horizontal / verticalをmotion 1 / 2、phase 1 / 2 / 4 / 8へencodingする
- progress、XY motion、終端XY velocityが`(source / 600) * systemGestureSensitivity`となることを0.25 / 1.0 / 2.0で検査し、登録済みfixtureと変換modelへ照合する

### 4本指system pinch class

- type 30 / classifier 23の認識済み`DockSwipe` motion 4を使う
- progressと終端Z velocityが符号規則を維持した`(source / 600) * systemGestureSensitivity`となることを0.25 / 1.0 / 2.0で検査し、motion、phase 1 / 2 / 4 / 8とともに登録済みfixtureへ照合する
- application magnification eventへ置き換えない

全classでsystem-wide投稿だけを使う。AX scrollbar、対象PID配送、frontmost application分岐、keyboard shortcut、DriverKit、virtual HID、raw digitizerをfallbackにしない。

## sessionと復旧

button downからreleaseまたはcancelまでsource buttonとGestureClassを固定する。進行中に別buttonが追加されてもclassやsession IDを切り替えない。

次の各経路を検証する。

- 正常release
- recognizer cancelとtimeout
- kill switchとmanual stop
- sleep / wakeと重複wake
- device切断
- TCC喪失
- event作成失敗
- 部分投稿と投稿失敗
- contract不一致

合格条件:

- terminalはsessionごとに一度だけ生成する
- terminal後に同じsessionのeventを投稿しない
- 部分投稿では未投稿offsetと順序を保持して同じsessionを閉じる
- terminal失敗を成功扱いにせず、新規sessionを開始しない
- sleepを伴わないwake通知と重複wakeでrunning状態や保留retryを破壊しない
- manual stop後に自動再開しない

## passthroughとcursor

button 3 / 4 / 5未押下時は、move、click、double-click、drag、wheel、button 1 / 2、対象外buttonを変更せず通す。対象deviceと対象外deviceを分けて検証する。

対象button downのevent locationをsession固有の絶対cursor anchorとして保存し、同じ座標への`CGWarpMouseCursorPosition`成功後にだけ出力を開始する。各moveではdelta、timestamp、capture orderを保存した後、同じevent tap callback内でanchorへ戻してからGestureClass出力を投稿する。wheelではwarpしない。button解放、cancel、timeout、tap中断、kill switch、runtime停止、出力失敗ではanchorを破棄する。

`system-test run --scenario gesture-drag --logical-button 3|4|5 --target finder --steps 120 --interval 0.001 --assert-cursor-anchor`を署名済みRelease `.app`のbackground runtimeへ入力し、実cursor座標、最大逸脱、逸脱継続時間、未投稿mouse event数、wheel session、解放後の通常move復帰を検査する。closure呼び出しやstate testだけではcursor固定の完成証跡にしない。

異常終了時はactivation buttonの物理解放前に途中のdown / upを通常clickとして漏らさず、解放後に通常passthroughへ戻す。

## 設定とGUI

設定検証は次を含む。

- 旧mode、`dragSensitivity`、`wheelSensitivity`、dead zone、application設定をcanonical形式から除去し、旧感度を`systemGestureSensitivity`へ移行しない
- `gesture.systemGestureSensitivity`がない旧設定には1.0を補い、既存値は0.25から2.0の範囲を検証する
- GUI sliderが25%から200%、既定100%で、button別・方向別・application別のcontrolを持たない
- 不正な旧設定は原本bytesを保持し、runtimeを開始しない
- canonical設定の再読込では不要な再書込をしない
- 複数processのmigration / saveを設定file単位で排他する
- lock fileのsymlink差し替えを拒否する
- GUIで先頭device条件を編集しても後続条件を失わない
- 保存失敗時は未保存状態とApplyの再試行可能状態を保持する
- 不正な数値入力を保存せず、保存済み設定を維持する

GUI smokeでは固定mapping、共通感度sliderと現在値表示、通常mouse通過説明、runtime状態、toolbar、詳細条件の開閉、pane切替、control数、非resizable window、Applyのdirty stateをAppKit上で検証する。実際のLaunchServices起動ではAX treeと画面を確認し、一時設定だけを編集・保存してdisk反映を検証する。

## doctorとruntime identity

doctorは未知option、重複option、値欠落、不正benchmark件数を拒否する。readinessは設定、Accessibility、HID inventory、対象device、Input Monitoring probe、3つの必須ProductOutput familyを同じreportで判定する。

`.app`内実行ファイルをterminalから起動した場合は`commandLine`、LaunchServicesから起動した場合は`launchServicesApp`として扱う。LaunchServices判定には次を全て要求する。

- `.app` bundleである
- parent PIDが1である
- `XPC_SERVICE_NAME`がbundle IDと一致する
- `__CFBundleIdentifier`がbundle IDと一致する

環境変数だけを偽装したCLIはGUIアプリとして扱わない。条件が曖昧な場合はTCC帰属先を推測せず`unknown`としてreadinessを失敗させる。

## fail closed

次ではevent tapと新規入力抑制を開始しない。

- 登録済みeventを構築できない、または投稿前field検証が成立しない環境
- fixture ID、SHA-256、schema、contract ID、収録元OS build、実体bytesの不一致。収録元OS buildはasset間で照合し、host OS buildとは比較しない
- scroll contract、変換model、DockSwipe templateの欠落または改変
- 対象device不一致
- AccessibilityまたはInput Monitoring不足
- timestamp、capture order、session、event batchの不整合
- event作成または投稿失敗を安全に閉じられない状態

diagnostic output、別event family、AX、PID、shortcutへfallbackしない。

## 実機検証

### 純正trackpad

検証対象macOS buildごとに、2本指scroll / swipe、3本指system swipe、4本指system pinchの正負方向、開始、changed、正常terminal、cancelを収録する。raw event、serialized event、manifest、fixture SHA-256、OS buildを同じrunへ結び付ける。

### Nape Pro

同じrelease候補で次を確認する。

- button 3 / 4 / 5がそれぞれ固定classだけを開始する
- source sampleとgenerated batchの量、符号、順序、timestampが対応する
- 全sessionがsingle terminalへ収束する
- gesture中にcursorが動かず、解放後に通常追従へ戻る
- 未押下のmove、click、drag、wheelが通常mouseとして動作する
- Space、Mission Control、App Expose、system pinchなどのOS結果を低レベルcontractと別に記録する

画面結果だけで低レベルcontract合格にしない。低レベルcontractが合格してもOS設定や前面Appにより結果が成立しない場合は、両者を別判定として記録する。

## 即時不合格

- buildまたは個別test成功だけで製品完成とする
- generic `fingerCount` eventやraw contact数を生成すると解釈する
- 3 classへ同じevent family、field、単位変換を強制する
- source sampleを最終deltaだけで比較する
- terminalなし、重複terminal、terminal後出力、stuck sessionがある
- 保存失敗後にGUIを保存済み表示へ変える
- HID inventory取得失敗を0台と表示する
- TCCの起動主体を環境変数だけで決める
- unsupported条件で抑制を先に開始する
- 異なるrun、binary、OS buildの証跡を混ぜる
- ad-hoc署名を公開配布署名として扱う

## 完成判定

[完成判定チェックリスト](completion-checklist.md)の全gateが、同じrelease候補、repo SHA、binary SHA-256、OS buildへ結び付いた場合だけ完成とする。自動検証は物理device受入を代替せず、画面証跡はruntime log、doctor、fixture、manifestを代替しない。
