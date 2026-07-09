# System Behavior Test matrix

この文書は、Issue #9 / #10 の System Behavior Test で何を機械証跡として扱い、何を画面挙動の実測待ちとして残すかを固定する。
正本の構造化データは CLI から出す。

```sh
.build/debug/nape-gesture system-test readiness --json --assert
.build/debug/nape-gesture system-test readiness --markdown --assert
```

`system-test matrix` は同じ出力の別名である。
completion evidence では alias の退行も検出するため、`system-test matrix --json --assert` も保存する。

## 判定境界

- `system-test readiness --json --assert` の成功は、シナリオ定義、Issue 紐づけ、機械証跡コマンド、画面挙動待ち、`need:human` 境界が欠落していないことを示す。
- `system-test run --dry-run --log-json` と `analyze-log --assert-system-scenario` の成功は、生成予定イベント列の前段証跡である。
- Spaces / Mission Control、ページ戻る / 進む、ズーム、横スクロールの画面が実際に動いた証跡ではない。
- `need:human` は CLI の scenario 自体には付けない。物理トラックパッド、Nape Pro 実機操作、TCC、GitHub Billing、Developer ID 署名など、人間作業が不可避な Issue / PR にだけ付ける。
- 画面挙動は、まず CGEvent 実投稿、Reference Target App、保存済みログ、computer-use で代替できる範囲を埋める。

## JSON schema

`schemaVersion: 1` の report は次のフィールドを持つ。

| フィールド | 意味 |
| --- | --- |
| `scope` | `system-behavior-test-readiness` 固定 |
| `completionState` | 画面挙動など未完了証跡が残る場合は `screen-behavior-evidence-pending` |
| `humanWorkPolicy` | `need:human` を最後の手段に限定する方針 |
| `summary.scenarioCount` | `SystemTestScenario.allCases` と一致するシナリオ数 |
| `summary.machinePreflightScenarioCount` | dry-run / analyze-log で前段証跡を取れるシナリオ数 |
| `summary.screenBehaviorPendingScenarioCount` | 画面挙動の実測を完成条件に残すシナリオ数 |
| `summary.runtimeTargetEvidenceScenarioCount` | runtime target log 証跡の対象シナリオ数 |
| `summary.needHumanLabelScenarioCount` | CLI scenario が直接 `need:human` を要求する数。通常は `0` |
| `scenarios[].machineEvidence` | completion evidence で先に保存するコマンド |
| `scenarios[].screenBehaviorEvidence` | 実画面で最終確認する内容 |
| `scenarios[].humanWorkBoundary` | 人間作業へ進む前に代替する確認 |

## Issue #9

`space-left`、`space-right`、`mission-control` は Issue #9 / #16 に紐づく。
前段証跡では、水平 `scrollWheel` または Mission Control ショートカットのイベント列を保存し、`analyze-log --assert-system-scenario` で確認する。
完成扱いには、Finder / Safari / Mission Control 上の画面挙動、同じ scenario 名の CGEvent log、AppKit target log、体感差分が必要である。

## Issue #10

`page-back`、`page-forward`、`zoom-in`、`zoom-out`、`horizontal-scroll` は Issue #10 / #16 に紐づく。
前段証跡では、離散ショートカットまたは水平スクロールのイベント列を保存し、`analyze-log --assert-system-scenario` で確認する。
完成扱いには、Safari または対応アプリでのページ遷移、ズーム倍率変更、横スクロール可能ビューの表示位置変化が必要である。

## 関連

- [ADR-0017: System Behavior Test dry-run のシナリオ別機械判定](adr/0017-system-test-scenario-assertion.md)
- [完成判定チェックリスト](completion-checklist.md)
- [検証方針](verification.md)
- [Issue 一覧](github-issues.md)
