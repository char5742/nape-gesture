# ADR-0026: runtime 性能ログによる tap-to-post 証跡

- 状態: 採択
- 日付: 2026-07-09
- 更新日: 2026-07-10

## 背景

純粋ロジック benchmark は `GestureRecognizer` と `ScrollGenerationPlanner` の処理コストを確認できるが、event tap callback から `CGEvent` 投稿までの遅延は含まない。
完成判定では、常駐 GUI アプリまたは同じ実行主体で、tap-to-post の p95 / p99 と常駐 CPU 使用率を構造化された証跡として残す必要がある。
ただし、tap-to-post と CPU 使用率は別の測定であり、一方の成功をもう一方の証跡として扱わない。

## 決定

- runtime の投稿経路は、任意の `RuntimePerformanceRecord` JSON Lines を出力できる。
- CLI の `run` は `--performance-log <path>`、GUI app は環境変数 `NAPE_RUNTIME_PERFORMANCE_LOG` で同じ形式のログを保存する。
- ログには `operationID`、`source`、`action`、`commandKind`、`commandPhase`、event tap callback 開始時刻、認識完了時刻、投稿直前/直後時刻、生成イベント数、作成失敗数を含める。
- `analyze-performance-log <path> --json --assert-baseline` は、tap callback から投稿直前/投稿完了までの p95 / p99、投稿なしレコード、作成失敗数を終了コードで判定する。
- `sample-cpu --pid <pid> --expected-executable <path> --duration <秒> --interval <秒> --mode idle|active|recovery --json --assert-baseline` は、指定 PID の実行主体同一性と `%CPU` を周期サンプルし、常駐 CPU 使用率を終了コードで判定する。`--expected-executable` は必須とする。
- 実行主体は、macOS の `proc_pidpath` で解決した実行ファイルパスと、`proc_pidinfo(PROC_PIDTBSDINFO)` の開始時刻から作る `processStartToken` で固定する。開始時と各 CPU sample の前後で expected path、resolved path、開始トークンを照合し、実行ファイル変更、PID 再利用候補、再確認失敗は不合格にする。
- JSON は既存キーと `schemaVersion: 1` を維持したうえで、report に `expectedExecutablePath`、`resolvedExecutablePath`、`executableIdentityMatched`、`processStartToken`、`processIdentityStable` を追加する。各 sample にも resolved path、開始トークン、同一性判定を保存する。`processCommand` は診断表示用であり、合格条件には使わない。
- `sample-cpu` の `measurementKind` は `processCpuSampling`、`includesEventTapAndPosting` は `false` とし、tap-to-post、AppKit 受信、画面反映の証跡としては扱わない。
- `scripts/collect-runtime-event-evidence.sh` は、TCC 許可後の gesture シナリオで runtime 性能ログを保存し、`analyze-performance-log --assert-baseline` を実行する。
- `scripts/collect-completion-evidence.sh` の `sample-cpu` は、`/bin/sleep` を直接起動して得た `$!` と `--expected-executable /bin/sleep` を使うコマンド形式の smoke として扱い、日常利用主体の常駐 CPU 完了証跡には昇格しない。
- GUI runtime の常駐 CPU 証跡では `.build/NapeGesture.app/Contents/MacOS/nape-gesture` 自身を直接起動し、その `$!` を PID とする。`pgrep`、`open`、`swift run` は PID 確定に使わない。
- この証跡は AppKit 受信や画面反映までは含まない。投稿から AppKit 受信までの遅延は、Reference Target App の target log と別証跡で扱う。

## 影響

- TCC 未許可環境でも、ログ schema、解析器、閾値判定は core test と fixture で確認できる。
- TCC 許可後は、人間の目視判断ではなく JSON Lines と終了コードで tap-to-post を判定できる。
- 常駐 CPU は、日常利用と同じ `.app` または実行ファイルを直接起動した PID と expected executable を指定した `sample-cpu` の JSON と終了コードで判定できる。
- CPU 値が基準内でも、別プロセス、shell wrapper、測定中の実行ファイル変更、PID 再利用候補を完成証跡として採用しない。
- `--performance-log` を有効にしない通常実行では、性能ログのファイル I/O は発生しない。
- 実イベント投稿まで進めない環境では、runtime 性能ログも完成証跡に昇格しない。

## 関連

- [純粋ロジック benchmark の batch p95 / p99 証跡](0022-benchmark-batch-percentile-metrics.md)
- [Runtime event 証跡の自動収集と人間作業境界](0006-runtime-event-evidence-automation.md)
- [Runtime event 証跡の status JSON](0019-runtime-event-status-json.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [性能測定基準](../performance-baseline.md)
