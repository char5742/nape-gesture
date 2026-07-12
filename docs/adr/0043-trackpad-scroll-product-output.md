# ADR-0043: 25F80のfinger count付きtrackpad入力compatibility contractを構成する

- 状態: 採択
- 日付: 2026-07-12

## 背景

[ADR-0049](0049-fixed-button-to-finger-count-trackpad-input.md)をNape Gestureの唯一の製品モデル正本とする。25F80で必要なのは、button 3 / 4 / 5から固定した2 / 3 / 4本指情報と、通常mouseの連続event量を、同じ入力変換原則でtrackpad driver上位入力へ再現するcompatibility contractである。

既存の低レベルcaptureには`scroll`などのevent family別sample、pair、係数、candidate builderが含まれる。しかし、それらは物理trackpadを解析する資産であり、familyをbuttonの割り当て先、独立製品機能、supported capability、OS / App結果として公開する根拠にはならない。scroll固有変換を共通入力変換より上位の製品経路にしてはならない。

本ADRは25F80の内部compatibility境界、identity検証、単位変換、system-wide投稿、provenanceを定める。buttonとfinger count、製品surface、OS / App結果の意味はADR-0049だけを正とする。

## 決定

### contract identityとfail closed

- 25F80 contractはfixture ID、SHA-256、schema、contract ID、OS version / build、fixture実体、単位変換model identityを持つversioned contractとして登録する。
- `supported`は、登録したidentityと実際に読み込んだbytesがすべて一致し、2 / 3 / 4本指入力の生成前提を満たす場合だけ生成する。文字列ID、builderの存在、過去のfamily別試用成功だけでは生成しない。
- 明示pathが設定された場合はそのpathだけを検証し、空、読取不能、不正bytes、identity不一致からbundle resourceやrepository fixtureへ黙ってfallbackしない。
- 未知OS build、未登録fixture、hash不一致、schema不一致、contract不一致、単位変換未確定では、event tapと入力抑制を開始しない。

### finger count付き共通入力変換

- 入力sampleはX / Y量、符号、source kind、timestamp、capture order、sample間隔、方向反転を保持し、buttonから固定したfinger countを付与する。
- button 3 / 4 / 5へ同じ入力列を与えた場合、生成列はfinger count以外について同じ変換原則に従う。button、方向、input kind、application、期待する画面結果で変換器を切り替えない。
- mouse単位からtrackpad単位への変換は、純正trackpad / Nape Proの自前計測から導出した単一のversioned contractにする。軸ごとの物理単位差とOS build差は記録できるが、event family別、結果別のprogress、velocity、scale係数を持たない。
- 有効なsource sampleをthreshold、dead zone、acceleration、感度、clampで変更または破棄せず、複数sampleをcoalesceしない。物理contract上のphase、companion event、momentumはsource sampleとの対応を保持した内部encodingとしてだけ生成し、ユーザー調整値にしない。
- 既存のscroll pair、odd quadratic係数、family別candidate builderは解析資産として保持できるが、現行の共通入力変換contract、supported判定、完成証跡へそのまま流用しない。

### 内部event contractとsystem-wide投稿

- `scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`などはfixture分類とadapter内部の低レベルcontract名に限定する。ユーザー向けmode、button割り当て、製品機能一覧、OS / App結果名には使わない。
- adapterが具体的なevent type、field、phase、companionを選ぶ場合、finger countとevent量を再現する25F80内部実装として選ぶ。familyを結果routingの入力にしない。
- session ID、finger count、capture order、monotonic timestamp、terminalは[ADR-0038](0038-trackpad-output-session-and-monotonic-clock.md)の共通sessionで検証する。
- 一つの入力sampleから複数eventを生成する場合は、batch全件を構築・検証してから投稿する。一部を作れないbatchを投稿せず、部分投稿後は未投稿offsetと順序を保持してterminalへ収束させる。
- eventはsystem-wideへだけ投稿し、対象PID、AX element、application別配送、keyboard shortcutを選ばない。
- adapterは投稿前のraw配送先fieldが未指定であることを検査する。投稿後captureでWindowServerが配送先を付与しても、それだけを対象PID投稿の証拠または失敗理由にしない。
- 投稿成功直後にdirect post traceへsession、finger count、capture order、timestamp、event type、内部contract、system-wide配送、run identity、binary identityを記録する。capture、manifest、traceのSHA-256とidentityを照合してprovenanceを確定する。
- 生成marker、source boundary guard、provenanceによりfeedback loop、対象PID、AX、shortcut、診断出力の混入を拒否する。

### 低レベルcontractとOS / App結果の分離

- 低レベル完成判定では、finger count、X / Y量、符号、単位、sample間隔、phase、timestamp、capture order、terminalを純正trackpad contractと比較する。
- 縦横scroll、nested target、ページ戻る・進む、Space切替、Mission Control、App Expose、拡縮は別のsystem-wide受入scenarioとして記録する。
- OS / App結果を成立させるため、結果別係数、優勢軸固定、直交成分破棄、family routing、fallbackを追加しない。
- 25F80対応は、2 / 3 / 4本指の低レベルcontract、通常mouse passthrough、抑制、terminal、OS / App受入、Nape Pro物理受入が揃うまで完成または試用可能と表現しない。

## 検証

- 同一入力fixtureをbutton 3 / 4 / 5へ与え、finger countだけが2 / 3 / 4へ変わることを機械判定する。
- X / Y量、符号、単位変換誤差、sample間隔、drop、並び替え、phase、terminalを純正trackpad fixtureと比較する。
- contract、model、fixture、OS identityの各要素を個別に改変し、抑制開始前にfail closedすることを検査する。
- batch作成失敗、部分投稿、terminal再試行、direct post trace、capture provenance、raw配送先fieldの投稿前後の境界を検査する。
- 低レベルcontract判定とOS / App結果scenarioを別々のartifactへ保存する。

## 影響

- 25F80にscrollだけの独立product capabilityを持たせない。finger count付き共通入力contractを生成できるかでruntime readinessを判定する。
- family別builderと過去fixtureは内部解析資産に降格し、GUI、doctor、README、release資料で製品機能として列挙しない。
- compatibility adapterの入力は結果別actionではなく、連続input sample、finger count、session metadataとする。
- 25F80 contractが不完全な間は元入力を抑制せず、通常mouseとして安全に振る舞う。

## 関連

- [ADR-0049: buttonを指本数へ固定しイベント量をtrackpad入力へ置換する](0049-fixed-button-to-finger-count-trackpad-input.md)
- [ADR-0036: trackpad driver上位入力を安全に再現する](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0038: finger count付きtrackpad入力sessionとmonotonic clockを共通化する](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0039: trackpad eventログを厳格解析しcapture manifestへ固定する](0039-strict-trackpad-event-analysis-and-capture-manifest.md)
- [ADR-0040: capture順とevent timestampを分離する](0040-capture-order-and-event-timestamp.md)
- [ADR-0042: 25F80 scroll / momentum契約を独立fixtureで比較する](0042-versioned-scroll-momentum-contract-comparison.md)
- [ゴール要件](../requirements.md)
- [検証ガイド](../verification.md)
