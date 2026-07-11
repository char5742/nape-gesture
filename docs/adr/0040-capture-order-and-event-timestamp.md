# ADR-0040: capture順とevent timestampを分離する

- 状態: 採択
- 日付: 2026-07-11

## 背景

ADR-0039では、`trackpad-event-log`の全recordでevent timestampが非減少になると仮定していた。
しかし、macOS 26.5.1（build 25F80）の純正トラックパッドを実測すると、`scrollWheel`より後に配送されるcompanion eventが、直前eventより小さいtimestampを持つ系列が確認された。
配送順をtimestampで再構成したり、timestamp逆行だけでraw captureを不正と判定すると、純正trackpadの系列を改変または拒否してしまう。

また、Issue #125はscenarioごとの開始・終了時刻を要求するが、capture manifest schema 1は完了wall-clockしか保存していなかった。

## 決定

- eventの配送順は、logger callbackで採番した0始まりかつ欠落のない`captureIndex`だけを正本とする。
- event timestampは取得値をlosslessに保持し、局所的な逆行を許可する。timestampでrecordをsortしない。
- analyzerは`captureIndex`の欠落、重複、並べ替えを拒否するが、timestamp逆行だけでは失敗にしない。
- generated product provenanceも`captureIndex`で順序を固定し、capture logとのtimestamp完全一致を検証する。record間のtimestamp非減少は要求しない。
- scroll eventとcompanion eventの対応にtimestamp同値を要求しない。envelope、phase、capture順上の局所系列を使い、固定index差やtimestamp最近傍だけで対応付けない。
- manifestの`firstEventTimestamp`と`lastEventTimestamp`は、数値上の最小・最大ではなく、capture順の先頭・末尾recordの値として保持する。大小関係は検証しない。
- capture manifestをschema 2へ上げ、`captureStartedAt`と`captureCompletedAt`をISO 8601 wall-clockで必須化する。開始はevent受付開始直前、完了は受付停止、queue drain、log flush / close後に記録し、開始が完了を超えるmanifestを拒否する。
- schema 1は開始時刻を証明できないため、現行の採用可能証跡として受理しない。
- ADR-0038の非減少timestamp要件は、製品側のsession進行と投稿scheduleに限定する。CGEvent tapで観測した異なるevent family間のglobal配送順には適用しない。

## 影響

- 純正trackpadのscrollとcompanion eventの配送順・timestamp関係を改変せず解析できる。
- timestampが逆行しても、capture順の改ざんは`captureIndex`と最終log SHA-256で検出できる。
- schema 1の既存captureは調査資料としては残せるが、Issue #125の完成証跡にはschema 2での再収録が必要になる。
- manifestからscenarioの実収録区間を直接確認できる。

## 置換範囲

ADR-0039の「timestampは逆行しない」と「capture完了wall-clockだけをmanifestへ保存する」という決定を置き換える。その他の厳格JSON Lines、raw field、manifest完全性、provenance、host再構築の決定は維持する。

## 関連

- [ADR-0038: trackpad出力sessionとmonotonic clockを共通化する](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0039: trackpad eventログを厳格解析しcapture manifestへ固定する](0039-strict-trackpad-event-analysis-and-capture-manifest.md)
- [検証手順](../verification.md)
