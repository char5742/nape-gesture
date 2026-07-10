# ADR-0035: generate-scroll dry-run は analyze-log の生成スクロール assertion で判定する

- 状態: 採択
- 日付: 2026-07-10

## 背景

`generate-scroll --dry-run --log-json` は、純正トラックパッドログと生成イベントログを同じ JSON Lines 形式で比較するための前段証跡である。
従来の completion evidence は JSON Lines を保存し、`analyze-log` で集計表示するだけだったため、保存したログが本当に生成スクロールだけで構成され、期待した方向、件数、量、phase 状態列を保っているかを終了コードで判定できなかった。空でないことや phase が存在することだけでは、39件を先頭1件へ切り詰めたログ、途中欠落、逆方向混在、合計相殺、同一 timestamp、終了後 tail も成功し得る。

`system-test --assert-system-scenario` は `systemTestScenario` / `sequenceIndex` を持つ dry-run 専用であり、momentum を持つ `generate-scroll` の契約とは異なる。

## 決定

- `analyze-log --assert-generated-scroll-log` は、`--expected-direction positive-x|negative-x`、`--expected-normal-events <数>`、`--expected-momentum-events <数>`、`--expected-normal-x-total <量>`、`--expected-phase-mode auto` の全指定を必須にする。
- `--expected-normal-events` は通常 scroll record 数、`--expected-momentum-events` は非ゼロの momentum changed record 数を表す。momentum ended-zero 1件は別に必須とし、期待総数を `normal + momentum + 1` とする。`auto` では通常2件以上、momentum changed 1件以上を要求する。
- 全 record は Nape Gesture 生成 `scrollWheel`、`isContinuous == 1` とし、timestamp は厳密増加させる。同一 record 重複、同一 timestamp、順序逆転、`systemTestScenario` / `sequenceIndex` 混在を失敗にする。
- 全非ゼロ record は X 軸だけを使い、`pointDeltaX` / `scrollDeltaX` の両方が非ゼロ、相互に同符号、期待方向と同符号、`generate-scroll` と同じ丸め量であることを要求する。通常区間は point/scroll の両 X 合計を `--expected-normal-x-total` と照合する。
- `auto` の状態列は通常 `began, changed*, ended`、続いて momentum `changed+, ended-zero` と exact に一致させる。phase なし、未知 phase、scroll/momentum phase 混在、通常 ended 欠落、changed-zero 終端、momentum ended 後の tail を失敗にし、ended-zero を最終 record に限定する。
- `generate-scroll --phase began|changed|ended|cancelled|momentum` の明示 override はこの assertion ではサポートしない。`--expected-phase-mode` は `auto` だけを受理し、それ以外は解析前に非ゼロ終了する。
- `generate-scroll` の JSON Lines には `systemTestScenario` / `sequenceIndex` を付けない。これらは System Behavior Test の取り違え防止メタ情報として扱う。
- completion evidence は `generate-scroll --dry-run --log-json` の直後に全期待値付き assertion を実行する。正常39件 fixture を成功、切り詰め、途中欠落、方向・量異常、phase・timestamp・重複異常を expected failure として固定する。
- `Fixtures/sample-generated-scroll-log.jsonl` は `compare-log` 用 sample とし、この assertion では expected failure にする。成功契約には `Fixtures/generated-scroll-auto-valid.jsonl` を使う。

## 影響

- 生成イベントログを純正ログと比較する前に、生成側ログの期待方向、exact 件数、通常 X 合計量、auto phase 状態列を機械判定できる。
- `system-test` dry-run と `generate-scroll` dry-run の証跡境界が明確になる。
- この assertion は前面アプリへの投稿や Spaces / Mission Control の画面挙動を証明しない。実挙動は別途 Reference Target App、System Behavior Test、実測ログで確認する。

## 関連

- [ADR-0007: ログ由来チューニング候補の再導出](0007-log-derived-tuning-parameters.md)
- [ADR-0017: System Behavior Test dry-run のシナリオ別機械判定](0017-system-test-scenario-assertion.md)
- [検証手順](../verification.md)
- [完成判定チェックリスト](../completion-checklist.md)
