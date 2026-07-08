# ADR-0019: Runtime event 証跡の status JSON

- 状態: 採択
- 日付: 2026-07-09

## 背景

Issue #6 / #12 / #16 の runtime event 証跡は、アクセシビリティ許可や入力監視許可がない環境では実イベント投稿へ進まない。
従来の `collect-runtime-event-evidence.sh` は `summary.md` に外部ブロッカーを記録していたが、総合状態や未実行理由が Markdown の文章に閉じていた。
この状態では、後続のメインスレッドやサブエージェントが、証跡 root 単体から `success`、`blocked`、`failed` を機械的に判定しにくい。

## 決定

- `scripts/collect-runtime-event-evidence.sh` は `status.json` を出力する。
- `status.json` は `schemaVersion`、`status`、`blockerCode`、`blockerCategory`、`artifactRoot`、`summaryFile`、`commandsFile`、`doctorJsonPath`、`preflightDir`、`scenarioDir`、`toolPath`、`failureCount` を含める。
- `status` は `success`、`blocked`、`failed` のいずれかにする。
- TCC で実イベントへ進めない場合は `status: "blocked"` とし、アクセシビリティ未許可は `blockerCode: "accessibility.missing"`、入力監視未成功は `blockerCode: "inputMonitoring.notGranted"` にする。
- runtime script は TCC 判定前に `gesture-wheel-then-kill-switch` と `normal-after-release` の dry-run preflight を保存し、実イベントへ進めない場合でも計画イベント列の前段証跡を同じ artifact root に残す。
- `summary.md` は人間が読む正本として維持し、採否の機械判定は `status.json` と各 JSON log を優先する。

## 影響

- 外部ブロッカーの Issue コメントや completion checklist 更新時に、Markdown の文面ではなく `status.json.status` と `blockerCode` を証跡として参照できる。
- TCC 未許可の環境でも、runtime event の前段 dry-run が成功しているかを同じ artifact root から確認できる。
- `status: "blocked"` は完成を意味しない。人間作業としての TCC 許可後に再実行し、`status: "success"` と target log assertion の成功を保存する必要がある。

## 関連

- [Runtime event 証跡の自動収集と人間作業境界](0006-runtime-event-evidence-automation.md)
- [Issue による orchestration と証跡付き close 方針](0005-issue-orchestration-and-evidence-close.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
