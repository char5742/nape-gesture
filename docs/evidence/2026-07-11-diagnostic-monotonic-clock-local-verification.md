# 診断event単調時刻 local verification

- 日付: 2026-07-11
- 対象: `codex/diagnostic-monotonic-clock-v2`
- 対象Issue: #102

## 結果

| 検証 | 結果 |
| --- | --- |
| `swift build --scratch-path .build` | 成功 |
| `.build/debug/nape-gesture-core-tests` | 成功 |
| `.build/debug/nape-gesture-diagnostic-output-tests` | 成功 |
| `sh scripts/check-provenance.sh` | 成功 |
| `sh scripts/check-product-output-boundary.sh` | 成功 |
| `sh scripts/check-diagnostic-event-time.sh` | 成功 |
| 全13 `system-test` scenarioのdry-run | 成功 |
| `generate-scroll --dry-run --log-json` | 成功 |
| `log --duration 30 --only-generated`実行中の`generate-scroll --steps 3` | 3 event受信 |
| Reference Target App global monitor | generated precise scroll 3 event受信 |

dry-runで生成した14 log、228 eventは、すべて現在bootの起動後timestamp範囲内だった。
diagnostic output testはCGEventを実投稿せず、現在boot内のtimestampが保持され、負値、NaN、正負infinity、Unix epoch、現在bootの未来時刻がevent作成失敗になることを確認した。

TCC許可済みdebug実行ファイルで`log --duration 30 --only-generated`を開始し、`generate-scroll --x 7 --y -19 --steps 3`を投稿した。`/tmp/nape-issue102-posted-30.jsonl`は3件で、全recordが`generatedByNapeGesture: true`かつ0より大きい起動後timestampだった。

Reference Target Appにも同じ3件が`scrollWheel`、`hasPreciseScrollingDeltas: true`、Nape Gesture生成eventとして届いた。ready時の`appIsActive`、`windowIsKey`、`windowIsMain`がfalseだったためcapture sourceは`globalMonitor`だけであり、`--assert-has-foreground-capture`は期待どおり失敗した。このtarget logは投稿到達の補助証跡であり、前面AppKit受信の完成証跡には使わない。

## 未検証境界

この証跡でevent作成、source guard、CGEvent投稿、event tap受信、AppKit global monitor受信までを確認した。
前面AppKit window受信とSafari画面挙動は、この時刻修正の合否と混同せず、通常bundleを前面化したruntime証跡またはtrackpad driver上位出力adapterの検証で別途取得する。
