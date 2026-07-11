# 並列開発運用

この文書は並列投入と所有範囲の運用記録である。
メインスレッド、サブエージェント、PR レビュー、merge 判断の継続方針は [ADR-0004](adr/0004-main-thread-subagent-pr-and-merge-roles.md) に従う。
Issue orchestration と証跡付き close は [ADR-0005](adr/0005-issue-orchestration-and-evidence-close.md) に従う。

## 基本方針

メインスレッドは、Issue 整理、PR レビュー、マージ判断、完成判定の証跡確認に集中する。
実装はサブエージェントに分割し、各サブエージェントは明確な所有範囲を持つ。
現在の baseline は `main` に push 済みなので、サブエージェントは Issue ごとの `codex/issue-XXX-*` ブランチで作業する。
コード編集を伴うサブエージェントは、Issue ごとの専用 `git worktree` を使う。
メインスレッドの checkout は PR レビュー、CI 確認、merge 後の `main` 同期用に保ち、サブエージェントの実装作業には共有しない。
同じ checkout を複数エージェントで共有すると、branch 切り替えや未コミット差分の取り合いが起きるため、並列化時は所有ファイルだけでなく worktree も分離する。
メインスレッドは直接実装を抱え込みすぎず、Issue 作成、PR レビュー、CI と証跡確認、マージ判断を主担当にする。

## メインスレッドの責務

- ゴール要件を維持し、MVP に縮小しない
- GitHub Issue の粒度、依存関係、優先度を管理する
- PR の差分をレビューし、仕様逸脱、入力安全性、テスト不足を指摘する
- CI、ローカル検証、実機検証の証跡を確認する
- 複数 PR の統合順序を決める
- 完成判定を Issue 単位ではなくゴール全体で行う
- `Package.swift`、CLI 入口、README、docs の最終統合を持つ

## サブエージェントの責務

- 割り当てられた Issue だけを実装する
- 割り当てられた専用 worktree と branch だけで作業する
- 自分の所有範囲外のファイルを不用意に編集しない
- 他エージェントの変更を戻さない
- 変更ファイル、実行した検証、未検証事項を PR 本文に明記する
- 実機が必要な項目は、モックや狭いテストだけで完了扱いにしない

## 推奨ブランチ

- `codex/issue-002-ci`
- `codex/issue-003-review-checklist`
- `codex/issue-004-nape-hid-profile`
- `codex/issue-005-device-association`
- `codex/issue-009-system-behavior-matrix`
- `codex/issue-011-permission-runtime-identity`
- `codex/issue-014-performance-baseline`
- `codex/issue-015-release-bundle`

## 次の並列投入候補

2026-07-11時点ではIssue #117を親にし、trackpad driver上位出力eventへの移行を次の順で進める。旧Issue #7の単一phase model、forced horizontal scroll、shortcut dry-runは移行前baselineであり、新経路の完了扱いにしない。

| 段階 | Issue | 目的 | 主な所有範囲 | 人間作業 |
| --- | --- | --- | --- | --- |
| 1 | #118 | listen-only raw event logger | logger CLI、raw schema、metadata、tests | なし |
| 1 | #128 | output session model / monotonic clock | core lifecycle、sequence、terminal state、pure tests | なし |
| 1 | #129 | raw event analyzer / fixture比較 | analyzer、negative fixtures、contract report | なし |
| 2 | #125 | 純正trackpad contract取得 | 保存済みraw log、scenario metadata | 純正trackpad物理操作だけ必要 |
| 3 | #119 | scroll + companion gesture / momentum | scroll family adapter、session state | なし |
| 3 | #126 | DockSwipe | Spaces / Mission Control family adapter | なし |
| 3 | #127 | NavigationSwipe / magnification | page / zoom family adapter | なし |
| 4 | #122 | macOS compatibility adapter | version fixture、supported / mismatch判定 | なし |
| 4 | #130 | daemon統合 / fail closed | runtime output coordinator、停止・復帰 | なし |
| 4 | #131 | product / diagnostic分離 | module境界、CI guard、旧CI移行 | なし |
| 5 | #132 | output性能baseline | queue / post latency、drop、p95 / p99 | なし |
| 6 | #9 / #10 | 最終実機受入 | system-wide挙動、画面証跡、体感差分 | Nape Pro /純正trackpad物理操作だけ必要 |

段階1は所有ファイルが重ならない範囲で並列化する。段階3もevent familyごとのmoduleを分けて並列化できる。段階4は共通interfaceが固まってから統合し、メインスレッドが依存方向、CI、runtime証跡をレビューする。

`need:human`は#125と#9 / #10の物理操作にだけ付ける。logger、analyzer、adapter、fixture test、CI guard、GUI / doctor表示を先に完成させ、物理操作を依頼する時点で実行コマンドと保存先を確定させる。

## 独立モデル監査

[ADR-0035](adr/0035-discontinue-grok-independent-audit.md)により、Grok CLIによる独立監査、補助レビュー、発散、PR差分レビューは行わない。
メインスレッドが設計、実装、レビュー、merge判断、Issue反映の責任を持つ。並列化が必要な場合は、同じリポジトリ方針と証跡契約を共有する通常のCodexサブエージェントへ、所有範囲を限定して委譲する。

`artifacts/grok-review/`へ新しい証跡を追加せず、既存のGrok出力も現在の設計判断、PR review、完成判定、CI gateには使わない。

## Computer Use による GUI 操作

Computer Use の使い分けは [ADR-0030](adr/0030-computer-use-gui-operation-evidence.md) を正とする。
メインスレッドは、`.app` 起動、設定ウィンドウ、メニューバー `NG`、System Settings pane 表示、スクリーンショット取得など、ローカル Mac UI が必要な作業を computer-use で前進させる。

運用ルール:

- 専用 CLI、GitHub / browser / app plugin、スクリプトで完結する場合はそれらを優先する
- computer-use で代替できる GUI 目視や UI 操作は、すぐ `need:human` にしない
- TCC、アクセシビリティ、入力監視など OS セキュリティ設定を変更する最終操作の直前には、具体的な操作内容とリスクを説明してユーザー確認を取る
- 画面証跡は `doctor --json`、runtime log、CI、analyzer の代替ではなく、対応づけて completion evidence に残す

## 衝突しにくい所有範囲

### Core Agent

対象:

- `Sources/NapeGestureCore/`
- `Sources/nape-gesture-core-tests/main.swift`

主な Issue:

- GestureRecognizer
- MomentumEngine
- ScrollGenerationPlanner
- SettingsValidator
- TargetDeviceGate

レビュー観点:

- 通常入力通過を壊していないか
- ジェスチャーボタン中だけ処理しているか
- 終了後に必ず idle へ戻るか
- テストが狭すぎないか

### Runtime Agent

対象:

- `Sources/nape-gesture/NapeGestureRuntime.swift`
- `Sources/nape-gesture/NapeGestureDaemon.swift`
- `Sources/nape-gesture/EventPoster.swift`
- `Sources/nape-gesture/EventLogger.swift`
- `Sources/nape-gesture/CGEventUtilities.swift`
- `Sources/nape-gesture/KillSwitchShortcut.swift`

主な Issue:

- イベントタップ
- 元入力抑制
- 生成イベント再入力防止
- キルスイッチ
- 権限喪失時の停止

レビュー観点:

- 入力ループを起こさないか
- 自前生成イベントを無視できるか
- 例外時に安全停止するか
- Accessibility 依存を曖昧にしていないか

### HID Agent

対象:

- `Sources/nape-gesture/HIDInputMonitor.swift`
- `Sources/nape-gesture/HIDLogCommand.swift`
- `Sources/nape-gesture/HIDDeviceMatch.swift`
- `Sources/nape-gesture/DeviceLister.swift`
- `Sources/nape-gesture/DeviceInventory.swift`
- `Sources/nape-gesture/SharedTargetDeviceGate.swift`

主な Issue:

- Nape Pro 実機識別
- usage/value range 解析
- 対象デバイス照合
- 入力監視権限の扱い

レビュー観点:

- 全デバイス誤適用を避けているか
- 複合 HID を見落としていないか
- 対象未検出時に安全停止するか
- 実機ログに基づく設定になっているか

### UI Agent

対象:

- `Sources/nape-gesture/StatusApp.swift`
- `Sources/nape-gesture/SettingsWindowController.swift`
- `Sources/nape-gesture/ReferenceTargetApp.swift`
- `Sources/nape-gesture/BundleAppCommand.swift`
- `Sources/nape-gesture/BundleVerifier.swift`

主な Issue:

- 設定 UI
- 権限導線
- Reference Target App
- 常駐 UI の状態表示
- 通常 GUI アプリ起動

レビュー観点:

- アプリ別設定を増やしていないか
- 設定保存前に不正値を止めるか
- `.app` が Dock に表示される通常 GUI アプリとして起動するか
- 起動時と Dock 再オープン時に設定ウィンドウを表示できるか
- メニューバーの `NG` 常駐 UI を維持しているか
- 権限付与対象が分かるか
- UI で実行状態と自動再試行状態が分かるか

### Verification Agent

対象:

- `docs/verification.md`
- `docs/requirements.md`
- `Fixtures/`
- `Sources/nape-gesture/SystemBehaviorTestCommand.swift`
- `Sources/nape-gesture/AnalyzeLogCommand.swift`
- `Sources/nape-gesture/CompareLogCommand.swift`
- `Sources/nape-gesture/AnalyzeTargetLogCommand.swift`
- `Sources/nape-gesture/AnalyzeHIDLogCommand.swift`
- `Sources/nape-gesture/BenchmarkCommand.swift`

主な Issue:

- System Behavior Test
- ログ比較
- 実機検証マトリクス
- 性能測定
- 完成判定証跡

レビュー観点:

- ログ形式が同じか
- 純正入力と生成イベントを比較できるか
- 実機が必要な項目を dry-run で済ませていないか
- 失敗条件と回避策が残っているか

### Release Agent

対象:

- `Package.swift`
- `README.md`
- `LICENSE`
- `THIRD_PARTY_NOTICES.md`
- `Sources/nape-gesture/BundleAppCommand.swift`
- `Sources/nape-gesture/BundleVerifier.swift`
- `.github/workflows/`

主な Issue:

- CI
- `.app` バンドル
- 署名/公証
- ライセンス同梱
- 配布手順

レビュー観点:

- debug/release 両方で壊れていないか
- `.app` の権限付与導線が正しいか
- ライセンスが同梱されているか
- 署名や公証の未決事項が明記されているか

## PR レビューゲート

PR は最低限次を満たすまでマージしない。

- 対応 Issue が明記されている
- 変更ファイルの所有範囲が説明されている
- コード、Package、workflow に影響する変更では `swift build` が成功している
- コード、Package、workflow に影響する変更では `nape-gesture-core-tests` が成功している
- docs/config のみの変更では、変更対象に合った検証と Swift build を省略した理由が明記されている
- runtime / HID / Accessibility に触る場合は、実機未検証か実機検証済みかが明記されている
- 既知の未完了事項を「完了」と言い換えていない

## 統合順序

1. Issue 1: repository foundation
2. Issue 2: CI
3. Issue 3: PR review checklist
4. Issue 7: phase encoding correctness
5. Issue 5: device association
6. Issue 11: permission/runtime identity
7. Issue 4: Nape Pro HID profile
8. Issue 8-10: calibration and system behavior verification
9. Issue 12-14: resident app robustness and performance
10. Issue 15-16: release and completion evidence

## サブエージェント起動時の標準指示

```text
あなたは nape-gesture のサブエージェントです。
担当 Issue だけを扱ってください。
他のエージェントも同じコードベースで作業しているため、他者の変更を戻さないでください。
所有範囲外のファイルを編集する必要が出た場合は、理由を明記してください。
ユーザーに見えるコメント、ドキュメント、エラー文は日本語で書いてください。
実行した検証と未検証事項を最後に報告してください。
```
