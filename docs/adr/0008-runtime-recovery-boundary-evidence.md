# ADR-0008: Runtime recovery 境界条件の機械証跡化

- 状態: 採択
- 日付: 2026-07-09

## 背景

Issue #13 のスリープ復帰、デバイス抜き差し、権限変更後の復旧は、最終的に macOS UI 操作や実デバイス操作を伴う。
一方で、復旧状態の予約、破棄、消費、表示条件は外部 IO なしで検証できる。
人間作業に進む前にこの純粋状態を固定しておかないと、実機検証で失敗したときに状態機械と外部状態の切り分けが難しくなる。

## 決定

- Issue #13 の機械前段は `RuntimeRecoveryState` の回帰テスト、`doctor --probe-hid --json` の保存、`doctor --assert-runtime-ready` の終了コードを正とする。
- `RuntimeRecoveryState` では、スリープ前停止、スリープ中の自動再試行禁止、wake 後の遅延再開、自動復旧可能な失敗の再試行、人間修正が必要な失敗の再試行禁止を固定する。
- 追加で、wake 後の再試行予約を手動停止で破棄すること、既存の失敗再試行予約を sleep で破棄すること、ready になった予約を `.automaticRetry` として消費すること、負の wake retry delay を即時再試行として丸めることを境界条件として固定する。
- wake 後に再試行するのは、sleep 前に runtime が実行中 / 開始中、または自動復旧可能な再試行予約中だった場合に限定する。初期停止、手動停止、設定不正、対象 matcher 未設定など、人間作業や設定修正が必要な停止からは wake retry を予約しない。sleep 通知が重複しても一度記録した wake retry 対象は維持する。
- 常駐 UI の state title と開始 / 緊急停止 / 停止の有効状態は `RuntimeStatusPresenter` に分離し、実行中、停止中、自動再試行中、スリープ待機中を core test で固定する。
- `scripts/collect-completion-evidence.sh` は `doctor --probe-hid --json` を保存し、`runtimeIdentity`、`runtimeReadiness`、`tccStatus`、入力監視プローブ成否、復旧手順、設定検証結果を記録する。
- `doctor --assert-runtime-ready` は、アクセシビリティ未許可、HID probe 未実行、HID probe 失敗、対象デバイス必須時の不一致、設定不正、HID inventory 失敗を非ゼロ終了にし、`runtimeReadiness.failures[].code` に理由を残す。
- `scripts/collect-completion-evidence.sh` は HID probe 未実行と対象デバイス不一致の期待失敗 code を保存し、人間がシステム設定や実機操作へ進む前に runtime ready でない状態を機械判定できることを確認する。

## 影響

- スリープ、デバイス抜き差し、TCC 変更の実機作業前に、状態機械の前提を CI と completion evidence で確認できる。
- 常駐 UI の自動再試行表示が private な AppKit 実装だけに閉じず、実機 UI 操作前に文字列と有効状態の対応を検証できる。
- `doctor --probe-hid --json --assert-runtime-ready` が失敗を返す場合も、TCC、入力監視、対象デバイス不一致、HID probe 未実行の外部ブロッカーと実装バグを `runtimeReadiness.failures[].code` で切り分けやすくなる。
- この ADR と機械証跡だけでは Issue #13 を完了扱いにしない。実機操作ログ、常駐 UI の自動再試行表示、権限復旧導線の実測は引き続き必要である。

## 関連

- [Runtime event 証跡の自動収集と人間作業境界](0006-runtime-event-evidence-automation.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
