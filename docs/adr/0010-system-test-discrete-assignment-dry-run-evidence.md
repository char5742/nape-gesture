# ADR-0010: 離散割り当ての System Behavior Test dry-run 証跡

- 状態: 採択
- 日付: 2026-07-09

## 背景

Issue #10 のページ戻る、進む、ズーム、横スクロールは、最終的に Safari や対応アプリ上での画面挙動実測が必要である。
一方で、実アプリ操作へ進む前に、System Behavior Test が生成する予定の keyDown / keyUp や scrollWheel のイベント列は機械証跡として固定できる。

## 決定

- completion evidence は `page-back`、`page-forward`、`zoom-in`、`zoom-out`、`horizontal-scroll` の `system-test run --dry-run --log-json` と `analyze-log` を保存する。
- completion evidence の dry-run では `--target safari` を付けない。対象アプリの前面化や画面挙動確認は実測フェーズとして分ける。
- dry-run と `analyze-log` は、生成予定イベント列の証跡であり、Safari や対応アプリでのページ遷移、ズーム、横スクロールが実際に動いた証跡としては扱わない。
- 実アプリ挙動の最終採否には、画面挙動、CGEvent log、Reference Target App target log、体感差分を同じシナリオ名で保存する。

## 影響

- `need:human` は Safari や対応アプリでの実操作に限定し、生成予定イベント列の検証は人間作業前に自動化できる。
- target log と dry-run log を混同しない。dry-run は前面アプリへ投稿しないため、AppKit 受信証跡ではない。
- ページ戻る / 進む / ズーム / 横スクロールの前段証跡が completion evidence に継続して残る。

## 関連

- [GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [Issue による orchestration と証跡付き close 方針](0005-issue-orchestration-and-evidence-close.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
