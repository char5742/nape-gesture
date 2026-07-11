# 診断event単調時刻 local verification

- 日付: 2026-07-11
- 対象: `codex/diagnostic-monotonic-clock-v2`
- 対象Issue: #102

## 結果

| 検証 | 結果 |
| --- | --- |
| `swift build --scratch-path .build` | 成功 |
| `swift build -c release --scratch-path .build` | 成功 |
| `.build/debug/nape-gesture-core-tests` | 成功 |
| `.build/debug/nape-gesture-diagnostic-output-tests` | 成功 |
| `.build/release/nape-gesture-diagnostic-output-tests` | 成功 |
| `sh scripts/check-provenance.sh` | 成功 |
| `sh scripts/check-product-output-boundary.sh` | 成功 |
| `sh scripts/check-diagnostic-event-time.sh` | 成功 |
| 全13 `system-test` scenarioのdry-run | 成功 |
| 全48 `generate-scroll --dry-run --log-json` pattern | 成功 |
| `log --duration 30 --only-generated`実行中の`generate-scroll --steps 3` | 3 event受信 |
| Reference Target App global monitor | generated precise scroll 3 event受信 |

dry-runで生成した14 log、228 eventは、すべて現在bootの起動後timestamp範囲内だった。
diagnostic output testはCGEventを実投稿せず、現在boot内のtimestampが保持され、負値、NaN、正負infinity、Unix epoch、現在bootの未来時刻がevent作成失敗になることを確認した。

PR #135のP1追補では、shortcutのdown/up生成・検証失敗を0件投稿にすること、途中投稿失敗後にscroll terminal、`mouseUp`、`keyUp`へ収束することをfailure injectionで確認した。Unix epoch / future startと元timestamp回帰は0件投稿にし、有効なstartからの未来予定offsetは許可して実event timestampを投稿時referenceへ置き換える。全13 system scenarioの既定222 recordと、4 mode x 6 phase x momentum有無の全48 generate pattern 188 recordは、期待件数、隣接offset、系列全体offset、現在boot上限を直接検証した。timestamp回帰時の差分はUInt64 underflowさせずtest failureにする。この追補検証では実eventを投稿していない。

TCC許可済みdebug実行ファイルで`log --duration 30 --only-generated`を開始し、`generate-scroll --x 7 --y -19 --steps 3`を投稿した。`/tmp/nape-issue102-posted-30.jsonl`は3件で、全recordが`generatedByNapeGesture: true`かつ0より大きい起動後timestampだった。

Reference Target Appにも同じ3件が`scrollWheel`、`hasPreciseScrollingDeltas: true`、Nape Gesture生成eventとして届いた。ready時の`appIsActive`、`windowIsKey`、`windowIsMain`がfalseだったためcapture sourceは`globalMonitor`だけであり、`--assert-has-foreground-capture`は期待どおり失敗した。このtarget logは投稿到達の補助証跡であり、前面AppKit受信の完成証跡には使わない。

## 未検証境界

この証跡でevent作成、source guard、CGEvent投稿、event tap受信、AppKit global monitor受信までを確認した。
前面AppKit window受信とSafari画面挙動は、この時刻修正の合否と混同せず、通常bundleを前面化したruntime証跡またはtrackpad driver上位出力adapterの検証で別途取得する。
