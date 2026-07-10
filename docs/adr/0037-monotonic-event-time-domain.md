# ADR-0037: CGEvent と慣性を起動後単調時刻へ統一する

- 状態: 採択
- 日付: 2026-07-10

## 背景

CoreGraphics SDK の `CGEventTypes.h` は `CGEventTimestamp` を「roughly, nanoseconds since startup」と定義している。
実入力は従来から `CGEvent.timestamp` を秒へ変換して `GestureCommand.timestamp` に渡していたが、慣性 timer、`generate-scroll`、`system-test` は `Date().timeIntervalSince1970` を使っていた。

この混在により、実入力由来 command と最初の慣性 tick の elapsed が約17億秒になり、慣性が開始直後に終了していた。
また、CLI が Unix epoch 秒をナノ秒化して `CGEvent.timestamp` に設定していたため、Safari などの実投稿診断は通常 runtime と異なる時刻条件だった。

## 決定

- `CGEvent.timestamp`、HID 入力時刻、`GestureCommand.timestamp`、慣性 tick、生成 `CGEvent.timestamp` は、すべて起動後の単調時刻を使う。
- Core の `MonotonicEventClock` を唯一の現在値・秒/ナノ秒変換境界とする。現在値は `DispatchTime.now().uptimeNanoseconds` から得る。
- `InputLogRecord.timestamp` と `CGEventTimestamp` は起動後ナノ秒、`RawInputEvent.time`、`GestureCommand.timestamp`、`RuntimePerformanceRecord.commandTimestamp` は起動後秒とする。runtime performance の `*Nanoseconds` フィールドも同じ uptime ドメインとする。
- `EventPoster` と `system-test` の実投稿は、投稿時点の uptime との差が60秒を超える timestamp を拒否する。epoch、非有限値、古すぎる command を clamp して投稿しない。
- `MomentumEngine` は時刻逆行、非有限 elapsed、通常1秒または設定済み `frameInterval` の2倍を超える tick gap で慣性を停止し、イベントを投稿しない。通常 tick だけは設定済み `frameInterval` を最小積分時間として使う。
- `generate-scroll --dry-run --log-json` と `system-test run --dry-run --log-json` も起動後ナノ秒を出力する。直後に `analyze-log --assert-current-uptime` を実行し、全レコードが現在 uptime から60秒以内であることを機械判定する。
- Reference Target App の ready metadata に必要な wall clock は `wallClockUnixSeconds` と明記し、イベントの `timestamp` と同じフィールド名を使わない。
- PR #101 で取得した Safari 診断は epoch timestamp が混在した可能性を除外できないため、時刻修正後の再取得が終わるまで Issue #10 / #16 の完成証跡に採用しない。

## 影響

- 実入力相当の uptime command から最初の慣性 tick が `.momentum` を生成できる。
- epoch 混入は慣性終了や不正な未来 timestamp 投稿として隠されず、純粋テスト、投稿時検証、JSON Lines assertion で失敗する。
- 保存済み JSON Lines の `timestamp` 単位はナノ秒のままだが、`generate-scroll` と `system-test` の値域は Unix epoch ナノ秒から起動後ナノ秒へ変わる。
- 現在 uptime assertion は取得直後のログ向けであり、保存から60秒を超えた過去ログの一般解析には付けない。
- Safari、Spaces、Mission Control、runtime performance の既存実投稿証跡は、必要に応じて現行 commit で取り直す。

## 関連

- [Issue 管理一覧](../github-issues.md)
- [検証手順](../verification.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [PR レビューチェックリスト](../pr-review-checklist.md)
