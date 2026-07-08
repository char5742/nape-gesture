# ADR-0006: Runtime event 証跡の自動収集と人間作業境界

- 状態: 採択
- 日付: 2026-07-09

## 背景

Issue #6 の元入力抑制と Issue #12 のキルスイッチは、最終的に実 event tap、Reference Target App、実イベント投稿の経路で証跡を取る必要がある。
一方で、物理マウス操作、物理キーボード操作、目視判断へすぐ寄せると再現性が落ち、`need:human` の範囲が広がりすぎる。

## 決定

- Issue #6 / #12 の runtime event 証跡は `scripts/collect-runtime-event-evidence.sh` を正とする。
- スクリプトは `status.json` を出力し、総合状態を `success`、`blocked`、`failed` のいずれかで記録する。
- TCC で実イベントへ進めない場合は、`status.json` に `status: "blocked"` と `blockerCode` を記録する。アクセシビリティ未許可は `accessibility.missing`、入力監視未成功は `inputMonitoring.notGranted` とする。
- スクリプトは TCC 判定前に `gesture-wheel-then-kill-switch` と `normal-after-release` の dry-run preflight を保存し、実イベント未実行時も計画イベント列の前段証跡を同じ artifact root に残す。
- スクリプトは `doctor --json` の `tccStatus.accessibility.status` と `tccStatus.inputMonitoring.status` が `granted` であることを確認してから、実 event tap 経路のシナリオを実行する。
- アクセシビリティ未許可の場合、target log が空だった失敗として扱わない。`runtimeIdentity`、`hidProbe`、`runtimeReadiness` を `summary.md` に残し、TCC / アクセシビリティ権限という外部ブロッカーとして記録する。
- HID 入力監視プローブに成功しない場合も、runtime event シナリオを実行しない。`runtimeIdentity`、`hidProbe`、`runtimeReadiness` を `summary.md` に残し、TCC / 入力監視権限という外部ブロッカーとして記録する。
- 実イベント経路の判定は、Reference Target App の target log と `analyze-target-log` の終了コードで行う。
- `gesture-drag`、`gesture-wheel` は `--assert-no-leaks --assert-has-generated-event` を使い、未マーク入力が前面アプリへ届いた場合、または Nape Gesture 生成イベントが AppKit に届かなかった場合に失敗させる。
- `kill-switch` は生成イベントが届かないことも正常系になり得るため、`--assert-has-generated-event` を使わない。`--assert-no-leaks` を使い、未マークキー入力が前面アプリへ届いた場合に失敗させる。
- `kill-switch` は target log だけでなく daemon log の停止メッセージも確認し、前面アプリへ漏れなかっただけの空振りを成功扱いしない。
- 物理キーボード操作へ進む前に、`system-test run --scenario kill-switch --dry-run --log-json` で `Control + Option + Command + G` 相当の未マーク keyDown / keyUp を completion evidence に保存する。
- 暴走中停止の前段証跡は `gesture-wheel-then-kill-switch` を使う。dry-run は `analyze-log --assert-kill-switch-shortcut --assert-gesture-before-kill-switch`、runtime event は daemon 停止ログと `analyze-target-log --assert-no-leaks --assert-has-generated-event` で判定する。
- `normal-after-release` は通常入力通過が期待値なので、`--assert-no-leaks` を使わない。`--assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel` を使い、解放後の通常クリック、通常ドラッグ、通常ホイールのいずれかが届かない場合に失敗させる。
- Reference Target App の gesture 受信形式は、人間によるトラックパッド操作へ進む前に `Fixtures/gesture-target-log.jsonl` と `analyze-target-log --assert-has-gesture` で `swipe`、`magnify`、`rotate` の解析経路を機械判定する。
- CI は completion evidence と同じ target log fixture assertion を smoke test に含める。`clean-target-log`、`leaky-target-log`、`no-generated-target-log`、`normal-input-target-log`、`gesture-target-log` を assertion 付きで検証し、単なる集計表示だけに戻さない。
- `system-test` は Reference Target App を前面に保つため、target log 証跡では `--target finder` / `--target safari` を付けない。
- `system-test` は HID 生入力を伴わないため、runtime event 証跡では `init-config --allow-unmatched` の検証用設定を使い、実利用設定と分ける。
- `.build/NapeGesture.app` に TCC 権限を集約する場合は、`NAPE_RUNTIME_EVENT_USE_APP_BUNDLE=1` で release build、`.app` 作成、bundle 検証、runtime event 証跡を一続きに実行する。
- 既に検証用の実行主体が決まっている場合は、`NAPE_RUNTIME_EVENT_TOOL=<実行ファイル>` で `run`、`target`、`system-test`、`analyze-target-log`、`doctor` に使う実行ファイルを明示する。
- 人間作業として残すのは、実行主体へのアクセシビリティ権限付与、入力監視権限付与、Nape Pro 実機由来の最終ログを採用する場合の物理操作、JSON / 終了コードで代替できない画面挙動観察に限定する。

## 影響

- `need:human` は、キルスイッチや元入力抑制のレビュー待ちではなく、macOS UI での TCC 許可など自動化できない作業を表す。
- `summary.md` の日本語文面に依存せず、`status.json.status` と `blockerCode` で外部ブロッカーを再判定できる。
- 権限付与後は、物理キー操作や目視判断ではなく、同じスクリプトを再実行して証跡を更新できる。
- 実行主体を `.app` に寄せられるため、debug CLI と日常利用 `.app` の両方へ権限を付ける運用を避けやすくなる。
- `normal-after-release` の未マーク通常クリック、通常ドラッグ、通常ホイールは、漏れではなく通常入力通過の証跡として扱う。

## 関連

- [GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [Issue による orchestration と証跡付き close 方針](0005-issue-orchestration-and-evidence-close.md)
- [Runtime event 証跡の status JSON](0019-runtime-event-status-json.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
