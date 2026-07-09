# ADR-0026: runtime 性能ログによる tap-to-post 証跡

- 状態: 採択
- 日付: 2026-07-09
- 更新: 2026-07-10（非同期配送 completion と schema 2）

## 背景

純粋ロジック benchmark は `GestureRecognizer` と `ScrollGenerationPlanner` の処理コストを確認できるが、event tap callback から `CGEvent` 投稿までの遅延は含まない。
完成判定では、常駐 GUI アプリまたは同じ実行主体で、tap-to-post の p95 / p99 を構造化された証跡として残す必要がある。

## 決定

- runtime の投稿経路は、任意の `RuntimePerformanceRecord` JSON Lines を出力できる。
- CLI の `run` は `--performance-log <path>`、GUI app は環境変数 `NAPE_RUNTIME_PERFORMANCE_LOG` で同じ形式のログを保存する。
- ログには `operationID`、`source`、`action`、`commandKind`、`commandPhase`、event tap callback 開始時刻、認識完了時刻、投稿直前/直後時刻、生成イベント数、作成失敗数を含める。
- runtime が serial queue へ非同期配送する場合、enqueue 時に `deliveryDeferred=true` の provisional record を保存し、同じ command 単位の `operationID` で queue 内の AX / CGEvent 実配送 completion record を追記する。解析時は completion があれば1配送へ解決し、その投稿直前/直後時刻を使う。
- `RuntimePerformanceRecord` schema 2 は `deliveryDeferred` を持つ。旧 schema 1 は `false` として読み、completion がなく `deliveryDeferred=true` のまま残った record は投稿 latency 分布に含めず baseline を不合格にする。
- `analyze-performance-log <path> --json --assert-baseline` は、tap callback から投稿直前/投稿完了までの p95 / p99、投稿なしレコード、作成失敗数を終了コードで判定する。
- `scripts/collect-runtime-event-evidence.sh` は、TCC 許可後の gesture シナリオで runtime 性能ログを保存し、`analyze-performance-log --assert-baseline` を実行する。
- この証跡は AppKit 受信や画面反映までは含まない。投稿から AppKit 受信までの遅延は、Reference Target App の target log と別証跡で扱う。

## 影響

- TCC 未許可環境でも、ログ schema、解析器、閾値判定は core test と fixture で確認できる。
- TCC 許可後は、人間の目視判断ではなく JSON Lines と終了コードで tap-to-post を判定できる。
- `--performance-log` を有効にしない通常実行では、性能ログのファイル I/O は発生しない。
- 実イベント投稿まで進めない環境では、runtime 性能ログも完成証跡に昇格しない。
- 非同期 queue を導入しても enqueue 時刻を投稿完了と誤認せず、queue 待ちと AX fallback 処理を tap-to-post に含める。

## 関連

- [純粋ロジック benchmark の batch p95 / p99 証跡](0022-benchmark-batch-percentile-metrics.md)
- [Runtime event 証跡の自動収集と人間作業境界](0006-runtime-event-evidence-automation.md)
- [Runtime event 証跡の status JSON](0019-runtime-event-status-json.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [性能測定基準](../performance-baseline.md)
