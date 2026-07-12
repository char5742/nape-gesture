# ADR-0036: trackpad driver上位入力を安全に再現する

- 状態: 採択
- 日付: 2026-07-12

## 背景

[ADR-0049](0049-fixed-button-to-finger-count-trackpad-input.md)をNape Gestureの唯一の製品モデル正本とする。製品はbutton 3 / 4 / 5をそれぞれ2 / 3 / 4本指trackpad入力へ固定し、通常mouseが持つ連続event量を保持してmacOSへ渡す。button未押下時と対象外buttonは通常mouse入力として通過させる。

縦横scroll、ページ移動、Space切替、Mission Control、App Expose、拡縮は、生成入力を受けたmacOSまたは前面applicationが解釈する結果である。Nape Gestureが結果を選ぶactionや、buttonから低レベルevent familyを選ぶ製品経路は持たない。

一方、通常SDKに公開されていないtrackpad event contractをsystem-wideへ安全に投稿するには、OS build別のcompatibility adapter、由来追跡、投稿前検査、fail closedが必要である。本ADRはADR-0049の製品モデルを変更せず、その生成・投稿境界だけを定める。

## 決定

### 製品入力境界

- button 3押下中は2本指、button 4押下中は3本指、button 5押下中は4本指のtrackpad入力を生成する。この対応は固定であり、設定、方向、input kind、application、OS / App結果では変更しない。
- mouse入力sampleのX / Y量、符号、source kind、timestamp、capture order、sample間隔、方向反転を連続列として保持する。button間で変えてよい意味情報はfinger countだけとする。
- mouse単位とtrackpad単位の差は、自前の純正trackpad / Nape Pro計測から導出した単一のversioned単位変換contractで補正する。結果別、family別、application別の係数を持たない。
- 変換対象button未押下時、対象外button、対象外deviceのclick、drag、move、wheelは抑制せず通常入力として通過させる。

### compatibility adapterと投稿境界

- 製品出力はfinger count付き連続入力contractを再現するtrackpad driver上位eventとして、system-wide event streamだけへ投稿する。対象PID、frontmost application、AX elementを配送判断に使わない。
- keyboard shortcut、AX操作、対象PID投稿、application別分岐、診断eventを製品fallbackにしない。DriverKit virtual trackpad、digitizer contact、System Extensionも前提にしない。
- `scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`などのevent family名は、物理trackpadとの比較、fixture分類、compatibility adapter内部のcontract識別にだけ使う。ユーザー向けmode、button割り当て、製品機能、supported capability、OS / App結果名には使わない。
- adapterが具体的なevent type、subtype、field、phase、順序を選ぶ場合、その選択はfinger countとevent量を再現するOS依存実装であり、結果routingではない。
- event contract、field、定数、状態遷移、単位変換、許容誤差はApple公式資料、Apple OSS、このリポジトリの純正trackpad / Nape Proログから再導出し、資料またはfixtureまで追跡可能にする。第三者project由来の実装値を取り込まない。
- 通常SDK非公開のfieldやbridgeは最小のcompatibility adapterへ隔離する。fixture ID、SHA-256、schema、contract ID、OS version / build、fixture実体が登録内容と完全一致した場合だけ生成可能と判定する。
- 未知OS build、未登録fixture、hash不一致、contract不一致、adapter不備、権限不足では、元入力を抑制せずruntimeを開始しない。推測値や別経路へfallbackしない。
- 生成eventにはfeedback loopを防ぐmarkerを付け、投稿前検査、direct post trace、captureとのprovenance照合を行う。[ADR-0037](0037-separate-product-and-diagnostic-event-output.md)に従い、製品adapterと診断出力をmodule境界で分離する。
- timestampとcapture順の解釈は[ADR-0040](0040-capture-order-and-event-timestamp.md)、sessionとterminalは[ADR-0038](0038-trackpad-output-session-and-monotonic-clock.md)を正とする。

### OS / App結果と証跡

- 縦横scroll、nested target、ページ戻る・進む、Space切替、Mission Control、App Expose、拡縮はsystem-wide受入scenarioとして記録するが、製品が直接選択または保証する結果にはしない。
- 証跡は、入力event量とfinger countを再現した低レベルcontract、macOSまたはapplicationで起きた結果、純正trackpadとNape Proの体感差を分けて保存する。
- 画面が動いたことだけで低レベルcontract一致を証明せず、低レベルcontract一致だけでOS / App結果を証明しない。

## 検証

- 同一mouse入力fixtureをbutton 3 / 4 / 5へ与え、生成列のfinger countだけが2 / 3 / 4へ変わることを検査する。
- X / Y量、符号、順序、sample間隔、方向反転、phase、terminal、単位変換誤差を純正trackpad contractと比較する。
- 未知OS build、fixture改変、hash不一致、明示path不正、event作成失敗、投稿失敗で、抑制開始前にfail closedすることを検査する。
- boundary guard、direct post trace、capture provenanceにより、対象PID、AX、shortcut、診断出力が製品経路へ入らないことを検査する。
- OS / App結果scenarioを低レベルcontract判定と別々に保存する。

## 影響

- 設定、GUI、doctor、runtime schemaはevent familyやOS / App結果をbutton割り当てとして公開せず、ADR-0049の固定finger-countモデルを表示する。
- family別builderと過去fixtureは内部解析資産としてのみ残せる。存在するだけでは製品到達性、supported、完成の根拠にならない。
- compatibility adapterを安全に構成できない環境では、通常mouse入力を壊さず停止する。

## 関連

- [ADR-0049: buttonを指本数へ固定しイベント量をtrackpad入力へ置換する](0049-fixed-button-to-finger-count-trackpad-input.md)
- [ADR-0037: 製品gesture出力と診断event出力を分離する](0037-separate-product-and-diagnostic-event-output.md)
- [ADR-0038: finger count付きtrackpad入力sessionとmonotonic clockを共通化する](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0043: 25F80のfinger count付きtrackpad入力compatibility contractを構成する](0043-trackpad-scroll-product-output.md)
- [ゴール要件](../requirements.md)
- [検証ガイド](../verification.md)
