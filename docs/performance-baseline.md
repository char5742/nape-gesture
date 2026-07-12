# 性能測定基準

この文書は Issue 14 の基準として、入力遅延と CPU 使用率を PR レビューで確認するための証跡を定義する。
`benchmark`は純粋ロジックのベンチマークであり、event tapからtrackpad output event系列の投稿、AppKit受信、画面反映までの実測ではない。

## 保存する証跡

PR には少なくとも次を添付または本文に要約する。

```sh
swift build --scratch-path .build
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture benchmark --events 200000 --json --assert-baseline
.build/debug/nape-gesture doctor --benchmark-events 50000 --json
```

`benchmark --json --assert-baseline` は `BenchmarkReport` 単体の証跡と基準照合の終了コード、`doctor --benchmark-events ... --json` は権限、対象デバイス、実行主体、同じ純粋ロジック benchmark をまとめた証跡として扱う。
どちらも `benchmark.measurementKind` または `measurementKind` が `pureLogic` で、`includesEventTapAndPosting` が `false` であることを確認する。
`BenchmarkReport.schemaVersion` は `3` とし、認識器とスクロール計画の batch p95 / p99 を含める。
`--assert-baseline` は純粋ロジック benchmark の初期合格基準を満たさない場合に非ゼロ終了する。
`doctor --json` の `runtimeReadiness` と `tccStatus` は測定主体の状態確認に使うが、純粋ロジック benchmark の合否そのものとは分けて扱う。
CI では同じ基準として `benchmark --events 200000 --json --assert-baseline` と `doctor --benchmark-events 50000 --json` を実行し、短い smoke 用イベント数だけを性能証跡として扱わない。

## 現時点で測れるもの

`benchmark --json --assert-baseline` と `doctor --benchmark-events ... --json` で自動確認できるもの:

- 認識器の wall 時間、CPU 時間、events/sec、平均 ns/event、CPU ns/event
- スクロール計画の wall 時間、CPU 時間、commands/sec、平均 ns/command、CPU ns/command
- 認識器とスクロール計画の固定 batch wall-clock 由来の p50 / p95 / p99 / max
- 1 core 換算の CPU 使用率目安
- `doctor --json` の `runtimeIdentity`、`runtimeReadiness`、`tccStatus`、対象デバイス検出状態

`cpuPercentOfOneCore` と `reviewMetrics.totalCpuPercentOfOneCore` は、短時間の一括処理で CPU をどれだけ使ったかの目安であり、常駐時 CPU 使用率ではない。
`sampledNanosecondsPerEvent` と `sampledNanosecondsPerCommand` は純粋ロジックを固定 batch で測った wall-clock 分布であり、tap-to-post や AppKit 受信までの入力遅延ではない。
常駐時 CPU 使用率は、実機で `run` を動かしたプロセスを外部サンプルで測る。
tap-to-post は、権限済み実行主体で `--performance-log` または `NAPE_RUNTIME_PERFORMANCE_LOG` を有効にし、`analyze-performance-log --json --assert-baseline` で集計する。

## 実機でしか測れないもの

次は `benchmark` では完了扱いにしない。

- IOHID または CGEvent tap へ入力が届くまでの遅延
- tap callbackからtrackpad output adapterの最初のevent投稿までの処理時間
- 同一frameのscroll + companion gesture、または製品runtimeのDockSwipe / magnification系列の投稿完了までの処理時間
- NavigationSwipe candidate fixture / analyzerの処理時間。製品runtime latencyと混ぜず、候補調査の指標として分離する
- 投稿イベントが AppKit や対象アプリに届くまでの遅延
- WindowServer配送後の縦横scroll、application navigation、Space切替、Mission Control、App Exposé、Zoomの画面反映時間。低レベルevent投稿時間と別に測る
- Nape Pro 実機の連続操作中 CPU 使用率
- スリープ復帰、デバイス抜き差し、権限変更後の復旧時 CPU 使用率

raw event loggerはtap callback内のcopy時間、callback外queue待ち、field scan / encode時間、queue depth、drop countを分離する。logger自身がevent timingを歪めていないことと、trackpad output系列の作成・投稿数が一致することはIssue #132でbaseline化する。

tap-to-post は runtime 性能 JSON Lines から自動集計する。
現行schema 2はユーザー入力の`mode`と実際に投稿した`outputFamily`を分け、`modeCounts`と`outputFamilyCounts`を別々に集計する。schema 1の旧`action`は読込時だけ移行する。
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
| tap callbackから最初のtrackpad output event投稿まで | p95 8 ms以下、p99 16 ms以下 |
| tap callbackから同一frame event系列の投稿完了まで | p95 8 ms以下、p99 16 ms以下 |
| 投稿から AppKit 受信まで | p95 16 ms 以下 |

上記の実機基準は、アクセシビリティと入力監視が許可された日常利用と同じ `.app` または実行ファイルで測る。
`doctor --json` の `runtimeIdentity` が、実際に許可した対象と一致していない測定は採用しない。
tap callback から投稿までの基準は `analyze-performance-log --assert-baseline` で終了コード判定する。
投稿なしrecord、予定event数と実投稿数の不一致、event作成失敗、`measurementKind != runtimeTapToPost`、`includesEventTapAndPosting != true`は不合格とする。

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

常駐プロセスを起動し、`doctor --json` の `runtimeIdentity` と同じ実行主体であることを確認する。
別ターミナルで PID を特定し、1 秒間隔で CPU を採取する。

```sh
pid=$(pgrep -x nape-gesture | head -n 1)
top -l 30 -s 1 -pid "$pid" -stats pid,cpu,time,command
```

アイドル、連続ジェスチャー、操作終了後の 3 区間を分けて保存する。
連続ジェスチャー区間では、同時に `log --exclude-generated`、`log --only-generated`、`target --out` のいずれかを使い、操作が実際に発生していたことを残す。

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
