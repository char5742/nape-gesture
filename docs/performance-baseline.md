# 性能測定基準

この文書は Issue 14 の基準として、入力遅延と CPU 使用率を PR レビューで確認するための証跡を定義する。
`benchmark` は純粋ロジックのベンチマークであり、イベントタップから CGEvent 投稿、AppKit 受信、画面反映までの実測ではない。

## 保存する証跡

性能に関わる PR には、まず純粋ロジック benchmark と doctor benchmark を添付または本文に要約する。

```sh
swift build --scratch-path .build
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture benchmark --events 200000 --json --assert-baseline
.build/debug/nape-gesture doctor --benchmark-events 50000 --json
```

常駐 CPU 使用率を完了条件として扱う PR では、上記とは別に、日常利用と同じ `.app` または実行ファイルの `nape-gesture` を直接起動して得た PID へ `sample-cpu` を実行した証跡を添付する。
completion evidence の短時間 smoke や `/bin/sleep` PID への実行は、コマンド形式の退行確認であり、常駐 CPU 完了証跡にはしない。

```sh
.build/debug/nape-gesture sample-cpu --pid <nape-gesture PID> --expected-executable <対象実行ファイルの絶対パス> --duration 30 --interval 1 --mode idle --json --assert-baseline
```

`benchmark --json --assert-baseline` は `BenchmarkReport` 単体の証跡と基準照合の終了コード、`doctor --benchmark-events ... --json` は権限、対象デバイス、実行主体、同じ純粋ロジック benchmark をまとめた証跡として扱う。
どちらも `benchmark.measurementKind` または `measurementKind` が `pureLogic` で、`includesEventTapAndPosting` が `false` であることを確認する。
`BenchmarkReport.schemaVersion` は `3` とし、認識器とスクロール計画の batch p95 / p99 を含める。
`--assert-baseline` は純粋ロジック benchmark の初期合格基準を満たさない場合に非ゼロ終了する。
`doctor --json` の `runtimeReadiness` と `tccStatus` は測定主体の状態確認に使うが、純粋ロジック benchmark の合否そのものとは分けて扱う。
CI では同じ基準として `benchmark --events 200000 --json --assert-baseline` と `doctor --benchmark-events 50000 --json` を実行し、短い smoke 用イベント数だけを性能証跡として扱わない。
`sample-cpu --expected-executable <path> --json --assert-baseline` は、`proc_pidpath` の実行ファイル、`proc_pidinfo` の開始時刻トークン、audit token の `(pid, pidversion)` を開始時・各 sample の前後で固定し、同一性を確認できた sample だけの `ps` `%CPU` を採用する。idle / active / recovery の平均基準に加え、開始トークンが変わる PID 再利用、pidversion が変わる `exec` / `posix_spawn`、path 変化、audit token を含む同一性再確認失敗も理由を分けて非ゼロ終了にする。`--pid` は `pid_t` の正範囲だけを受理する。

## 現時点で測れるもの

`benchmark --json --assert-baseline` と `doctor --benchmark-events ... --json` で自動確認できるもの:

- 認識器の wall 時間、CPU 時間、events/sec、平均 ns/event、CPU ns/event
- スクロール計画の wall 時間、CPU 時間、commands/sec、平均 ns/command、CPU ns/command
- 認識器とスクロール計画の固定 batch wall-clock 由来の p50 / p95 / p99 / max
- 1 core 換算の CPU 使用率目安
- `doctor --json` の `runtimeIdentity`、`runtimeReadiness`、`tccStatus`、対象デバイス検出状態

`cpuPercentOfOneCore` と `reviewMetrics.totalCpuPercentOfOneCore` は、短時間の一括処理で CPU をどれだけ使ったかの目安であり、常駐時 CPU 使用率ではない。
`sampledNanosecondsPerEvent` と `sampledNanosecondsPerCommand` は純粋ロジックを固定 batch で測った wall-clock 分布であり、tap-to-post や AppKit 受信までの入力遅延ではない。
常駐時 CPU 使用率は、実機で `run` または `.app` を動かしたプロセスを `sample-cpu` で測る。
`sample-cpu` で別に測れるもの:

- 指定 PID の CPU 使用率サンプル、平均値、最大値、基準判定
- `measurementKind: "processCpuSampling"` と `includesEventTapAndPosting: false`
- `expectedExecutablePath`、`resolvedExecutablePath`、`executableIdentityMatched`
- `processStartToken`、`processIDVersion`、`processIdentityStable` による測定中の PID / execution 固定
- idle / active / recovery のモード別 baseline 判定

tap-to-post は、権限済み実行主体で `--performance-log` または `NAPE_RUNTIME_PERFORMANCE_LOG` を有効にし、`analyze-performance-log --json --assert-baseline` で集計する。

## 実機でしか測れないもの

次は `benchmark` では完了扱いにしない。

- IOHID または CGEvent tap へ入力が届くまでの遅延
- tap callback から `CGEventPost` 完了までの処理時間
- 投稿イベントが AppKit や対象アプリに届くまでの遅延
- WindowServer、Spaces、Mission Control の画面反映時間
- Nape Pro 実機の連続操作中 CPU 使用率
- スリープ復帰、デバイス抜き差し、権限変更後の復旧時 CPU 使用率

tap-to-post は runtime 性能 JSON Lines から自動集計する。
この値を完了条件に含める PR では、イベントタップ受信時刻、投稿直前/直後時刻、投稿コマンド数を同じ操作 ID で記録した `RuntimePerformanceRecord` と、`analyze-performance-log --json --assert-baseline` の出力を添付する。
投稿から AppKit 受信までの遅延と画面反映時間は runtime 性能ログだけでは算出できないため、Reference Target App の target log または同等の実測証跡を別途添付する。

## 合格基準

純粋ロジック benchmark の初期合格基準:

| 項目 | 基準 |
| --- | --- |
| `measurementKind` | `pureLogic` |
| `includesEventTapAndPosting` | `false` |
| `recognizer.averageNanosecondsPerEvent` | 2,000 ns/event 以下 |
| `recognizer.cpuNanosecondsPerEvent` | 2,000 ns/event 以下 |
| `recognizer.sampledNanosecondsPerEvent.p95Nanoseconds` | 50,000 ns/event 以下 |
| `recognizer.sampledNanosecondsPerEvent.p99Nanoseconds` | 250,000 ns/event 以下 |
| `scrollPlanner.averageNanosecondsPerCommand` | 2,000 ns/command 以下 |
| `scrollPlanner.cpuNanosecondsPerCommand` | 2,000 ns/command 以下 |
| `scrollPlanner.sampledNanosecondsPerCommand.p95Nanoseconds` | 50,000 ns/command 以下 |
| `scrollPlanner.sampledNanosecondsPerCommand.p99Nanoseconds` | 250,000 ns/command 以下 |
| `doctor.settingsValidationIssues` | 空 |

実機の常駐 CPU 使用率の合格基準:

| 状態 | 基準 |
| --- | --- |
| アイドル 30 秒 | 平均 1% 以下 |
| 連続ジェスチャー 30 秒 | 平均 15% 以下 |
| 操作終了 5 秒後 | 1% 以下へ戻る |

実機の入力遅延の合格基準:

| 区間 | 基準 |
| --- | --- |
| tap callback から最初の投稿まで | p95 8 ms 以下、p99 16 ms 以下 |
| tap callback から連続スクロール投稿まで | p95 8 ms 以下、p99 16 ms 以下 |
| 投稿から AppKit 受信まで | p95 16 ms 以下 |

上記の実機基準は、アクセシビリティと入力監視が許可された日常利用と同じ `.app` または実行ファイルで測る。
`doctor --json` の `runtimeIdentity` が、実際に許可した対象と一致していない測定は採用しない。
tap callback から投稿までの基準は `analyze-performance-log --assert-baseline` で終了コード判定する。
投稿なしレコード、生成イベント作成失敗、`measurementKind != runtimeTapToPost`、`includesEventTapAndPosting != true` は不合格とする。

## tap-to-post 測定手順

CLI 実行主体で測る場合:

```sh
.build/debug/nape-gesture run --config <設定ファイル> --performance-log <runtime-performance.jsonl>
.build/debug/nape-gesture analyze-performance-log <runtime-performance.jsonl> --json --assert-baseline
```

GUI app 実行主体で測る場合:

```sh
NAPE_RUNTIME_PERFORMANCE_LOG=<runtime-performance.jsonl> .build/NapeGesture.app/Contents/MacOS/nape-gesture app --config <設定ファイル>
.build/NapeGesture.app/Contents/MacOS/nape-gesture analyze-performance-log <runtime-performance.jsonl> --json --assert-baseline
```

`scripts/collect-runtime-event-evidence.sh` は、TCC 許可後の `gesture-drag`、`gesture-wheel`、`gesture-wheel-then-kill-switch` で runtime 性能ログを保存し、同じ基準を自動判定する。
TCC 未許可で scenario が未実行の場合、runtime 性能ログも完成証跡として扱わない。

## 実機 CPU 測定手順

GUI runtime の測定対象は `.build/NapeGesture.app/Contents/MacOS/nape-gesture` 自身とする。`open` 経由ではなくこの executable を直接起動し、そのコマンドの `$!` を保存する。`pgrep -x nape-gesture | head -n 1` は同名の別プロセスを選び得る。`open ... &` の `$!` は `open`、`swift run ... &` の `$!` は SwiftPM の実行主体になり得るため、いずれも PID 確定に使わない。

次の手順では app runtime を直接起動し、同じ PID と expected executable を 3 区間で固定する。`config_path` は検証対象の絶対パスへ置き換える。

```sh
set -eu

repository_root=$(pwd -P)
sampler_executable="$repository_root/.build/debug/nape-gesture"
runtime_executable="$repository_root/.build/NapeGesture.app/Contents/MacOS/nape-gesture"
config_path="/absolute/path/to/nape-gesture.json"
evidence_directory="$repository_root/artifacts/runtime-cpu"
mkdir -p "$evidence_directory"

"$runtime_executable" app --config "$config_path" \
  > "$evidence_directory/runtime.stdout.log" \
  2> "$evidence_directory/runtime.stderr.log" &
runtime_pid=$!

cleanup_runtime() {
  kill "$runtime_pid" 2>/dev/null || true
  wait "$runtime_pid" 2>/dev/null || true
}
trap cleanup_runtime EXIT
trap 'exit 1' HUP INT TERM

"$sampler_executable" sample-cpu --pid "$runtime_pid" --expected-executable "$runtime_executable" --duration 30 --interval 1 --mode idle --json --assert-baseline > "$evidence_directory/cpu-idle.json"
"$sampler_executable" sample-cpu --pid "$runtime_pid" --expected-executable "$runtime_executable" --duration 30 --interval 1 --mode active --json --assert-baseline > "$evidence_directory/cpu-active.json"
"$sampler_executable" sample-cpu --pid "$runtime_pid" --expected-executable "$runtime_executable" --duration 5 --interval 1 --mode recovery --json --assert-baseline > "$evidence_directory/cpu-recovery.json"

cleanup_runtime
trap - EXIT HUP INT TERM
```

アイドル、連続ジェスチャー、操作終了後の 3 区間を分けて保存する。
連続ジェスチャー区間では、同時に `log --exclude-generated`、`log --only-generated`、`target --out` のいずれかを使い、操作が実際に発生していたことを残す。
`sample-cpu` の `measurementKind` は `processCpuSampling`、`includesEventTapAndPosting` は `false` である。既存の `schemaVersion: 1` とキーを維持したうえで、`expectedExecutablePath == resolvedExecutablePath`、`executableIdentityMatched == true`、`processIdentityStable == true`、全 sample の `processStartToken` と `processIDVersion` が report の値と同じことも確認する。`processCommand` は診断表示用であり、同一性の合格条件には使わない。
この CPU 証跡は tap-to-post 遅延や AppKit 受信を示さないため、runtime 性能 JSON Lines と target log とは分けて採否する。

## 超過時に調整する項目

純粋ロジックの基準を超えた場合:

- 認識器の状態遷移で不要な command 生成や抑制判定が増えていないか確認する
- `deadZonePoints`、`directionLockRatio`、`dragSensitivity`、`wheelSensitivity` の変更がイベント数や command 数を増やしていないか確認する
- `acceleration` のしきい値、指数、最大倍率が過剰な計算や過剰なイベント生成につながっていないか確認する

常駐 CPU または入力遅延の基準を超えた場合:

- 対象デバイス条件を絞り、対象外デバイスの入力を処理していないか確認する
- `momentum.frameInterval`、`minimumStartVelocity`、`stopVelocity`、`decayPerSecond` が投稿頻度を増やしすぎていないか確認する
- スクロール生成の steps、interval、momentum steps、momentum decay、momentum scale の組み合わせで投稿数が増えすぎていないか確認する
- 自前生成イベントを再解釈していないか、`generatedByNapeGesture` のログで確認する
- 権限未許可、対象デバイス未検出、古い `.app` のまま測っていないか `doctor --json` で確認する

調整後は、純粋ロジック benchmark と実機測定の両方を取り直す。
