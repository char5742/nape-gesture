# ADR-0039: trackpad eventログを厳格解析しcapture manifestへ固定する

- 状態: 採択
- 日付: 2026-07-11

## 背景

`trackpad-event-log`は、純正trackpadとNape Gesture生成eventを同じraw schemaで保存する。
しかし、通常の`Codable` decodeだけでは旧schema向け既定値補完、field順序の正規化、不明fieldの破棄が起こり得る。
また、JSON Lines本体だけでは、capture完了後の完全なbytes、実行したlogger、証跡種別、生成eventの配送経路を固定できない。

純正trackpad contractを再導出する正本には、途中書き込み、別captureとの混同、対象PID配送やAccessibility fallbackを含む生成列を採用してはならない。

## 決定

### JSON Lines解析

- 現行schemaの解析は厳格modeとし、空でないUTF-8、最終LF、空行なし、1行1object、重複keyなしを必須にする。
- `schemaVersion`、metadata、capture index、timestamp、event type、named field、raw field 0...255、double bit pattern、serialized eventを現行schemaの必須fieldとして検証する。CoreGraphicsで取得不能なevent subtypeは省略または`null`を許可し、値がある場合だけ整数型を必須にする。
- parserのJSON nestingは128段を上限とし、上限超過をprocess crashではなく構造化issueとして返す。
- `captureIndex`は0始まりで欠落なく増加し、timestampは逆行せず、全recordのmetadataは完全一致しなければならない。
- typed modelがfieldを並べ替えたり既定値を補う前のraw JSON表現を保持する。不明なtop-level fieldとmetadata fieldは捨てず、解析reportから参照可能にする。
- raw fieldの意味は純正fixtureで確認するまで推測しない。Phase 1では構文、型、順序、bit pattern、serialized dataとの一致だけを判定する。

### Capture manifest

- loggerはoutput fileのflush、close、0件でないこと、queue errorがないことを確認した後だけcapture manifestを書く。
- manifestにはevidence kind、確定済みlogのSHA-256 / byte数 / event数 /最初と最後のtimestamp、metadata、logger実行ファイルSHA-256、capture完了wall-clockを保存する。
- log SHA-256はclose後の最終bytesから計算する。manifestは同一directory内の一時fileからatomicに確定し、旧sidecarとsymlinkをcapture開始前に除去する。書き込み、rename、親directory、logとの同一路径競合の失敗時も、有効なsidecarや一時fileを残さない。
- `physicalTrackpad`と`generatedProduct`を採用可能な証跡にする場合、scenario ID、device label、repo HEAD SHAを必須にする。`synthetic`はloggerとanalyzerの機械回帰にだけ使い、純正contract値の根拠にしない。
- analyzerはmanifest単体の整合性だけでなく、渡されたlogのSHA-256、byte数、event数、timestamp範囲、metadataとの完全一致を検証する。

### Generated product provenance

- `generatedProduct`の解析には、capture logへ結合されたprovenance traceを必須にする。
- provenanceはlog SHA-256、capture index、timestamp、event type、output session ID、event family、event kind、deliveryをrecordごとに持つ。
- provenance件数、順序、timestamp、event typeはcapture logと一致しなければならない。
- capture log上の製品eventは生成markerを必須にし、既知のscrollはscroll event type、gestureは既知のscroll / key / pointer / button / null以外でなければならない。raw target process fieldが非0のevent、またはprovenance上の対象PID、Accessibility、keyboard shortcut、key / pointer / button配送を失敗にする。
- raw CGEventだけからAccessibility APIの利用有無は復元できない。analyzerはtraceに記録された配送経路を検査し、製品sourceからAX / PID / shortcut経路が存在しないことはmodule境界とsource guardで別途固定する。provenanceを暗号学的な証明として扱わない。

### Host再構築とCLI

- analyzer CLIは`serializedEventBase64`からCoreGraphics eventを再構築し、type、timestamp、flags、取得済みsubtype、named field、raw fieldのinteger値とdouble bit patternをJSON recordと比較する。capture時にsubtypeを取得できず省略または`null`になったrecordへ、再構築時の値を事後補完しない。
- CoreGraphics serializationはsource PID、source state、生成markerを持つ`sourceUserData`、未公開fieldなど一部の値を別processへの再構築時に保持しない。type、timestamp、flags、取得済みsubtype、保持される公開named fieldの不一致は失敗にし、`sourceUserData`とraw field差分は捨てずに独立した`rawFieldDifferences`へ保存する。生成markerの有無はserialized eventではなくcapture時のactual recordで検査する。これらの差分だけでPhase 1を失敗にせず、Phase 2の同一OS build fixture比較で意味と許容可否を確定する。
- 構造、manifest、host再構築、provenanceの各reportを1つの結果へまとめる。
- 不正な入力でも可能な範囲のreportを標準出力へ出し、その後に非ゼロ終了する。`--json`なしでは人間が読める要約を出す。
- `generatedProduct`以外へprovenanceを必須にしない。ただし指定されたprovenanceが不正な場合は無視せず失敗にする。

## 段階境界

Phase 1ではlogger、厳格parser、manifest、host再構築、generated provenance、negative tests、CLI、CIを完成させる。
純正trackpad固有のscroll companion、phase / momentum、DockSwipe、NavigationSwipe、magnificationの必須field、順序、OS build別許容差は、Issue #125の物理capture後にPhase 2として固定する。

Phase 1の合成eventが成功しても、Issue #129全体または製品完成とは判定しない。

## 影響

- truncated、reordered、別capture、typed decodeによる暗黙補完を機械的に拒否できる。
- 純正trackpad値を取得する前に解析経路を自動化でき、人間へ依頼する物理操作を最小化できる。
- captureごとにlog、metadata、logger binary、generated deliveryを再現可能に追跡できる。
- Phase 2で未知raw fieldの意味を実測から追加しても、Phase 1のraw表現を失わない。

## 関連

- [ADR-0036: trackpad driver上位出力eventを再現する](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0037: 製品gesture出力と診断event出力を分離する](0037-separate-product-and-diagnostic-event-output.md)
- [ADR-0038: trackpad出力sessionとmonotonic clockを共通化する](0038-trackpad-output-session-and-monotonic-clock.md)
- [検証手順](../verification.md)
- [完成チェックリスト](../completion-checklist.md)
