# ADR-0038: 固定GestureClass sessionとmonotonic clockを共通化する

- 状態: 採択
- 日付: 2026-07-12

## 背景

button 3 / 4 / 5は異なる上位GestureClassとProductOutput adapterへ固定接続される。一方、source sampleの順序、exact timestamp、session identity、cancel、single terminalはclassにかかわらず同じ安全契約を必要とする。

class固有adapterをなくして一つのgeneric eventへ統一する必要はない。共通化するのはsource commandとsession safetyであり、低レベルevent encodingではない。

## 決定

### source commandとsession identity

- button 3 / 4 / 5のpressでsessionを開始し、releaseまたはcancelまでsource buttonとGestureClassを固定する。
- session中の追加button、軸変更、方向反転、move / wheel到着でclass、session ID、adapterを切り替えない。
- sessionは一意なID、0始まりで欠落のないcapture order、source button、GestureClass、source kind、X/Y量、符号、timestamp、terminal stateを持つ。
- accepted source sampleごとに1 commandを生成し、drop、duplicate、coalesce、reorderをしない。
- class adapterが1 commandから複数eventを生成しても、source commandとのbatch対応を保持する。
- 低レベルfamilyは固定GestureClassから決定され、applicationまたは期待画面結果から決めない。

### monotonic clock

- source event timestampは取得値とtime domainをlosslessに保持し、wall clockまたはsampleごとの投稿時刻で上書きしない。
- sourceとgenerated eventが同じ起動後time domainを使う場合はsource timestampをそのまま使う。
- rebaseが必要な場合はsession開始時に単一offsetを確定し、全sampleへ同じoffsetを適用する。
- companion eventなど物理contract固有のtimestamp関係は登録fixtureから導出し、source timestamp、generated timestamp、導出規則をprovenanceへ記録する。
- 配送順はcapture orderを正本とし、timestampでsortしない。局所的なtimestamp逆行だけで物理系列を拒否しない。
- 非有限値、現在boot外timestamp、sampleごとのrebase、説明不能なtimestamp関係を拒否する。

### lifecycleとsingle terminal

- source lifecycleを`began / changed / ended / cancelled`として扱う。
- adapterはclass contractに必要なphase、companion lifecycle、任意のmomentumを生成できる。
- release、cancel、kill switch、runtime stop、sleep、device切断、権限喪失、event作成失敗、投稿失敗のどこからでも、一度だけterminalへ収束させる。
- terminal後に同じsessionのcommandまたはeventを受理しない。
- active cancellationに必要なclass、family、最終payload、timestamp、capture orderを保持する。
- batchの一部が投稿済みなら未投稿offsetを保持し、同じsource eventまたは同じterminalの再試行だけを許可する。
- terminal投稿が失敗してもsessionを破棄せず、成功するまで同じterminalを再試行する。
- session ID違い、class違い、button違い、capture order欠落、不正phase、二重terminalを拒否し、accepted stateを変更しない。

### 抑制と復帰

- 対象device、権限、OS build、fixture、3 adapterを検証し、sessionを安全に終了できると確定してから元入力を抑制する。
- 抑制対象はactive sessionのbutton、move、wheelに限定する。
- button未押下時、対象外button、対象外deviceは通常mouse入力として通過させる。
- daemon generationをterminal callbackへ固定し、古いsessionが再起動後のruntimeへ干渉しないようにする。

## 検証

- 3 GestureClassに同じsource系列を与え、source commandの量、順序、timestamp、session規則が共通であることを確認する。
- classごとのgenerated event family、event count、field、単位が異なることを許容し、各registered contractへ照合する。
- 方向反転、軸変更、move / wheel混在、追加button、release競合、kill switch、sleep、disconnect、TCC喪失、投稿失敗を検査する。
- capture order欠落、timestamp改変、非有限値、現在boot外timestamp、class変更、二重terminalを拒否する。
- partial batchとterminal失敗後の再試行、通常mouse復帰、古いgeneration無効化を検査する。

## 影響

- recognizerとcoordinatorは`FixedGestureInputCommand`を共通境界にする。
- fixed coordinatorはGestureClassから既存ProductOutput adapterを一意に選ぶ。
- adapter固有state machineは低レベルcontractを構成し、共通session machineはsource identityとsingle terminalを保証する。
- performance logはGestureClass、内部family、source command、generated batchを分けて記録する。

## 関連

- [ADR-0049: buttonを固定GestureClassへ接続する](0049-fixed-button-to-gesture-class-input.md)
- [ADR-0036: trackpad driver上位eventを安全に再現する](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0037: 製品gesture出力と診断event出力を分離する](0037-separate-product-and-diagnostic-event-output.md)
- [ADR-0040: capture順とevent timestampを独立して保持する](0040-capture-order-and-event-timestamp.md)
- [完成判定チェックリスト](../completion-checklist.md)
