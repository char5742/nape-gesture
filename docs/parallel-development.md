# 並列開発運用

この文書は並列投入と所有範囲の運用記録である。
メインスレッド、サブエージェント、PR レビュー、merge 判断の継続方針は [ADR-0004](adr/0004-main-thread-subagent-pr-and-merge-roles.md) に従う。
Issue orchestration と証跡付き close は [ADR-0005](adr/0005-issue-orchestration-and-evidence-close.md) に従う。
製品モデルと実装境界は [ADR-0049](adr/0049-fixed-button-to-finger-count-trackpad-input.md) を正とする。

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
| mouse button 3押下中の連続mouse event量 | 2本指入力 |
| mouse button 4押下中の連続mouse event量 | 3本指入力 |
| mouse button 5押下中の連続mouse event量 | 4本指入力 |
| button 3 / 4 / 5未押下 | 通常mouse入力を変更せず通過 |

結果別mode、方向別action、application別設定をworkstreamにしない。`scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`は低レベルevent familyまたは観測語彙であり、担当分割や製品完成の単位ではない。OS/App結果は同じ入力を受けたmacOSまたは前面applicationの解釈として、入力contractとは別に検証する。

2026-07-12のbaseline `55eb991` はbuttonごとの旧mode選択とfamily別製品経路を残しており、固定製品モデルには未達である。旧mode / familyの実装、テスト、`doctor` capability、`.app`試用を完了済み成果として引き継がず、再利用する低レベル部品ごとに固定mappingへの適合を再確認する。

## メインスレッドの責務

- ゴール要件を維持し、MVP に縮小しない
- button 3→2本指、button 4→3本指、button 5→4本指、未押下pass-throughをIssue間の不変条件にする
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
- 低レベルevent familyの投稿成功をfinger count経路の完了と言い換えない

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

Issue #117を追跡親、Issue #148を全面修正の主Issueにし、固定button→finger countモデルへの移行を次の順で進める。旧Issue #7の単一phase model、forced horizontal scroll、shortcut dry-runに加え、`twoFingerSwipe` / `systemSwipe` / `pinch`のmode分割と`scroll` / `DockSwipe` / `magnification`のfamily別製品経路も移行前baselineであり、新経路の完了扱いにしない。

| 段階 | Issue | 状態と目的 | 主な所有範囲 | 人間作業 |
| --- | --- | --- | --- | --- |
| 1 | #148 | open。共通sample contractと旧mode廃止を固定 | core types、settings schema、migration contract、pure tests | なし |
| 1 | #118 / #128 | close済み基盤を#148で再検証 | logger schema、finger count metadata、session / terminal | なし |
| 1 | #129 | open。2 / 3 / 4本指raw event analyzer / fixture比較 | analyzer、negative fixtures、contract report | なし |
| 2 | #125 | open。純正trackpadの2 / 3 / 4本指contract取得 | 保存済みraw log、finger count、scenario metadata | 純正trackpad物理操作だけ必要 |
| 3 | #119 / #148 | close済みscroll資産を共通contract下のbutton 3→2本指経路として再検証 | 2本指contact / session変換、product tests | なし |
| 3 | #126 | open。button 4→3本指の低レベルcontract | 3本指contact / session変換、contract tests | なし |
| 3 | #127 | open。button 5→4本指の低レベルcontract | 4本指contact / session変換、contract tests | なし |
| 4 | #122 | open。macOS compatibility adapter | version fixture、supported / mismatch判定 | なし |
| 4 | #124 / #130 / #131 / #148 | close済みguard・統合・分離基盤を固定mappingで再検証 | runtime coordinator、禁止経路guard、未押下pass-through、fail closed | なし |
| 4 | #148 | open。settings / GUI / doctorを固定表示へ統合 | 旧mode UI削除、読取専用mapping、migration状態、doctor | なし |
| 5 | #132 | open。finger count変換の性能baseline | 2 / 3 / 4本指別queue / post latency、drop、p95 / p99 | なし |
| 6 | #10 / #9 | open。2本指OS/App結果と3 / 4本指macOS結果の受入 | 低レベルcontractとOS/App結果を分けた証跡 | Nape Pro /純正trackpad物理操作だけ必要 |
| 6 | #146 | open。magnificationの表現可能性を再評価 | pinch / 平行移動fixture、解析、結論の文書反映 | 純正trackpad物理操作だけ必要 |

Issue #148が複数段階に現れるのは、名称変更ではなく設定、GUI、recognizer、session、event builder、migration、doctor、fixture、testsを一貫して直すためである。段階1は所有ファイルが重ならない範囲で並列化する。段階3はfinger count経路ごとのmoduleを分けられるが、button識別、連続量、source kind、timestamp、session終端、未押下pass-throughの共通contractを先に固定する。段階4でメインスレッドが全sliceを統合し、旧mode / family routingの残存、依存方向、CI、runtime証跡をレビューする。一部sliceやclose済みIssueの再利用だけで#148または#117をcloseしない。

`need:human`は#4、#125、#9 / #10 / #146のうち、computer-useで代替できない純正trackpadまたはNape Proの物理操作だけに付ける。Issue全体を人間待ちにせず、logger、analyzer、adapter、fixture test、CI guard、GUI / doctor表示、画面操作を先に完成させ、物理操作を依頼する時点で実行コマンド、保存先、期待値、失敗時の切り分けを確定させる。レビュー待ち、判断待ち、通常のTCC画面操作を`need:human`にしない。

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
- button 3 / 4 / 5をそれぞれ2 / 3 / 4本指へ固定し、設定で変更できないか
- button押下中の連続mouse event量だけを同じfinger countのsessionで処理しているか
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
- button 3 / 4 / 5と2 / 3 / 4本指の対応がruntime全体で保持されているか
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
- 固定button→finger count対応を表示する場合も編集可能なcontrolにしていないか
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
- 純正2 / 3 / 4本指入力と対応するbutton 3 / 4 / 5生成入力を比較できるか
- finger count、低レベルevent family、OS/App結果を別項目として比較できるか
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
- button 3→2本指、button 4→3本指、button 5→4本指、未押下pass-throughの回帰テストが変更範囲に応じてある
- 同一入力fixtureをbutton 3 / 4 / 5へ与えたとき、意味上の差がfinger countだけであることを検証している
- 旧mode / family capability、低レベルevent投稿、`.app`生成だけを固定製品モデルの完成根拠にしていない
- 結果別mode、方向別action、application別設定、AX、対象PID配送、shortcut fallbackを製品経路へ追加していない

## 統合順序

1. Issue #148 / #129: 共通sample・migration contract、finger count analyzer、現行fixture schema
2. Issue #125: 不足する純正trackpad物理contractの取得
3. Issue #119 / #148、#126、#127: button 3 / 4 / 5から2 / 3 / 4本指への変換
4. Issue #148 / #122: settings・GUI・doctor・runtime統合とcompatibility gate
5. Issue #124 / #128 / #130 / #131の既存基盤を#148の固定mappingで再検証
6. Issue #132: 2 / 3 / 4本指の性能baseline
7. Issue #10 / #9 / #146: OS/App結果、magnification境界、物理受入
8. Issue #11 / #13 / #15 / #16: 常駐品質、配布、固定製品モデル全体の完成証跡

## サブエージェント起動時の標準指示

```text
あなたは nape-gesture のサブエージェントです。
担当 Issue だけを扱ってください。
製品モデルはbutton 3→2本指、button 4→3本指、button 5→4本指の固定変換で、未押下時は通常mouseを変更せず通します。
設計正本はADR-0049です。担当差分をIssue #148のend-to-end migrationと矛盾させないでください。
結果別mode、方向別action、application別設定、AX、対象PID配送、shortcut fallbackを製品経路へ追加しないでください。
scroll、DockSwipe、NavigationSwipe、magnificationは低レベルevent familyまたは観測語彙であり、ユーザーmodeや完成単位ではありません。
他のエージェントも同じコードベースで作業しているため、他者の変更を戻さないでください。
所有範囲外のファイルを編集する必要が出た場合は、理由を明記してください。
ユーザーに見えるコメント、ドキュメント、エラー文は日本語で書いてください。
実行した検証と未検証事項を最後に報告してください。
```
