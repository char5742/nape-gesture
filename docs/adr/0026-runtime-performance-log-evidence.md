# ADR-0026: runtime 性能ログと実行主体固定による性能証跡

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
- macOS SDK の `ESMessage.h` が定めるとおり、特定の execution は `(pid, pidversion)` で識別する。`exec` / `posix_spawn` では PID と開始時刻や executable path が同じでも pidversion が増えるため、開始時刻と path だけを同一性契約にしない。
- pidversion は `task_name_for_pid`、`task_info(TASK_AUDIT_TOKEN)` で `audit_token_t` を取得し、libbsm の `audit_token_to_pid` と `audit_token_to_pidversion` で抽出する。audit token の PID が要求 PID と一致することも必須とし、取得不能、返却サイズ不一致、PID 不一致は fail closed にする。取得した Mach task name port は成功・失敗の両経路で必ず `mach_port_deallocate` する。
- 実行主体 snapshot は audit token、`proc_pidinfo(PROC_PIDTBSDINFO)` の開始時刻から作る `processStartToken`、`proc_pidpath` で解決した実行ファイルパスを前後確認して作る。開始時と各 CPU sample の前後で snapshot を照合し、開始トークン変化は PID 再利用、pidversion 変化は `exec` / `posix_spawn`、pidversion が同じままの resolved path 変化は path 変化として理由を分けて不合格にする。
- JSON は既存キーと `schemaVersion: 1` を維持したうえで、report と各 sample に `processIDVersion` を追加する。report の `processIDVersion` と `processStartToken` は開始 snapshot の値であり、合格 sample では両方が report と一致する。`processCommand` は診断表示用であり、合格条件には使わない。
- libbsm は `nape-gesture` executable target だけにリンクし、`NapeGestureCore` と core test target へ波及させない。
- `sample-cpu` の `measurementKind` は `processCpuSampling`、`includesEventTapAndPosting` は `false` とし、tap-to-post、AppKit 受信、画面反映の証跡としては扱わない。
- `scripts/collect-runtime-event-evidence.sh` は、TCC 許可後の gesture シナリオで runtime 性能ログを保存し、`analyze-performance-log --assert-baseline` を実行する。
- `scripts/collect-completion-evidence.sh` の `sample-cpu` は、`/bin/sleep` を直接起動して得た `$!` と `--expected-executable /bin/sleep` を使うコマンド形式の smoke として扱い、日常利用主体の常駐 CPU 完了証跡には昇格しない。
- GUI runtime の常駐 CPU 証跡では `.build/NapeGesture.app/Contents/MacOS/nape-gesture` 自身を直接起動し、その `$!` を PID とする。`pgrep`、`open`、`swift run` は PID 確定に使わない。
- この証跡は AppKit 受信や画面反映までは含まない。投稿から AppKit 受信までの遅延は、Reference Target App の target log と別証跡で扱う。

## 影響

- TCC 未許可環境でも、ログ schema、解析器、閾値判定は core test と fixture で確認できる。
- TCC 許可後は、人間の目視判断ではなく JSON Lines と終了コードで tap-to-post を判定できる。
- 常駐 CPU は、日常利用と同じ `.app` または実行ファイルを直接起動した PID と expected executable を指定した `sample-cpu` の JSON と終了コードで判定できる。
- CPU 値が基準内でも、別プロセス、shell wrapper、測定中の PID 再利用、同一 path を含む `exec` / `posix_spawn`、実行ファイルパス変化、同一性取得不能を完成証跡として採用しない。
- `--performance-log` を有効にしない通常実行では、性能ログのファイル I/O は発生しない。
- 実イベント投稿まで進めない環境では、runtime 性能ログも完成証跡に昇格しない。

## 関連

- [純粋ロジック benchmark の batch p95 / p99 証跡](0022-benchmark-batch-percentile-metrics.md)
- [Runtime event 証跡の自動収集と人間作業境界](0006-runtime-event-evidence-automation.md)
- [Runtime event 証跡の status JSON](0019-runtime-event-status-json.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [性能測定基準](../performance-baseline.md)
