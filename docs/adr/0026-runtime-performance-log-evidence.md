# ADR-0026: 固定GestureClass変換のruntime性能を構造化記録する

- 状態: 採択
- 日付: 2026-07-09
- 更新日: 2026-07-14

## 背景

pure logic benchmarkだけでは、event tap callbackからsource command生成、class固有ProductOutput、system-wide投稿完了までの遅延、drop、queue増加を評価できない。

button 3 / 4 / 5は同じgeneric finger-count eventを生成しない。2本指scroll / swipe、3本指system swipe、4本指system pinchではevent type、batch件数、field、phase、単位変換が異なるため、性能recordはsessionで選択したGestureClassとgenerated batchを明示する必要がある。

## 決定

- runtime投稿経路はversioned `RuntimePerformanceRecord`をJSON Linesで出力できる。
- CLIの`run`は`--performance-log <path>`、GUI appは環境変数`NAPE_RUNTIME_PERFORMANCE_LOG`で同じschemaを使う。
- 現行schemaは最低限、次を記録する。
  - operation ID、session ID、source device、source button、固定GestureClass
  - source kind、input delta X / Y、capture order
  - command phase、terminal reason、ProductOutput family、OS build
  - event tap callback開始、認識完了、生成開始、投稿直前、投稿完了のmonotonic timestamp
  - 期待event数、生成event数、投稿event数、作成失敗数、drop数、queue depth
- `eventFamily`はclass固有compatibility adapterの内部contract分類とし、ユーザーmode、button assignment、OS / App結果として集計しない。
- `mode`、方向別`action`、applicationを入力変換の分類keyにしない。
- analyzerはGestureClass別と全体について、tap-to-generate、tap-to-postのp50 / p95 / p99 / max、drop率、作成失敗数、queue depthを出力する。
- source sampleとgenerated batchをoperation ID、session ID、capture orderで対応付けられないrecordは完成証跡として拒否する。
- class間でgenerated event件数や単位の一致を要求しない。各classの登録contractに対する正確性gateを先に通し、その後でlatencyを集計する。
- 未知schema、必須field欠落、現在boot外timestamp、terminal後の追加record、非有限値を非ゼロ終了にする。
- runtime性能logは画面反映時間を含まない。OS / App結果とtarget受信時間は別証跡にする。

## 移行

結果別modeまたはgeneric finger-count transportを正本にする旧性能schemaは現行baselineへ混在させない。必要な回帰値は固定GestureClass schemaへ再収録する。

## 完成判定への影響

- dry-run logはschemaとanalyzerの機械回帰にだけ使う。
- TCC許可済みの製品bundleまたは同一identityの実行主体で取得し、入力、生成batch、投稿を対応付けたlogだけをruntime性能証跡にする。
- 3 GestureClassと未押下passthroughの全経路が正確性・latency基準を満たすまでrelease gateを通さない。

## 関連

- [ADR-0022: 純粋ロジックbenchmarkのbatch percentile](0022-benchmark-batch-percentile-metrics.md)
- [ADR-0038: 固定GestureClass sessionとmonotonic clock](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0049: buttonごとにGestureClassを割り当てる](0049-fixed-button-to-gesture-class-input.md)
- [性能測定基準](../performance-baseline.md)
