# ADR-0040: capture順とevent timestampを独立して保持する

- 状態: 採択
- 日付: 2026-07-11
- 更新日: 2026-07-12

## 背景

macOS 26.5.1（build 25F80）の純正trackpadでは、`scrollWheel`より後に配送されるcompanion eventが、直前eventより小さいtimestampを持つ系列が観測される。timestampで配送順を再構成したり、局所的な逆行だけでrecordを拒否したりすると、物理trackpadの系列を改変する。

Nape Gestureはsource mouse sampleの取得順、exact timestamp、sample間隔を保持しつつ、GestureClass固有のbatchを構成する必要がある。capture orderと時刻値を別々の情報として扱う。

## 決定

- source eventの順序は、capture callbackで採番した0始まりかつ欠落のないcapture orderを正本とする。
- accepted source sampleごとに1 commandを生成し、capture orderをそのcommandへ引き継ぐ。
- source timestampは取得値とtime domainをlosslessに保持し、timestampでrecordをsortしない。
- sourceとgenerated eventが同じ起動後time domainならsource timestampをそのまま使う。
- rebaseが必要ならsession全体へ単一offsetを適用し、sample間隔を保持する。
- 1 commandから複数eventを生成するbatchは同じsource capture orderへ対応付け、batch内順序を別のpost indexで保持する。
- companion eventなど物理contract固有のtimestamp関係は登録fixtureから再現する。全eventへのtimestamp同値を強制しない。
- generated provenanceはsource timestamp、generated timestamp、capture order、batch post index、rebase offset、導出規則を保存する。
- analyzerはcapture orderの欠落、重複、並べ替えを拒否するが、timestampの局所逆行だけでは失敗にしない。
- manifestのfirst / last event timestampはcapture順の先頭 / 末尾recordとして保持し、数値上の大小を要求しない。
- capture開始 / 完了のwall clockは収録区間の説明にだけ使い、event timestampへ変換しない。

## 検証

- 正負、同値、局所逆行を含むtimestamp列でcapture orderと時刻値を保持する。
- 3 GestureClassのcommand境界で同じsource timestampとcapture orderを保持する。
- class固有batchのevent順とtimestamp関係をregistered fixtureへ照合する。
- sampleごとの投稿時刻置換、timestamp sort、差分clamp、現在boot外timestampを拒否する。
- manifest wall clockとevent time domainを混在させない。

## 影響

- 純正trackpadの配送順とtimestamp関係を改変せず解析できる。
- source sample、fixed command、generated batch、system-wide captureを同じrunで追跡できる。
- 順序違反とtimestamp逆行を区別し、physical contractにない改変だけを拒否できる。

## 関連

- [ADR-0038: 固定GestureClass sessionとmonotonic clockを共通化する](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0039: trackpad eventログを厳格解析しcapture manifestへ固定する](0039-strict-trackpad-event-analysis-and-capture-manifest.md)
- [ADR-0049: buttonを固定GestureClassへ接続する](0049-fixed-button-to-finger-count-trackpad-input.md)
- [検証手順](../verification.md)
