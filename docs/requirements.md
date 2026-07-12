# ゴール要件

この文書をNape Gestureの製品要件の正本とする。Issue、ADR、README、設定UI、runtime、テスト、release判定が矛盾する場合は、本書と[ADR-0049](adr/0049-fixed-button-to-finger-count-trackpad-input.md)へ揃える。

## 最終ゴール

Nape Gestureを、Nape Proなどの通常マウス入力が持つ連続的なイベント量を、macOSが受け取る本来のトラックパッド入力へ置換する常駐GUIアプリとして完成させる。

製品が「スクロール」「ページ移動」「Mission Control」「Zoom」などの結果を選ぶのではない。製品の責務は、押されているmouse buttonから指本数を決め、入力のX/Y量、符号、順序、時刻、速度の連続性を保ったトラックパッド入力列を生成するところまでである。最終的な画面結果はmacOSまたは前面applicationが解釈する。

## 製品モデル

### 固定buttonと指本数

| mouse入力 | trackpad入力 | 動作 |
| --- | --- | --- |
| button 3押下中 | 2本指 | 連続イベント量を2本指trackpad入力として生成する |
| button 4押下中 | 3本指 | 連続イベント量を3本指trackpad入力として生成する |
| button 5押下中 | 4本指 | 連続イベント量を4本指trackpad入力として生成する |
| 上記button未押下 | 変換なし | 通常mouse入力を改変せず通過させる |
| 上記以外のbutton | 変換なし | 通常mouse入力を改変せず通過させる |

この対応は固定であり、ユーザーが結果別modeやactionをbuttonへ割り当てる設定は持たない。buttonは結果を選ぶためではなく、生成するtrackpad入力の指本数だけを選ぶ。

### イベント量の置換

- mouse moveとwheelが持つX/Y量、符号、方向反転、発生順、timestamp、sample間隔を入力列として保持する。
- button 3 / 4 / 5の違いで変えてよい意味情報は`fingerCount`だけとする。同じ入力列に対し、結果別の別変換器を選ばない。
- mouse単位とtrackpad単位が異なる場合は、純正trackpadとNape Proの自前計測から再導出した単一の単位変換contractを使う。
- 単位変換contractは軸ごとの物理単位差やOS build差を表現できるが、Space切替、ページ移動、Zoomなどの結果に合わせた係数を持たない。
- 優勢軸への固定、直交成分の破棄、結果別progress正規化、結果別velocity正規化、方向別action選択を行わない。
- 有効なsource sampleをthreshold、dead zone、acceleration、感度、clampで変更または破棄しない。複数source sampleを1 sampleへcoalesceしない。
- phase、companion event、momentumなど物理trackpad driver上位contractが要求する補助eventは、自前fixtureから導出したversioned contractでだけ生成し、source event量と分けて対応付ける。ユーザー調整値にしない。

### event familyと画面結果

`scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`などの名称は、物理trackpadと生成eventを解析するための低レベルevent familyまたはcontract識別子に限定する。ユーザー向けmode、buttonの割り当て先、application別routingにはしない。

次の項目はmacOSまたは前面applicationで観測する結果であり、Nape Gestureが直接選択する製品機能ではない。

- 縦横scrollとnested scroll target
- ページ戻る・進む、履歴移動、AppKit swipe受信
- Space切替、Mission Control、App Expose
- applicationの拡縮、AppKit magnify受信

同じfinger countと入力列でも、macOS設定、application、focus、画面状態、OS buildにより結果は変わり得る。結果を成立させるためのkeyboard shortcut、AX操作、対象PIDへのevent投稿、application別分岐を製品fallbackにしない。

## 入力session要件

- 対象デバイスを識別し、対象外デバイスの入力を変換または抑制しない。
- button 3 / 4 / 5のpressでsessionを開始し、対応するreleaseまでfinger countを固定する。
- session中に別のgesture buttonが押されてもfinger countやevent familyを切り替えない。曖昧なbutton組み合わせは安全に拒否する。
- 入力sampleを一つの連続sessionとして扱い、途中の軸変更、方向反転、moveとwheelの到着で別結果へroutingしない。
- 元入力の抑制は、対応するtrackpad入力を安全に生成できることが確定した後にだけ開始する。
- 変換対象sessionの元button、move、wheelだけを抑制し、通常click、drag、wheel、未知buttonを壊さない。
- release、cancel、kill switch、runtime stop、sleep、対象デバイス切断、権限喪失、event投稿失敗のすべてでsessionを一度だけterminalへ収束させる。
- 物理contractに基づくmomentumを生成する場合は入力sessionのfinger count、順序、導出元sampleを継承し、終了後に通常mouse状態へ戻る。
- 自分が生成したeventの再取得、部分投稿後の別session化、source / contractにないtimestamp関係、sampleごとの投稿時刻上書き、stuck gestureを防止する。
- 未知OS build、未登録contract、fixture不一致、権限不足、対象デバイス不一致では、入力抑制を始める前にfail closedする。
- `Control + Option + Command + G`の一方向kill switchで、進行中sessionをterminalへ収束させてruntimeを停止できる。

## GUIと設定

- Dockに表示される通常GUIアプリとして起動し、設定ウィンドウとメニューバー状態を持つ。
- GUIにはbutton 3 = 2本指、button 4 = 3本指、button 5 = 4本指の固定対応を明示する。
- buttonごとの無効化または結果別mode selectorを持たない。
- applicationごとの有効・無効、感度、割り当て、方向別binding、OS機能別actionを持たない。
- 単位変換contractはfixtureとOS buildで固定し、ユーザーが感度、加速度、dead zone、momentum係数として変更できない。設定可能にするのは対象デバイス条件、証跡出力、安全停止など入力の意味を変えない運用項目に限る。
- 常駐状態、実行主体、Accessibility、Input Monitoring、対象デバイス、OS build、確定contract、未確定contract、fail-closed理由をGUIと`doctor --json`で確認できる。
- 旧mode、旧action、旧button assignmentを含む設定は、固定buttonとfinger countの正本へ原子的に移行する。移行失敗時は元ファイルを保持し、runtimeを開始しない。

## 不要・禁止する機能

- applicationごとの有効・無効、感度、割り当て
- buttonごとの結果別modeまたはaction selector
- 方向別binding、優勢軸lock、直交成分の破棄
- Space、Mission Control、ページ移動、Zoomなどを直接選ぶrouting
- keyboard shortcut、AX scrollbar、対象PID投稿による製品fallback
- 結果別のprogress、velocity、scale係数
- 感度、加速度、dead zone、threshold、momentum係数によるsource event量の変更
- 第三者project由来のコード、定数、状態遷移、係数、調整値の取り込み

button未押下時に通常mouseとして振る舞うことと、button 3 / 4 / 5が指本数だけを決めることが、application別制御を不要にする。

## 検証要件

### 同一schemaによる記録

純正trackpad、Nape Proの元mouse入力、Nape Gestureの生成eventを同じversioned schemaで記録する。最低限、次を保存する。

- source deviceとevent source
- button状態とfinger count
- X/Y量、符号、単位、反転
- event type、subtype、phase、momentum phase
- timestamp、capture order、session ID、terminal理由
- OS version / build、contract ID、fixture ID、SHA-256
- 抑制判断と生成eventとの対応

### 低レベルcontract判定

- 入力sampleと生成sampleを対応付け、X/Y量、符号、順序、sample間隔、velocity、phase、finger count、terminalの差を数値化する。
- 単位変換前後の期待値と許容誤差をfixtureで固定する。
- button 3 / 4 / 5で同一入力列を与え、finger count以外の変換原則が一致することを検証する。
- 方向反転、軸変更、低速、高速、微小入力、長時間、move/wheel混在、release競合、kill switch、sleep、抜き差し、権限喪失を検証する。
- 通常mouse passthrough、抑制漏れ、過剰抑制、feedback loop、terminal重複がないことを検証する。

### OS / application受入

Finder、Safari、Web content、nested target、Space切替、Mission Control、App Expose、拡縮対応applicationをscenarioとして確認する。ただし、次を分けて判定する。

1. 期待finger count、event量、phase、timestamp、terminalを持つ低レベル入力を生成できたか。
2. macOSまたはapplicationで何が起きたか。
3. 純正trackpadとNape Proで体感差があるか。

画面が動いたことだけを低レベルcontract一致の証明にせず、低レベルcontractが一致したことだけをOS/App結果の証明にしない。

### 人間作業

Nape Proと純正trackpadの物理操作、本人しか通せない認証など、computer-useでも代替できない作業だけを`need:human`にする。人間に依頼する前に、runner、ready同期、出力先、manifest、privacy guardを自動検証し、必要な操作だけを短時間で収録する。

## 品質・性能要件

- 常駐時と変換時のCPU、memory、event tap latency、tap-to-post latency、drop率を計測する。
- pure logic benchmarkと実機runtime計測を分離し、p50、p95、p99、最大値、sample数を保存する。
- 2本指、3本指、4本指で性能基準を満たし、入力速度やsession長で無制限にqueueが増えない。
- 通常click、drag、wheel、button 3 / 4 / 5以外のside buttonを壊さない。
- sleep復帰、デバイス抜き差し、runtime再起動、権限変更後に安全に復旧する。
- compatibility adapterをOS依存境界へ隔離し、未知条件ではfail closedする。
- 設定、event builder、session、suppression、recovery、migration、doctorに自動テストを用意する。

## 由来とライセンス

- 実装contractとパラメータはApple公式資料、Apple OSS、自前ログから再導出する。
- 実装と製品surfaceに置く外部固有名は、実装上必要な実依存の識別子と法定通知に限定する。
- event contractと単位変換はApple公式資料、Apple OSS、このリポジトリで取得した純正trackpad / Nape Proログから再導出する。
- 採用したfield、状態遷移、係数、許容誤差を、資料または自前fixtureまで追跡可能にする。
- 物理captureの公開fixtureにはkey input、個人情報、不要な周辺eventを含めない。
- 外部依存を追加する場合はlicenseと法定noticeを記録する。

## 現在位置

現行実装には、buttonごとの結果別mode、modeからevent familyを選ぶrouting、優勢軸固定、結果別正規化が残っている。この状態は本要件に適合せず、試用可能な完成形とは判定しない。

本要件へ適合させるため、Issue #148で設定、GUI、recognizer、session coordinator、event builder、migration、doctor、fixture、テストを一貫して修正する。既存のfamily別builderや過去の証跡は、低レベルcontractの解析資産として利用できる場合に限って残し、製品modeの根拠にはしない。

## 完成判定

次をすべて満たしたときだけ完成とする。

- signed appを日常利用でき、button 3 / 4 / 5が常に2 / 3 / 4本指trackpad入力として動く。
- button未押下時と対象外buttonの通常mouse入力が改変されない。
- 同じ入力列に対し、finger count以外の変換原則が共通で、結果別routingや係数が存在しない。
- 純正trackpad、Nape Pro、生成eventの量、符号、順序、時刻、phase、terminalの差を再現可能な証跡で説明できる。
- OS/App結果と低レベルcontractが別々に受入済みである。
- suppression、kill switch、sleep、抜き差し、権限変更、未知OS fail-closed、migration、性能が検証済みである。
- README、ADR、Issue、completion checklist、release手順、設定UI、runtime、テスト、CI、署名、公証が同じ製品モデルを正本としている。
