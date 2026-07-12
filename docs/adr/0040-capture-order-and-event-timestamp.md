# ADR-0040: capture順とevent timestampを独立して保持する

- 状態: 採択
- 日付: 2026-07-11
- 更新日: 2026-07-12

## 背景

macOS 26.5.1（build 25F80）の純正trackpadでは、`scrollWheel`より後に配送されるcompanion eventが、直前eventより小さいtimestampを持つ系列が観測される。配送順をtimestampで再構成したり、timestampの局所的な逆行だけでrecordを拒否したりすると、物理trackpadの系列を改変する。

Nape Gestureはsource mouse event量、配送順、timestamp間隔を保持する必要がある。capture順と時刻値を別々の情報として記録し、生成時に投稿直前時刻へ上書きしない。

## 決定

- eventの配送順は、logger callbackで採番した0始まりかつ欠落のない`captureIndex`を正本とする。
- source event timestampは取得値とtime domainをlosslessに保持し、timestampでrecordをsortしない。
- analyzerは`captureIndex`の欠落、重複、並べ替えを拒否するが、timestampの局所的な逆行だけでは失敗にしない。
- generated product provenanceもcapture orderで順序を固定し、source timestamp、生成timestamp、rebase offset、内部contractの導出規則をsampleごとに保存する。
- sourceと生成eventが同じ起動後time domainを使う場合はsource timestampをそのまま使う。rebaseが必要な場合はsession全体へ単一offsetを適用し、sample間隔と同値関係を保持する。
- companion eventなど物理contract固有のtimestamp関係は登録fixtureから再現する。sourceまたはfixtureにない局所逆行、間隔変更、sampleごとの投稿時刻置換を生成しない。
- scroll eventとcompanion eventの対応にtimestamp同値を一律要求しない。envelope、phase、capture順上の局所系列、登録contractを使う。
- manifestの`firstEventTimestamp`と`lastEventTimestamp`はcapture順の先頭・末尾recordの値として保持し、数値上の大小関係を要求しない。
- capture manifestは`captureStartedAt`と`captureCompletedAt`をISO 8601 wall-clockで持つ。wall clockは収録区間の説明にだけ使い、event timestampへ変換しない。

## 検証

- 正負、同値、局所逆行を含むsource timestamp列で、capture orderとtimestamp値がlosslessに保持される。
- session単位rebaseは全sampleへ同じoffsetを適用し、各timestamp差分を保持する。
- sampleごとの投稿直前時刻への置換、timestamp sort、差分clamp、現在boot外timestampを拒否する。
- 物理fixtureが要求するcompanion timestamp関係と、それ以外の説明不能な関係を区別する。
- manifestのcapture wall-clockとevent timestamp domainを混在させない。

## 影響

- 純正trackpadの配送順とtimestamp関係を改変せず解析できる。
- source mouse eventから生成trackpad eventまで、量、順序、時間間隔を同じrunで追跡できる。
- timestamp値だけでは順序を決めず、capture order、session ID、SHA-256で欠落と改ざんを検出する。

## 関連

- [ADR-0038: finger count付きtrackpad入力sessionとmonotonic clockを共通化する](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0039: trackpad eventログを厳格解析しcapture manifestへ固定する](0039-strict-trackpad-event-analysis-and-capture-manifest.md)
- [ADR-0049: buttonを指本数へ固定しイベント量をtrackpad入力へ置換する](0049-fixed-button-to-finger-count-trackpad-input.md)
- [検証手順](../verification.md)
