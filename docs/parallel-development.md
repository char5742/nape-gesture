# 並列開発運用

この文書は並列投入と所有範囲の運用記録である。
メインスレッド、サブエージェント、PR レビュー、merge 判断の継続方針は [ADR-0004](adr/0004-main-thread-subagent-pr-and-merge-roles.md) に従う。
Issue orchestration と証跡付き close は [ADR-0005](adr/0005-issue-orchestration-and-evidence-close.md) に従う。
製品モデルと実装境界は [ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md) を正とする。

## 基本方針

メインスレッドは、Issue 整理、PR レビュー、マージ判断、完成判定の証跡確認に集中する。
実装はサブエージェントに分割し、各サブエージェントは明確な所有範囲を持つ。
現在の baseline は `main` に push 済みなので、サブエージェントは Issue ごとの `codex/issue-XXX-*` ブランチで作業する。
コード編集を伴うサブエージェントは、Issue ごとの専用 `git worktree` を使う。
メインスレッドの checkout は PR レビュー、CI 確認、merge 後の `main` 同期用に保ち、サブエージェントの実装作業には共有しない。
同じ checkout を複数エージェントで共有すると、branch 切り替えや未コミット差分の取り合いが起きるため、並列化時は所有ファイルだけでなく worktree も分離する。
メインスレッドは直接実装を抱え込みすぎず、Issue 作成、PR レビュー、CI と証跡確認、マージ判断を主担当にする。

### 固定製品モデル

Issue分割と完成判定は、次の固定対応を変えない。

| Nape Pro入力 | 製品が生成するtrackpad入力 |
| --- | --- |
| mouse button 3押下中の連続mouse event量 | `twoFingerScrollSwipe`: type 22 scroll + 必要なtype 29 companion |
| mouse button 4押下中の連続mouse event量 | `threeFingerSystemSwipe`: type 30 `DockSwipe` motion 1 / 2 |
| mouse button 5押下中の連続mouse event量 | `pinch`（4本指system pinch相当）: type 30 `DockSwipe` motion 4 |
| button 3 / 4 / 5未押下 | 通常mouse入力を変更せず通過 |

2 / 3 / 4本指はraw contact数やgeneric `fingerCount` transportではなく、固定GestureClassの説明である。class固有adapterが異なるevent type、field、phase、companion、単位変換を生成することを前提に分担する。結果別mode、方向別action、application別設定をworkstreamにせず、OS/App結果はmacOSまたは前面applicationの解釈としてclass固有contractと別に検証する。

2026-07-12のbaseline `55eb991` はbuttonごとの旧mode選択を残していた移行前履歴であり、現在の実装状態を示さない。旧mode test、個別familyの投稿、`doctor`、`.app`試用だけを完成根拠にせず、固定button→GestureClass→class固有ProductOutputのend-to-end到達性を確認する。

## メインスレッドの責務

- ゴール要件を維持し、MVP に縮小しない
- button 3→`twoFingerScrollSwipe`、button 4→`threeFingerSystemSwipe`、button 5→`pinch`、未押下pass-throughをIssue間の不変条件にする
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
- class固有eventの一部を投稿できただけで固定GestureClass経路の完了と言い換えない

## 推奨ブランチ

- `codex/issue-002-ci`
- `codex/issue-003-review-checklist`
- `codex/issue-004-nape-hid-profile`
- `codex/issue-005-device-association`
- `codex/issue-009-system-behavior-matrix`
- `codex/issue-011-permission-runtime-identity`
- `codex/issue-014-performance-baseline`
- `codex/issue-015-release-bundle`

## 現在の並列投入

Issue #117 / #148を使った段階表とgeneric finger-count移行計画は履歴であり、現在の投入順や完成判定には使わない。現在は固定GestureClass runtime、class固有ProductOutput、読取専用GUI、canonical migration、doctorを前提に、競合しない安定化範囲だけをworkerへ割り当てる。

| 担当 | 現在の所有範囲 | 統合条件 | 人間作業 |
| --- | --- | --- | --- |
| Core安定化 | source sample、session、single terminal、sleep / wake / retry | 3 GestureClassとpassthroughの回帰test | なし |
| ProductOutput安定化 | scroll、DockSwipe motion 1 / 2、DockSwipe motion 4、部分失敗 | class固有event contractとfail closed test | なし |
| App安定化 | migration、設定保存、GUI、doctor、bundle、runtime identity | debug / release bundleとGUI smoke | なし |
| 物理受入 | 純正trackpad / Nape Proの同一binary比較 | class固有contractとOS/App結果を分離した証跡 | 物理操作だけ必要 |

`need:human`はcomputer-useで代替できない純正trackpadまたはNape Proの物理操作だけに付ける。Issue全体を人間待ちにせず、logger、analyzer、adapter、fixture test、GUI / doctor表示、画面操作を先に完成させ、物理操作を依頼する時点で実行コマンド、保存先、期待値、失敗時の切り分けを確定させる。レビュー待ち、判断待ち、通常のTCC画面操作を`need:human`にしない。

## 独立モデル監査

[ADR-0035](adr/0035-discontinue-grok-independent-audit.md)により、Grok CLIによる独立監査、補助レビュー、発散、PR差分レビューは行わない。
メインスレッドが設計、実装、レビュー、merge判断、Issue反映の責任を持つ。並列化が必要な場合は、同じリポジトリ方針と証跡契約を共有する通常のCodexサブエージェントへ、所有範囲を限定して委譲する。

`artifacts/grok-review/`へ新しい証跡を追加せず、既存のGrok出力も現在の設計判断、PR review、完成判定、CI gateには使わない。

## Computer Use による GUI 操作

Computer Use の使い分けは [ADR-0030](adr/0030-computer-use-gui-operation-evidence.md) を正とする。
メインスレッドは、`.app` 起動、設定ウィンドウ、メニューバーのsystem symbol、System Settings pane 表示、スクリーンショット取得など、ローカル Mac UI が必要な作業を computer-use で前進させる。

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
- button 3 / 4 / 5をそれぞれ3つの固定GestureClassへ接続し、設定で変更できないか
- button押下中の連続mouse event量を同じGestureClassとsession IDで処理しているか
- 未押下時は通常mouse入力を変更せず通しているか
- 終了後に必ず idle へ戻るか
- 結果別modeや低レベルevent familyを入力モデルとして持ち込んでいないか
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
- button 3 / 4 / 5と固定GestureClassの対応がruntime全体で保持されているか
- AX、対象PID配送、shortcut fallback、application別分岐が製品経路へ入っていないか
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
- buttonごとのmode / family選択、方向別action、感度、割り当てを増やしていないか
- 固定button→GestureClass対応を読取専用で表示しているか
- 設定保存前に不正値を止めるか
- `.app` が Dock に表示される通常 GUI アプリとして起動するか
- 起動時と Dock 再オープン時に設定ウィンドウを表示できるか
- メニューバーのsystem symbolによる常駐 UI を維持しているか
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
- 純正trackpadの各GestureClassと対応するbutton 3 / 4 / 5生成入力を比較できるか
- GestureClass、class固有event contract、OS/App結果を別項目として比較できるか
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
- 3つの固定GestureClassと未押下pass-throughの回帰テストが変更範囲に応じてある
- 同一source fixtureでX/Y量、符号、順序、timestampを保持しながら、class固有のevent type、field、phase、companion、単位変換を検証している
- 旧mode / family capability、低レベルevent投稿、`.app`生成だけを固定製品モデルの完成根拠にしていない
- 結果別mode、方向別action、application別設定、AX、対象PID配送、shortcut fallbackを製品経路へ追加していない

## 統合順序

1. Coreのsource sample、session、terminal、recovery回帰を固定する。
2. 3つのclass固有ProductOutputとevent作成・投稿の部分失敗を固定する。
3. migration、設定保存、GUI、doctor、bundle、runtime identityを同じcontractへ揃える。
4. メインスレッドが全差分をreviewし、debug / release / sanitizer / bundle / GUI検証を通す。
5. 同一release binaryで純正trackpadとNape Proの物理受入を行い、OS/App結果とcontract判定を分離する。

## サブエージェント起動時の標準指示

```text
あなたは nape-gesture のサブエージェントです。
担当 Issue だけを扱ってください。
製品モデルはbutton 3→`twoFingerScrollSwipe`、button 4→`threeFingerSystemSwipe`、button 5→`pinch`の固定GestureClass接続で、未押下時は通常mouseを変更せず通します。
設計正本はADR-0049です。2 / 3 / 4本指をraw contact数やgeneric fingerCount transportとして扱わないでください。
結果別mode、方向別action、application別設定、AX、対象PID配送、shortcut fallbackを製品経路へ追加しないでください。
各GestureClassはclass固有のevent type、field、phase、companion、単位変換を使います。これはユーザーmodeやapplication別routingではありません。
他のエージェントも同じコードベースで作業しているため、他者の変更を戻さないでください。
所有範囲外のファイルを編集する必要が出た場合は、理由を明記してください。
ユーザーに見えるコメント、ドキュメント、エラー文は日本語で書いてください。
実行した検証と未検証事項を最後に報告してください。
```
