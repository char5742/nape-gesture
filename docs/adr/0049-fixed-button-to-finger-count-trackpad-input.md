# ADR-0049: buttonを指本数へ固定しイベント量をtrackpad入力へ置換する

- 状態: 採択
- 日付: 2026-07-12

## 背景

従来は、button 3 / 4 / 5へ画面結果を想定したmodeを割り当て、modeから低レベルevent familyを選ぶ設計を採っていた。

この設計は製品の責務を誤っていた。ユーザーが求める変換は結果別modeの選択ではなく、通常mouseが持つ連続イベント量をtrackpad入力へ置換し、押したbuttonによって指本数だけを2、3、4へ変えることである。scroll、ページ移動、Space切替、Mission Control、App Expose、Zoomなどは、生成入力を受けたmacOSまたは前面applicationが解釈する結果であり、製品がroutingするactionではない。

結果別modeは、同じ入力に異なる正規化、優勢軸固定、family別係数、到達性の分岐を持ち込み、event量の欠落と複雑なfailure modeを生んだ。また、低レベルevent familyの存在と、製品runtimeからの到達性と、OS/App結果の成立を混同させた。

## 決定

### 1. buttonはfinger countだけを決める

固定対応を次のとおりとする。

- button 3押下中: 2本指trackpad入力
- button 4押下中: 3本指trackpad入力
- button 5押下中: 4本指trackpad入力
- 上記button未押下または対象外button: 通常mouse入力

この対応は設定で変更しない。buttonごとの無効化または結果別mode selector、方向別action、application別assignmentを廃止する。

### 2. 変換は一つの連続入力contractを使う

mouse入力sampleを、少なくともX/Y量、符号、source kind、timestamp、capture orderからなる連続列として扱う。生成sampleでは、物理的な単位差を補正したX/Y量、順序、時間間隔、方向反転を保持し、buttonから決まるfinger countを付与する。

buttonごとに別の結果変換器を選ばない。同一の入力列をbutton 3 / 4 / 5で与えた場合、生成列はfinger count以外について同じ変換原則に従わなければならない。

mouse単位とtrackpad単位が異なる場合は、自前の純正trackpad / Nape Pro計測から導出した単一のversioned単位変換contractだけを使う。軸ごとの物理単位差とOS build差はcontractへ記録できるが、結果別のprogress、velocity、scale係数を持たない。

次を製品経路から除外する。

- 開始時の優勢軸へsessionを固定する処理
- 直交成分を捨てる処理
- Space切替やページ移動などの結果を成立させるための正規化
- input kind、方向、applicationによるevent family routing
- keyboard shortcut、AX、対象PID投稿によるfallback

### 3. event familyは内部contract語彙に限定する

`scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`などは、純正trackpadと生成eventを比較する低レベルfamilyまたはcompatibility contractの名称として保持できる。ただし、次には使わない。

- ユーザー向けmode
- buttonの割り当て先
- 製品機能の一覧
- OS/App結果の保証名
- familyごとに独立した感度または係数

compatibility adapterがmacOSへ投稿する具体的event typeを選ぶ必要がある場合も、その選択はfinger count付き連続入力contractを再現する内部実装であり、ユーザーの結果選択ではない。familyごとのbuilderが残るだけでは完成または到達性の証明にならない。

### 4. OS / application結果を別に判定する

縦横scroll、nested target、ページ戻る・進む、Space切替、Mission Control、App Expose、拡縮は受入scenarioとして記録する。各scenarioでは次を別々に判定する。

1. 入力event量、finger count、phase、timestamp、terminalが期待contractに一致したか。
2. macOSまたはapplicationでどの結果が起きたか。
3. 純正trackpadとNape Proで体感差があるか。

画面結果を成立させるために製品runtimeへ個別routingを追加しない。OS設定またはapplicationにより結果が異なる場合は、その前提をscenario証跡へ記録する。

### 5. session中のfinger countを固定する

button pressから対応releaseまたはcancelまでを一つのtrackpad入力sessionとし、finger countを固定する。session中の追加button、軸変更、方向反転、move / wheel到着でfinger count、family、session IDを切り替えない。

release、cancel、kill switch、runtime stop、sleep、デバイス切断、権限喪失、投稿失敗では、一度だけterminalを生成する。momentumが物理contract上必要な場合は元sessionのfinger countをmetadataとして継承し、終了後に通常mouse状態へ戻る。

### 6. 抑制より先に生成可能性を確定する

対象デバイス、権限、OS build、fixture、contract、adapterを検証し、対応するtrackpad入力を安全に生成できると確定してから元入力を抑制する。fail-closed条件では元入力を飲み込まずruntimeを開始しない。

変換対象sessionのbutton、move、wheelだけを抑制し、button未押下時、対象外button、対象外デバイスのclick、drag、wheelを通過させる。生成eventのfeedback loopとrelease漏れを防ぐ。

### 7. GUIと設定を固定モデルへ移行する

GUIはbutton 3 = 2本指、button 4 = 3本指、button 5 = 4本指を読み取り専用の製品仕様として表示する。結果別mode selectorとapplication別設定を置かない。

設定可能な値は、自前計測により必要性と単位を説明できる共通変換contract、安全条件、対象デバイス条件に限る。旧mode、旧action、旧button assignmentは、読込時に固定モデルへ原子的に移行し、canonical設定から除去する。

## 証跡と完成判定

純正trackpad、Nape Pro元入力、生成eventを同一schemaで収録し、最低限、button、finger count、X/Y量、符号、単位、phase、timestamp、capture order、session、terminal、抑制判断を比較する。

完成には次が必要である。

- button 3 / 4 / 5の同一入力fixtureで、finger countだけが2 / 3 / 4へ変わる自動テスト
- 単位変換誤差、sample間隔差、drop、並び替え、terminal重複の数値判定
- 通常mouse passthrough、抑制、kill switch、sleep、抜き差し、権限変更、未知OS fail-closedの証跡
- 低レベルcontractとOS/App結果を分離したsystem-wide受入
- Nape Proと純正trackpadの物理受入
- 設定migration、GUI、doctor、README、Issue、release資料の同期

現行実装に結果別mode、modeからfamilyを選ぶrouting、優勢軸固定、結果別正規化が残る間は、本ADRへ未適合であり完成扱いにしない。

## 影響

- `TrackpadGestureMode`とbuttonごとのmode設定を製品surfaceから削除する。
- recognizerはbuttonからfinger countを確定し、session commandへ明示的に渡す。
- coordinatorは結果別familyを選ばず、同一の入力sample contractをfinger count付きで出力層へ渡す。
- compatibility adapterはfinger countとevent量を再現する責務を持ち、OS/App結果を選ぶ責務を持たない。
- raw physical captureと生成logは再解析可能な計測原本として保持できる。ただし、その説明文、manifest status、analyzer出力は固定button / finger-countモデルへ更新し、旧製品modeの正当化に使わない。
- requirements、README、completion checklist、verification、release、Issue orchestrationを本ADRへ同期する。

## 廃止する設計

次の設計は現行文書、設定、runtime、テスト、証跡から削除する。

- buttonごとに結果別modeまたは変換無効を選ぶ設計
- modeからscroll、system swipe、pinchなどのfamilyへroutingする設計
- family別の試用経路を製品機能として数える設計
- scroll固有変換、優勢軸固定、progress / velocity / scale正規化を共通入力変換より上位に置く設計
- 旧設計を「置換済みADR」として残し、実装判断や完成判定から参照できる状態

[ADR-0036](0036-emulate-trackpad-driver-output-events.md)はfinger-count付きdriver上位入力、[ADR-0038](0038-trackpad-output-session-and-monotonic-clock.md)は共通session、monotonic timestamp、terminal、[ADR-0043](0043-trackpad-scroll-product-output.md)は25F80の2 / 3 / 4本指内部compatibility contractとして本ADRへ全面同期する。

## 関連

- [ゴール要件](../requirements.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証ガイド](../verification.md)
- [ADR-0036](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0038](0038-trackpad-output-session-and-monotonic-clock.md)
