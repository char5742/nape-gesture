# ADR-0022: 純粋ロジック benchmark の batch p95 / p99 証跡

- 状態: 採択
- 日付: 2026-07-09

## 背景

性能要件では、入力遅延が体感できない水準であることを証跡で示す必要がある。
実際の tap-to-post 遅延、投稿から AppKit 受信までの遅延、常駐 CPU 使用率は、アクセシビリティと入力監視が許可された実行主体と実機操作が必要であり、純粋な CI では完了扱いにできない。

一方で、従来の `benchmark --json --assert-baseline` は平均処理時間と平均 CPU コストに寄っていた。
平均値だけでは、純粋ロジック内に短いスパイクが混ざる退行を見落とす余地がある。

## 決定

- `BenchmarkReport.schemaVersion` を `3` に上げる。
- `recognizer.sampledNanosecondsPerEvent` と `scrollPlanner.sampledNanosecondsPerCommand` を追加する。
- 各分布は、1 event / command ごとに `DispatchTime.now()` を呼ばず、固定 batch の wall-clock を unit 数で割った値から `minimum`、`p50`、`p95`、`p99`、`maximum` を出す。
- `reviewMetrics` に `recognizerP95NanosecondsPerEvent`、`recognizerP99NanosecondsPerEvent`、`scrollPlannerP95NanosecondsPerCommand`、`scrollPlannerP99NanosecondsPerCommand` を追加する。
- `--assert-baseline` は平均値と CPU 平均に加えて、batch p95 / p99 の上限も確認する。
- CI と completion evidence は、benchmark 単体 JSON と doctor 内 benchmark の両方に schemaVersion 3 と p95 / p99 field があることを確認する。
- この値は純粋ロジック処理コストであり、tap callback から `CGEventPost`、AppKit 受信、画面反映までの入力遅延実測として扱わない。

## 影響

- 実機操作前でも、認識器とスクロール計画の短時間スパイクを平均値だけより強く検出できる。
- `benchmark` JSON の互換性は schemaVersion 3 として扱う。
- 入力遅延の完成判定には、引き続き権限済み実行主体での tap-to-post または同等の実測証跡が必要である。

## 関連

- [doctor runtime ready の機械判定](0011-doctor-runtime-ready-assertion.md)
- [Runtime event 証跡の自動収集と人間作業境界](0006-runtime-event-evidence-automation.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [性能測定基準](../performance-baseline.md)
