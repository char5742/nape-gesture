# 検証手順と既知の失敗条件

この文書は、button 3 / 4 / 5押下中の連続mouse event量を2 / 3 / 4本指trackpad入力へ変換する製品モデルの検証手順を定義する。
完成状態の正本は[完成判定チェックリスト](completion-checklist.md)とし、この文書は証跡の取得・比較・失敗判定を具体化する。
製品モデルの設計判断は[ADR-0049](adr/0049-fixed-button-to-finger-count-trackpad-input.md)を正とする。

## 現在の確認状態

改訂基準commit`55eb991`の実装は、buttonごとの3つのユーザーmodeと、`scroll` / `DockSwipe` / `magnification`へのroutingを保持している。2 / 3 / 4 finger count固定、全source event量の保存、button押下単位のterminal、未押下passthroughを一続きに検証する製品証跡はない。

したがって現状は**未達**である。既存の次の成果は基盤として再利用できるが、完成証跡ではない。

- trackpad event logger、strict analyzer、manifest、provenance
- 25F80で取得した一部の純正trackpad観測とscroll / momentum fixture
- product / diagnostic outputのmodule境界
- runtime identity、TCC、device診断
- 旧mode / familyを対象にしたsession test、runtime test、performance log

`supportedFamilies`、`confirmedFamilies`、`trialFamilies`の値や、旧3経路のtest成功を現在の製品完成判定に使わない。

## 検証対象

製品入力契約は次に固定する。

| activation input | expected finger count |
| --- | --- |
| button 3 | 2 |
| button 4 | 3 |
| button 5 | 4 |

button 3 / 4 / 5のいずれも押されていない時は、通常mouse eventを変更せず通す。
buttonからmode、方向別action、OS/App結果、application別設定を選ばない。
`scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`はcapture解析時の低レベル分類だけに使い、ユーザー入力契約や製品routing keyにしない。

## 証跡runの同一性

各scenarioは専用directoryへ保存し、次を同じrun UUIDで結合する。

- source mouse event log
- HID log
- generated trackpad event log
- direct post trace
- Reference Target App log
- contract analyzer report
- OS/App結果メモ
- manifest

manifestには最低限、repo SHA、binary SHA-256、macOS version / build、実行主体、TCC状態、device identity、scenario ID、button、期待finger count、開始・終了時刻、各logのSHA-256、event件数、terminal理由、fixture ID / SHA-256を保存する。
異なるrunのlogを補完し合わない。開始前から存在するsidecar、ready file、manifestを再利用しない。

## 機械検証

### 製品surface

次を静的guardとtestで確認する。

- `ruby scripts/check-product-model-documentation.rb`が成功する
- `ruby scripts/check-finger-count-product-model.rb`が成功する。基準commitでは廃止対象を検出して失敗することが正しい現在状態である
- button 3 / 4 / 5と2 / 3 / 4 finger countの対応が1か所で固定されている
- 設定schema、GUI、CLI help、doctor、performance schemaに結果別modeや方向別actionがない
- application別の有効・無効、感度、割り当てがない
- product targetがAX、対象PID、frontmost application、keyboard shortcut配送を参照しない
- diagnostic targetの旧出力をproduct targetからimportしない
- low-level family名をbutton routingや完成度のkeyに使わない
- 同一source fixtureでは、button 3 / 4 / 5が同じ正規化入力の量、順序、時間間隔を使い、結果別またはfinger count別の変換係数を使わない
- 旧設定は結果別modeへ移行せず、固定button-to-finger-count modelへ安全に廃止または正規化する

旧語をmigration入力、履歴fixture、明示的な診断toolで読む場合は、製品出力へ到達しないtestと履歴用途の注記を必須にする。

### event量保存

source event列`S`について、少なくとも`sourceKind`、`unit`、`phase`、`captureOrder`、`timestamp`、`deltaX`、`deltaY`、`sourceEventCount`を変換前に記録する。

検証は次の2段階に分ける。

1. 変換器へ渡した入力量がsource logと一致することをbit単位で確認する。
2. 生成trackpad量が、対応OS buildの純正fixtureから導出した単一versioned単位変換contractの許容差内であることを確認する。finger count固有の低レベルencoding差は同じcontract内で明示する。

合格条件:

- 受理したsource eventが欠落・重複せず、同じ順序でちょうど1回だけ寄与する
- 複数source sampleをcoalesceせず、各sampleを個別に対応付けられる
- X / Y、正負、斜め、停止、方向反転を保持する
- terminal用zero frameや補助eventをsource event量へ加算しない
- queue drop、整数飽和、非有限値、現在boot外timestamp、source / contractにないtimestamp変換を成功扱いにしない
- 単位変換以外の感度、加速度、dead zone、threshold、clampでsource event量を変えていない
- event familyごとに別の意味へevent量を読み替えない

最終delta合計だけの一致では不十分である。途中で正負が相殺される列でも、各source eventの寄与と順序を検証する。

### finger count

各sessionについて次を確認する。

- button 3は全frameで2本指
- button 4は全frameで3本指
- button 5は全frameで4本指
- finger countはbutton down時に確定し、terminalまで変化しない
- 方向、速度、App、OS/App結果、低レベルfamilyによって変化しない
- 進行中sessionへ別activation buttonが追加されてもfinger count、family、session IDを切り替えない
- session開始時に複数activation buttonが曖昧に競合する場合やunknown buttonではfinger countを推測しない
- output contractがfinger countを表現・検証できない場合はunsupportedとしてfail closedにする

event typeやclassifierだけからfinger countを推測した結果は合格にしない。純正captureでfinger countと低レベルfieldの対応を固定し、generated captureで同じ表現を検証する。

### session terminal

button downから対応するbutton upまでを1つのinput sessionとする。source eventを1件も受理しなかった場合を含め、開始したsessionは必ず次のいずれか1つでterminalになる。

- 正常終了
- cancel
- kill switch
- runtime stop
- sleep
- device切断
- TCC喪失
- output作成または投稿失敗
- contract不一致

合格条件:

- session IDが一意で、順序が0から欠落なく増える
- source timestamp、sample間隔、登録contractのcompanion timestamp関係を保持し、capture orderで順序を判定する
- finger countがterminalまで固定される
- terminalが重複しない
- terminal後に同じsessionのeventを投稿しない
- active sessionを残したまま次のbutton sessionを開始しない
- contractが要求するcontinuationがある場合も同じsessionへ結合し、最終的にterminalへ収束する
- 部分投稿時は実投稿順とtrace順を一致させ、再送またはcancelで予約済みeventを解消する
- terminal生成自体に失敗した場合は成功扱いにせず、出力停止と物理解放待ちを構造化して報告する

### passthrough

button 3 / 4 / 5未押下時に、対象deviceと対象外deviceの両方で次を確認する。

- mouse move
- click / double-click
- drag
- wheel
- button 1 / 2および対象外button

合格条件は、元event objectまたは同値field列がそのまま下流へ届き、生成event 0件、抑制0件、変更0件になることである。
activation session中に消費するsource eventと、未押下時に通すeventを同じ「漏れなし」countへまとめない。

次の境界も別scenarioで検証する。

- app起動直後
- 各buttonの正常解放直後
- kill switch直後
- output failure直後
- sleep復帰直後
- device再接続直後
- TCC復旧直後

active sessionが異常終了した時は、activation buttonの物理解放前に途中のdown/upを通常clickとして漏らさず、解放を確認した後に通常passthroughへ戻る。

### fail closed

次の条件では、event tapによる新規抑制と製品event生成を開始しない。

- 未対応macOS version / build
- symbolまたはprivate contract不在
- fixture ID、SHA-256、schema、contract ID、OS build、実体bytesの不一致
- 明示したcontract pathが空、読取不能、空file、不正bytes
- finger countを検証できないcontract
- 対象device不一致または複数候補で一意に決まらない
- Input MonitoringまたはAccessibility不足
- timestamp、session、event量の不整合
- source / generated / trace / manifestのprovenance不一致

active session中に失敗した場合は、利用可能なcontractで明示cancel terminalを投稿して停止する。cancelを安全に生成できない場合は追加のtrackpad eventを投稿せず、activation inputの物理解放まで誤clickを抑え、解放後にpassthroughへ戻す。

次をfallbackにしない。

- AX scrollbar
- 対象PIDへの明示投稿
- frontmost application別分岐
- keyboard shortcut
- 別の低レベルevent family
- 旧単純scroll

## 実機検証

### 純正trackpad fixture

対応対象の各macOS buildで、純正trackpadから次のscenarioを収録する。

| scenario | 必須系列 |
| --- | --- |
| 2本指 | 正負X、正負Y、斜め、停止、方向反転、正常terminal、cancel |
| 3本指 | 正負X、正負Y、斜め、停止、方向反転、正常terminal、cancel |
| 4本指 | 正負X、正負Y、斜め、停止、方向反転、正常terminal、cancel |

各captureには操作marker、finger count、scenario ID、ready tokenを付ける。loggerがreadyになる前の操作、deadline後の操作、0 event、dropあり、manifest不成立のcaptureは採用しない。
公開fixtureには不要なdevice identifier、keycode、pointer座標、未採用prefixを残さず、公開したbytesと登録SHA-256を一致させる。

### Nape Pro変換

同じOS buildとbinaryで次を収録する。

| scenario | 入力 | 期待値 |
| --- | --- | --- |
| button 3 | 押下中に純正2本指fixtureと対応する連続量を入力 | 全frame 2本指、量保存、terminal |
| button 4 | 押下中に純正3本指fixtureと対応する連続量を入力 | 全frame 3本指、量保存、terminal |
| button 5 | 押下中に純正4本指fixtureと対応する連続量を入力 | 全frame 4本指、量保存、terminal |
| 未押下 | move、click、drag、wheel | passthrough、生成0件 |

source mouse log、HID log、generated trackpad log、post traceを同時収録し、同じrun UUIDで結ぶ。画面結果が期待どおりでも、source-to-output量、finger count、terminal、provenanceのいずれかが不一致なら不合格とする。

### 異常終了

少なくとも次を実利用する`.app`で取得する。

- kill switch
- runtime stop
- sleep / wake
- Nape Pro切断 / 再接続
- TCC喪失 / 復旧
- unsupported contract

各scenarioでterminal 1件、terminal後の生成0件、物理解放後のpassthrough、stuck session 0件を確認する。

## 低レベルcontractとOS/App結果

### 低レベルcontract

低レベル判定はfinger countごとに行い、次を比較する。

- event type、subtype、raw field、serialized data
- finger count表現
- phase、terminal、補助event
- event量とmodel入力
- timestamp、順序、session ID
- system-wide post trace
- fixture / binary provenance

`scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`は解析reportの観測ラベルとして使用できる。これらの件数や成功率を、buttonごとのmode、製品capability、完成率として報告しない。

### OS/App結果

OS/App結果は別scenario、別reportで保存する。

- 前面App名とversion
- macOS version / build
- OS gesture設定
- button、finger count、入力event量、方向、速度
- 参照した低レベルcontract report
- AppKit target logまたはsystem result
- 画面観察
- session terminalとstuck有無

縦横scroll、application navigation、Space切替、Mission Control、App Exposé、Zoomなどを記録できるが、これはOS/Appの解釈結果である。
結果が異なるAppへ対応するためにapplication別設定、方向別action、AX/PID/shortcut fallbackを追加しない。

判定例:

| 低レベルcontract | OS/App結果 | 記録 |
| --- | --- | --- |
| 合格 | 成立 | 両方を独立して合格 |
| 合格 | 不成立 | contract合格、当該OS/App結果は不成立 |
| 不合格 | 成立 | contract不合格。画面結果は参考のみ |
| 不合格 | 不成立 | 両方不合格 |

## 性能検証

性能はfinger countごとに集計し、低レベルfamilyや旧modeで分割しない。

- source event受理から変換入力記録まで
- 変換入力記録から最初のtrackpad event投稿まで
- source event受理から同frame系列の投稿完了まで
- button downからterminal投稿完了まで
- passthrough eventの追加遅延
- logger queue depth、drop count
- idle、連続入力、terminal後のCPU

詳細な閾値と失敗条件は[性能測定基準](performance-baseline.md)を正とする。AppKit受信と画面反映時間は低レベル投稿時間と分離する。

## 権限とruntime identity

完成証跡は日常利用する`.app`と同じ実行主体で取得する。

~~~sh
.build/NapeGesture.app/Contents/MacOS/nape-gesture doctor --probe-hid --json --assert-runtime-ready
~~~

終了コード0だけでなく、実行ファイル、bundle path、bundle ID、TCC対象、対象device、OS build、contract fixture、fail-closed状態が証跡manifestと一致することを確認する。
standalone binaryのTCC状態を配布`.app`の証跡として代用しない。

## 既知の失敗条件

次は即時不合格とする。

- 旧mode / family testだけが成功している
- source event量を最終deltaだけで比較している
- buttonとfinger countの対応が設定や方向で変わる
- sessionがterminalなしで残る、またはterminal後に出力が続く
- 未押下passthroughをactivation sessionの「漏れなし」証跡で代用する
- dry-run、合成input、画面結果だけで実機合格にする
- family単体の生成成功を製品完成とする
- OS/App結果のためにAX、PID、shortcut、application別分岐へfallbackする
- unsupported条件でevent tapや抑制を先に開始する
- fixture ID文字列だけを見て、bytesとSHA-256を検証しない
- 異なるrun、binary、OS buildの証跡を混ぜる
- logger drop、0 event、ready期限切れ、manifest不一致を警告だけで通す
- 公証成功をevent contract互換性の証明にする

## 完成判定

次を全て満たした場合だけ完成とする。

- event量保存が2 / 3 / 4本指で機械検証・実機検証とも合格
- button 3 / 4 / 5からfinger countが固定され、全frameで一致
- 全正常・異常経路がsession terminalへ収束
- 未押下、解放後、異常終了後のpassthroughが合格
- 純正trackpadとNape Proの登録済み実機証跡が同一OS buildでそろう
- unsupported条件が誤出力なしでfail closedになる
- 低レベルcontractとOS/App結果を別reportで判定
- build、test、性能、bundle、署名、公証の必要ゲートが合格
- READMEとリリース文書が実測済み範囲を超えて完成を主張していない
