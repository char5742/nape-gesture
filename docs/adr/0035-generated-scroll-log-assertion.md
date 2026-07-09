# ADR-0035: generate-scroll dry-run は analyze-log の生成スクロール assertion で判定する

- 状態: 採択
- 日付: 2026-07-10

## 背景

`generate-scroll --dry-run --log-json` は、純正トラックパッドログと生成イベントログを同じ JSON Lines 形式で比較するための前段証跡である。
従来の completion evidence は JSON Lines を保存し、`analyze-log` で集計表示するだけだったため、保存したログが本当に生成スクロールだけで構成され、通常 scroll phase と momentum phase を分離しているかを終了コードで判定できなかった。

`system-test --assert-system-scenario` は `systemTestScenario` / `sequenceIndex` を持つ dry-run 専用であり、momentum を持つ `generate-scroll` の契約とは異なる。

## 決定

- `analyze-log` に `--assert-generated-scroll-log` を追加する。
- この assertion は、空ログ、`scrollWheel` 以外の混在、未生成イベント混在、continuous/precise でない scroll、timestamp 非単調、`systemTestScenario` / `sequenceIndex` 混在、`scrollPhase` と `momentumPhase` の同一イベント混在、通常 scroll phase なし、非ゼロ delta なしを失敗にする。
- momentum がある場合は、通常 scroll phase が終わった後にだけ `momentumPhase` を出し、最後の momentum イベントがゼロ delta で終了することを要求する。
- `generate-scroll` の JSON Lines には `systemTestScenario` / `sequenceIndex` を付けない。これらは System Behavior Test の取り違え防止メタ情報として扱う。
- completion evidence は `generate-scroll --dry-run --log-json` の直後に `analyze-log --json --assert-generated-scroll-log` を実行する。

## 影響

- 生成イベントログを純正ログと比較する前に、生成側ログの最低限の形を機械判定できる。
- `system-test` dry-run と `generate-scroll` dry-run の証跡境界が明確になる。
- この assertion は前面アプリへの投稿や Spaces / Mission Control の画面挙動を証明しない。実挙動は別途 Reference Target App、System Behavior Test、実測ログで確認する。

## 関連

- [ADR-0007: ログ由来チューニング候補の再導出](0007-log-derived-tuning-parameters.md)
- [ADR-0017: System Behavior Test dry-run のシナリオ別機械判定](0017-system-test-scenario-assertion.md)
- [検証手順](../verification.md)
- [完成判定チェックリスト](../completion-checklist.md)
