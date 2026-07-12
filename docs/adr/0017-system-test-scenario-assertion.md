# ADR-0017: System Behavior Test dry-run のシナリオ別機械判定

> historical note: 本文のSpaces、Mission Control、ページ戻る/進む、ズーム、横スクロールは移行前診断scenarioの結果名であり、現行modeまたは低レベルevent familyではない。現在の用語境界は[ADR-0048](0048-separate-input-mode-event-family-os-result-and-evidence.md)を正とする。

- 状態: 置換済み
- 日付: 2026-07-09
- 置換先: [ADR-0036](0036-emulate-trackpad-driver-output-events.md)

## 背景

Issue #9 と Issue #10 の System Behavior Test は、最終的に Finder、Safari、Mission Control、Spaces の画面挙動を実測する必要がある。
しかし、`system-test run --dry-run --log-json` を保存するだけでは、保存した JSON Lines が本当に指定シナリオの期待イベント列かを人間が読む余地が残る。
人間作業は最後の手段に限定するため、実画面へ進む前の生成予定イベント列は終了コードで採否できる必要がある。

## 決定

- `system-test run --dry-run --log-json` は各 `InputLogRecord` に `systemTestScenario` と `sequenceIndex` を付与する。
- `analyze-log` に `--assert-system-scenario <name>` を追加し、`systemTestScenario` と `sequenceIndex` も照合する。
- Spaces と横スクロール系シナリオは、Nape Gesture 生成済み `scrollWheel`、各イベントの水平 delta の方向、垂直 delta なし、continuous/precise、`began` / `changed` / `ended` の `scrollPhase`、`momentumPhase == 0`、timestamp の単調増加を確認する。
- Mission Control、ページ戻る/進む、ズームは、Nape Gesture 生成済み `keyDown` / `keyUp`、keyCode、余計な modifier を含まない exact modifier flags を確認する。
- `analyze-log --json` は `generatedKeyEvents`、`unmarkedKeyEvents`、`generatedScrollEvents`、`momentumScrollEvents`、水平 scroll 方向数、`keySignatureCounts` を出し、シナリオ assertion の根拠を構造化して残す。
- `kill-switch`、`gesture-wheel-then-kill-switch`、`normal-after-release` など既存の未生成入力シナリオも、同じ `--assert-system-scenario` 入口で確認できるようにする。
- completion evidence と CI は、`system-test run --dry-run --log-json` の直後に `analyze-log --json --assert-system-scenario <name>` を実行する。

## 影響

- Issue #9 / #10 の前段証跡は、ログ保存だけでなくシナリオ別の終了コードと JSON メタ情報で採否できる。
- `space-right` と `horizontal-scroll` のようにイベント形状が近いシナリオも、`systemTestScenario` で取り違えを検出できる。
- `need:human` は、実画面挙動、純正トラックパッド操作、TCC 権限操作など、ログのシナリオ整合性では代替できない作業に絞られる。
- `--assert-system-scenario` の成功は、生成予定イベント列の正しさを示す前段証跡であり、Finder / Safari / Mission Control / Spaces の画面が実際に動いた証跡ではない。

## 関連

- [GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [Issue による orchestration と証跡付き close 方針](0005-issue-orchestration-and-evidence-close.md)
- [離散割り当ての System Behavior Test dry-run 証跡](0010-system-test-discrete-assignment-dry-run-evidence.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
