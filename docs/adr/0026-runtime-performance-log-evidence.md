# ADR-0026: finger-count入力変換のruntime性能を構造化記録する

- 状態: 採択
- 日付: 2026-07-09
- 更新日: 2026-07-12

## 背景

pure logic benchmarkだけでは、event tap callbackからtrackpad入力生成、system-wide投稿完了までの遅延、drop、queue増加を評価できない。固定button / finger-countモデルでは、button 3 / 4 / 5で同じ変換原則と性能特性を持つことも確認する必要がある。

結果別modeやevent family別の集計は、製品責務を誤って表現する。性能記録は入力sample、finger count、共通変換contract、session lifecycleを正本にする。

## 決定

- runtime投稿経路は、versioned `RuntimePerformanceRecord`をJSON Linesで出力できる。
- CLIの`run`は`--performance-log <path>`、GUI appは環境変数`NAPE_RUNTIME_PERFORMANCE_LOG`で同じschemaを使う。
- 現行schemaは最低限、次を記録する。
  - operation ID、session ID、source device、source button、finger count
  - source kind、input delta X/Y、output delta X/Y、sample order
  - command phase、terminal reason、contract ID、OS build
  - event tap callback開始、認識完了、生成開始、投稿直前、投稿完了のmonotonic timestamp
  - 期待event数、生成event数、投稿event数、作成失敗数、drop数、queue depth
- `eventFamily`を記録する場合はcompatibility adapterの内部contract分類とし、ユーザーmode、button assignment、結果名として集計しない。
- `mode`、方向別`action`、application、OS/App結果を入力変換の分類keyにしない。
- analyzerはfinger count別と全体について、tap-to-generate、tap-to-postのp50 / p95 / p99 / max、drop率、作成失敗数、queue depthを出力する。
- button 3 / 4 / 5へ同一fixtureを与え、finger count以外の変換処理時間と生成sample対応が許容差内であることを判定する。
- source sampleと生成sampleをoperation ID、session ID、sample orderで対応付けられない記録は完成証跡として拒否する。
- 未知schema、必須field欠落、現在boot外timestamp、source / contractにないtimestamp変換、terminal後の追加record、非有限値を非ゼロ終了にする。
- runtime性能logは画面反映時間を含まない。OS/App結果とtarget受信時間は別証跡にする。

## 移行

結果別modeを必須にする旧性能schemaは読み取り専用のhistorical fixtureとしても保持しない。必要な回帰値は固定button / finger-count schemaへ再収録する。新schemaへ変換できない旧recordを現在のbaselineへ混在させない。

## 完成判定への影響

- 実イベント投稿を行わないdry-run logは、schemaとanalyzerの機械回帰にだけ使う。
- TCC許可済みの製品bundleまたは同一identityの実行主体で取得し、入力、生成、投稿を対応付けたlogだけをruntime性能証跡にする。
- 2 / 3 / 4本指の全経路が基準を満たすまでrelease gateを通さない。

## 関連

- [ADR-0022: 純粋ロジックbenchmarkのbatch percentile](0022-benchmark-batch-percentile-metrics.md)
- [ADR-0038: finger-count trackpad入力sessionとmonotonic clock](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0049: buttonを指本数へ固定しイベント量をtrackpad入力へ置換する](0049-fixed-button-to-finger-count-trackpad-input.md)
- [性能測定基準](../performance-baseline.md)
