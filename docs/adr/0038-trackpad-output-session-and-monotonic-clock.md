# ADR-0038: finger count付きtrackpad入力sessionとmonotonic clockを共通化する

- 状態: 採択
- 日付: 2026-07-12

## 背景

[ADR-0049](0049-fixed-button-to-finger-count-trackpad-input.md)をNape Gestureの唯一の製品モデル正本とする。button 3 / 4 / 5は2 / 3 / 4本指trackpad入力へ固定され、button pressからreleaseまたはcancelまで、mouse入力のevent量を一つの連続sessionとして扱う。

session管理を低レベルevent familyごとに分けると、同じ入力列でもlifecycle、timestamp、terminal、失敗時cancellationが分岐し、event量の欠落、二重terminal、stuckを生む。event familyは内部contract語彙に限定し、finger count付き入力sampleを共通sessionの正本とする必要がある。

## 決定

### session identityと入力sample

- button 3 / 4 / 5のpressでsessionを開始し、対応するreleaseまたはcancelまでfinger countを2 / 3 / 4のいずれかへ固定する。
- session中の追加button、軸変更、方向反転、move / wheel到着、内部event familyの選択でfinger countまたはsession IDを切り替えない。曖昧なbutton組み合わせは新しいsessionへ分岐させず安全に拒否する。
- sessionは一意なID、0始まりで欠落のないcapture order、finger count、source kind、X / Y量、符号、timestamp、terminal stateを持つ。
- 入力sampleは順序とevent量を保持する。低レベルadapterが内部fieldへ変換しても、結果別progress、velocity、scaleをsessionの製品意味にしない。

### monotonic clock

- source event timestampは取得値と時刻domainをlosslessに保持し、wall clock、投稿時刻、別uptime helperでsampleごとに上書きしない。
- sourceと生成eventが同じmacOS起動後時刻domainを使う場合はsource timestampをそのまま使う。rebaseが不可避な場合はsession開始時に1つのoffsetを確定し、全sampleへ同じoffsetを適用して差分と間隔を保持する。
- companion eventなど物理contractがsource sampleと異なるtimestamp関係を要求する場合は、登録fixtureの関係を再現し、source timestamp、生成timestamp、導出規則をprovenanceへ記録する。
- `monotonic`は起動後time domainを表し、record間の数値非減少を意味しない。配送順はcapture orderを正本とし、timestampでsortしない。
- 負値、非有限値、現在boot外timestamp、sampleごとの投稿時刻置換、sourceまたは物理contractにないtimestamp関係を拒否する。詳細は[ADR-0040](0040-capture-order-and-event-timestamp.md)を正とする。

### lifecycleとterminal

- 入力lifecycleは`began / changed / ended / cancelled`、物理contract上必要なmomentumは`began / continued / ended`として表現する。
- release、cancel、kill switch、runtime stop、sleep、device切断、権限喪失、event作成失敗、投稿失敗のどこからでも、一度だけterminalへ収束させる。
- momentumへ移行する場合は入力sessionのID、finger count、順序を継承する。入力終了後にだけ開始し、momentum終了後は通常mouse状態へ戻る。
- active sessionのcancellationに必要なfinger count、最終X / Y量、符号、timestamp、phaseを失わない。terminal生成と投稿が失敗した場合はsessionを破棄せず、同じterminalの再試行だけを許可する。
- session ID違い、finger count違い、capture order欠落、現在boot外timestamp、非有限値、説明できないtimestamp変換、不正phase、二重terminalを拒否する。拒否したsampleでaccepted stateを変更しない。
- Codable decodeや過去logの読込成功だけをlive capabilityにしない。live sessionへ受理する時点で、現在boot、順序、finger count、terminalを再検証する。
- 低レベルevent familyはadapter内部のcontract識別として記録できるが、製品sessionの開始条件、button割り当て、結果routing、supported判定を決めない。

### 抑制と復帰

- 対象device、権限、OS build、fixture、contract、adapterを検証し、session全体を安全に生成・終了できると確定してから元入力を抑制する。
- 抑制対象はactive sessionのbutton、move、wheelに限定する。button未押下時、対象外button、対象外deviceは通常mouse入力として通過させる。
- daemon再起動や遅延callbackでは起動generationを照合し、古いsessionのterminalが新しいsessionを停止または完了させないようにする。

## 検証

- 同一入力fixtureを2 / 3 / 4本指sessionとして実行し、finger count以外のevent量、順序、timestamp原則、terminal規則が共通であることを検査する。
- 方向反転、軸変更、move / wheel混在、追加button、release競合、kill switch、sleep、device切断、権限喪失、投稿失敗をfailure injectionで検査する。
- capture order欠落、sampleごとの投稿時刻置換、timestamp差分改変、非有限値、現在boot外timestamp、finger count変更、二重terminalを拒否し、accepted stateが不変であることを検査する。
- terminal失敗後の再試行、momentum継承、通常mouse復帰、古いgenerationのcallback無効化を検査する。

## 影響

- recognizer、coordinator、compatibility adapter、System Behavior Testは、結果別family commandではなくfinger count付き共通session commandを受け渡す。
- performance logとruntime evidenceは入力finger countと内部contract識別を分け、OS / App結果をsession familyから推測しない。
- family別state machineを製品経路に増やさず、すべての安全停止を同じterminal規則へ収束させる。

## 関連

- [ADR-0049: buttonを指本数へ固定しイベント量をtrackpad入力へ置換する](0049-fixed-button-to-finger-count-trackpad-input.md)
- [ADR-0036: trackpad driver上位入力を安全に再現する](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0037: 製品gesture出力と診断event出力を分離する](0037-separate-product-and-diagnostic-event-output.md)
- [ADR-0040: capture順とevent timestampを分離する](0040-capture-order-and-event-timestamp.md)
- [ゴール要件](../requirements.md)
- [完成判定チェックリスト](../completion-checklist.md)
