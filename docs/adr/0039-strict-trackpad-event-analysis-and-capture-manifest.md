# ADR-0039: trackpad eventログを厳格解析しcapture manifestへ固定する

現行比較schemaは[ADR-0049](0049-fixed-button-to-gesture-class-input.md)に従い、source button、保存済み割り当て、sessionで選択したGestureClass、X/Y入力量、変換後batch、sample対応、session、terminalを追跡する。`event family`はclass固有adapterの内部contract分類であり、ユーザーmodeまたは製品完成単位として扱わない。

- 状態: 採択（timestamp順序とcapture wall-clockはADR-0040、投稿後raw field 39 / 40の解釈はADR-0043、製品入力モデルはADR-0049で拡張）
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
- `captureIndex`は0始まりで欠落なく増加し、全recordのmetadataは完全一致しなければならない。timestampは取得値をlosslessに保持し、順序判定は[ADR-0040](0040-capture-order-and-event-timestamp.md)に従う。
- typed modelがfieldを並べ替えたり既定値を補う前のraw JSON表現を保持する。不明なtop-level fieldとmetadata fieldは捨てず、解析reportから参照可能にする。
- raw fieldの意味は純正fixtureで確認するまで推測しない。Phase 1では構文、型、順序、bit pattern、serialized dataとの一致だけを判定する。

### Capture manifest

- loggerはoutput fileのflush、close、0件でないこと、queue errorがないことを確認した後だけcapture manifestを書く。
- manifestにはevidence kind、確定済みlogのSHA-256 / byte数 / event数 / capture順の最初と最後のtimestamp、metadata、logger実行ファイルSHA-256、capture wall-clockを保存する。開始・完了wall-clockの必須化は[ADR-0040](0040-capture-order-and-event-timestamp.md)で追加した。
- log SHA-256はclose後の最終bytesから計算する。manifestは同一directory内の一時fileからatomicに確定し、旧sidecarとsymlinkをcapture開始前に除去する。書き込み、rename、親directory、logとの同一路径競合の失敗時も、有効なsidecarや一時fileを残さない。
- `physicalTrackpad`と`generatedProduct`を採用可能な証跡にする場合、scenario ID、device label、repo HEAD SHAを必須にする。`synthetic`はloggerとanalyzerの機械回帰にだけ使い、純正contract値の根拠にしない。
- analyzerはmanifest単体の整合性だけでなく、渡されたlogのSHA-256、byte数、event数、timestamp範囲、metadataとの完全一致を検証する。

### Generated product provenance

- `generatedProduct`の解析には、capture logへ結合されたprovenance traceを必須にする。
- provenanceはlog / trace SHA-256、capture index、timestamp、event type、output session ID、event family、event kind、delivery、run token、scenario、repo / binary identity、投稿直前の対象process fieldをrecordごとに持つ。source button、GestureClass、sample order、入力X/Y量はruntime performance recordとsession traceで同じrunへ結合する。
- provenance件数、順序、timestamp、event typeはcapture logと一致しなければならない。
- capture log上の製品eventは生成markerを必須にする。2本指内部contractではtype 22を`scroll`、type 29 companion / envelopeを`gesture`として区別し、declared event kindをactual typeと照合する。この分類はbutton assignmentまたは製品機能名ではない。gestureは既知のscroll / key / pointer / button / null以外でなければならない。provenance上の対象PID、Accessibility、keyboard shortcut、key / pointer / button配送を失敗にする。
- adapterはpost operation直前のraw field 39 / 40=`0`を検証し、成功投稿直後のdirect post traceへ`delivery: systemWide`を記録する。capture後のfield 39 / 40が非0でも、それ単独では投稿APIの宛先指定を判定しない。direct post trace、capture log / manifestとのprovenance照合、製品sourceのmodule境界とsource guardを組み合わせて、AX / PID / shortcut経路がないことを固定する。
- raw CGEventだけからAccessibility APIの利用有無や投稿APIの宛先指定は復元できない。provenanceを暗号学的な証明として扱わず、投稿前検査とsource guardを省略しない。

### Host再構築とCLI

- analyzer CLIは`serializedEventBase64`からCoreGraphics eventを再構築し、type、timestamp、flags、取得済みsubtype、named field、raw fieldのinteger値とdouble bit patternをJSON recordと比較する。capture時にsubtypeを取得できず省略または`null`になったrecordへ、再構築時の値を事後補完しない。
- CoreGraphics serializationはsource PID、source state、生成markerを持つ`sourceUserData`、未公開fieldなど一部の値を別processへの再構築時に保持しない。type、timestamp、flags、取得済みsubtype、保持される公開named fieldの不一致は失敗にし、`sourceUserData`とraw field差分は捨てずに独立した`rawFieldDifferences`へ保存する。生成markerの有無はserialized eventではなくcapture時のactual recordで検査する。これらの差分だけでPhase 1を失敗にせず、Phase 2の同一OS build fixture比較で意味と許容可否を確定する。
- 構造、manifest、host再構築、provenanceの各reportを1つの結果へまとめる。
- `--contract`を指定しないPhase 1 reportはschema 1と既存JSON shapeを維持する。Phase 2 contract sectionは明示指定時だけschema 2として追加し、既存利用者へ無条件のschema変更を行わない。
- 不正な入力でも可能な範囲のreportを標準出力へ出し、その後に非ゼロ終了する。`--json`なしでは人間が読める要約を出す。
- `generatedProduct`以外へprovenanceを必須にしない。ただし指定されたprovenanceが不正な場合は無視せず失敗にする。

## 段階境界

Phase 1ではlogger、厳格parser、manifest、host再構築、generated provenance、negative tests、CLI、CIを完成させる。
Phase 2では純正trackpadの3つの上位GestureClassを同一schemaで物理収録し、class固有event type、field、X/Yまたはpinch量、phase、timestamp、順序、terminal、OS build別許容差を固定する。既存のscroll / momentum fixtureは[ADR-0042](0042-versioned-scroll-momentum-contract-comparison.md)に基づく2本指class内部contractの部分資料として再利用できるが、button 3 / 4 / 5の固定変換を単独では証明しない。

Phase 1の合成event、特定familyの解析、画面結果のいずれかが成功しても、Issue #129全体または製品完成とは判定しない。

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
- [ADR-0040: capture順とevent timestampを分離する](0040-capture-order-and-event-timestamp.md)
- [ADR-0041: 物理captureのready同期と公開fixture境界を固定する](0041-physical-capture-readiness-and-fixture-privacy.md)
- [ADR-0042: 25F80 scroll / momentum契約を独立fixtureで比較する](0042-versioned-scroll-momentum-contract-comparison.md)
- [ADR-0043: 25F80 trackpad scrollを製品出力として構成する](0043-trackpad-scroll-product-output.md)
- [ADR-0049: buttonごとにGestureClassを割り当てる](0049-fixed-button-to-gesture-class-input.md)
