# ADR-0035: generate-scroll dry-run は analyze-log の生成スクロール assertion で判定する

- 状態: 採択
- 日付: 2026-07-10

## 背景

`generate-scroll --dry-run --log-json` は、純正トラックパッドログと生成イベントログを同じ JSON Lines 形式で比較するための前段証跡である。
従来の completion evidence は JSON Lines を保存し、`analyze-log` で集計表示するだけだったため、保存したログが本当に生成スクロールだけで構成され、期待した方向、件数、量、phase 状態列を保っているかを終了コードで判定できなかった。空でないことや phase が存在することだけでは、39件を先頭1件へ切り詰めたログ、途中欠落、逆方向混在、合計相殺、同一 timestamp、終了後 tail も成功し得る。

`system-test --assert-system-scenario` は `systemTestScenario` / `sequenceIndex` を持つ dry-run 専用であり、momentum を持つ `generate-scroll` の契約とは異なる。

## 決定

- `analyze-log --assert-generated-scroll-log` は、`--expected-direction positive-x|negative-x`、`--expected-normal-events <数>`、`--expected-momentum-events <数>`、`--expected-normal-x-total <量>`、`--expected-phase-mode auto` の全指定を必須にする。
- `analyze-log` は option allowlist を走査し、未知 option、余分な positional、重複、値欠落、生成スクロール assertion alias の同時指定を解析前に拒否する。期待値の typo や重複を黙って無視しない。
- `--expected-normal-events` は通常 scroll record 数、`--expected-momentum-events` は momentum changed record 数を表す。通常は1件以上、momentumは0件以上を受理する。momentumが1件以上なら ended-zero 1件を別に必須とし、期待総数を `normal + momentum + 1`、0件なら終了recordを要求せず `normal` とする。
- 全 record は Nape Gesture 生成 `scrollWheel`、`isContinuous == 1` とし、timestamp は厳密増加させる。同一 record 重複、同一 timestamp、順序逆転、`systemTestScenario` / `sequenceIndex` 混在を失敗にする。
- 全 record は X 軸だけを使い、`scrollDeltaX` が `pointDeltaX` の `generate-scroll` と同じ per-record 丸め量であることを要求する。通常区間は各 `pointDeltaX` を `normalXTotal / normalEventCount` と照合し、point 合計と、per-step 量子化値を件数倍した scroll 合計を検査する。サブ1 pointでは正しい `scrollDeltaX == 0` を許可する。非ゼロ値は期待方向と一致させる。
- `auto` の状態列は通常1件なら `changed`、2件以上なら `began, changed*, ended` とする。momentum 0件ならそこで終了し、1件以上なら `changed+, ended-zero` を続ける。`--momentum-decay 0` が生成するゼロ delta の momentum changed は許可する一方、phase なし、未知 phase、scroll/momentum phase 混在、通常 ended 欠落、momentum ended 後の tail は失敗にし、ended-zero を最終 record に限定する。
- `generate-scroll --phase began|changed|ended|cancelled|momentum` の明示 override はこの assertion ではサポートしない。`--expected-phase-mode` は `auto` だけを受理し、それ以外は解析前に非ゼロ終了する。
- `generate-scroll` の JSON Lines には `systemTestScenario` / `sequenceIndex` を付けない。これらは System Behavior Test の取り違え防止メタ情報として扱う。
- completion evidence は `generate-scroll --dry-run --log-json` の直後に全期待値付き assertion を実行する。正常39件 fixture に加え、1 step、momentumなし、サブ1 point量子化、`momentum-decay 0` を成功として固定し、切り詰め、途中欠落、方向・量異常、phase・timestamp・重複異常を expected failure として固定する。
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
