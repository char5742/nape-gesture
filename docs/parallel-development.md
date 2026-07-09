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

2026-07-08 時点で、Issue 1、Issue 2、Issue 3、Issue 7 は完了済み。
次は次の順でサブエージェントへ分ける。

| Issue | 目的 | 所有範囲 | 衝突リスク | 完了確認 |
| --- | --- | --- | --- | --- |
| Issue 14 | 入力遅延と CPU 使用率の測定基準を固定する | `Sources/nape-gesture/BenchmarkCommand.swift`, `Sources/nape-gesture/CPUSampleCommand.swift`, `docs/verification.md`, `docs/pr-review-checklist.md` | 低 | `swift build --scratch-path .build`, `.build/debug/nape-gesture-core-tests`, `.build/debug/nape-gesture benchmark --events 200000 --json`, `.build/debug/nape-gesture doctor --benchmark-events 50000 --json`, `.build/debug/nape-gesture sample-cpu --pid <pid> --json --assert-baseline` |
| Issue 5 | HID 対象デバイスとイベントタップ入力の紐づけを厳密化する | `Sources/NapeGestureCore/`, `Sources/nape-gesture/NapeGestureRuntime.swift`, `Sources/nape-gesture/HIDInputMonitor.swift`, `Sources/nape-gesture/SettingsWindowController.swift` | 中 | `swift build --scratch-path .build`, `.build/debug/nape-gesture-core-tests`, `.build/debug/nape-gesture check-config --config <検証設定> --probe-hid` |
| Issue 6 | 元入力抑制を Reference Target App とログ解析で検証可能にする | `Sources/nape-gesture/ReferenceTargetApp.swift`, `Sources/nape-gesture/AnalyzeTargetLogCommand.swift`, `docs/verification.md` | 中 | `swift build --scratch-path .build`, `.build/debug/nape-gesture target --out <target-log>`, `.build/debug/nape-gesture analyze-target-log <target-log>` |
| Issue 9 | Spaces / Mission Control の実機挙動マトリクスを作る | `Sources/nape-gesture/SystemBehaviorTestCommand.swift`, `docs/verification.md`, `docs/system-behavior-matrix.md` | 中 | `.build/debug/nape-gesture system-test list`, `.build/debug/nape-gesture system-test run --scenario space-left --target finder --dry-run --log-json --out /tmp/system-space-left.jsonl`, `.build/debug/nape-gesture analyze-log /tmp/system-space-left.jsonl` |
| Issue 4 | Nape Pro HID profile を実機ログから確定する | `docs/verification.md`, `Fixtures/`, `logs/` | 低 | `.build/debug/nape-gesture devices --all --json`, `.build/debug/nape-gesture hid-log --vendor-id <ID> --product-id <ID> --usage-page <ID> --usage <ID> --duration 10`, `.build/debug/nape-gesture analyze-hid-log <log>`, `.build/debug/nape-gesture doctor --config <設定> --probe-hid --json` |

Issue 4 と Issue 9 は実機と権限状態に依存するため、実機なしの dry-run だけで完了扱いにしない。

## Grok CLI による補助レビュー

Grok CLI の使い分けは [ADR-0027](adr/0027-grok-cli-auxiliary-review.md) を正とする。
実行時の短いルールは repo 直下の `AGENTS.md`、再利用可能な手順はローカル Codex skill `$grok-auxiliary-review` にも置く。
この 3 層の役割分担は [ADR-0029](adr/0029-grok-operational-surface.md) を正とする。
メインスレッドは GPT-5.5 / Codex として実装、テスト、PR レビュー、merge 判断、Issue 反映を主担当にする。
Grok は別モデルの第二視点として、UI / UX、文言、レビュー観点の抜け、第三者視点の確認に使う。

確認済みの非対話実行:

```sh
grok -p "Nape Gesture の設定画面で、初心者が迷いやすいUIリスクを日本語で3点だけ挙げてください。" \
  --model grok-4.5 \
  --disable-web-search \
  --no-subagents \
  --permission-mode plan \
  --tools '' \
  --max-turns 1
```

差分レビューは入力を明示する:

```sh
tmpdir=$(mktemp -d /tmp/grok-review.XXXXXX)
artifact_dir=${GROK_REVIEW_ARTIFACT_DIR:-artifacts/grok-review/$(date +%F-%H%M%S)}
mkdir -p "$artifact_dir"
grok version > "$artifact_dir/grok-version.txt"
git fetch origin main
base_ref=$(git rev-parse origin/main)
head_ref=$(git rev-parse HEAD)
{
  printf '%s\n' "以下の git diff だけを第三者視点でレビューしてください。外部ファイルは読まないでください。"
  printf 'base: %s\nhead: %s\n' "$base_ref" "$head_ref"
  git diff "$base_ref...$head_ref" -- <対象ファイル>
} > "$tmpdir/prompt.md"
cp "$tmpdir/prompt.md" "$artifact_dir/prompt.md"
grok --prompt-file "$tmpdir/prompt.md" \
  --model grok-4.5 \
  --disable-web-search \
  --no-subagents \
  --permission-mode plan \
  --tools '' \
  --max-turns 1 \
  > "$artifact_dir/stdout.txt" \
  2> "$artifact_dir/stderr.log"
```

構造化されたレビュー観点が必要な場合:

```sh
tmpdir=$(mktemp -d /tmp/grok-review.XXXXXX)
artifact_dir=${GROK_REVIEW_ARTIFACT_DIR:-artifacts/grok-review/$(date +%F-%H%M%S)}
mkdir -p "$artifact_dir"
grok version > "$artifact_dir/grok-version.txt"
git fetch origin main
base_ref=$(git rev-parse origin/main)
head_ref=$(git rev-parse HEAD)
{
  printf '%s\n' "以下の git diff だけをレビューし、レビュー観点を最大3点返してください。外部ファイルは読まないでください。問題がなければ空配列にしてください。"
  printf 'base: %s\nhead: %s\n' "$base_ref" "$head_ref"
  git diff "$base_ref...$head_ref" -- <対象ファイル>
} > "$tmpdir/prompt.md"
cp "$tmpdir/prompt.md" "$artifact_dir/prompt.md"
grok --prompt-file "$tmpdir/prompt.md" \
  --model grok-4.5 \
  --disable-web-search \
  --no-subagents \
  --permission-mode plan \
  --tools '' \
  --max-turns 1 \
  --output-format json \
  --json-schema '{"type":"object","properties":{"findings":{"type":"array","items":{"type":"string"},"maxItems":3}},"required":["findings"],"additionalProperties":false}' \
  > "$artifact_dir/stdout.json" \
  2> "$artifact_dir/stderr.log"
```

運用ルール:

- Grok の出力は助言であり、機械証跡や完成判定の代替にしない
- Grok のレビューを採用する前に、メインスレッドが Issue 要件、コード、docs、テストと照合する
- 再現性が必要なレビューでは model と CLI version を固定・保存し、base/head SHA と対象差分を prompt-file に含め、prompt / stdout / stderr を保存する
- レビュー用途では `--disable-web-search`、`--no-subagents`、`--permission-mode plan`、`--tools ''`、`--max-turns 1` を基本にし、必要以上に外部状態や編集権限を与えない
- 非対話実行では MCP 警告が stderr に出る場合があるため、証跡にする場合は stdout と stderr を分けて保存する
- Grok に編集させる場合は、通常のサブエージェントと同じく専用 branch / worktree / 所有範囲を分け、`--permission-mode default` から始める。最初から `--always-approve`、`auto`、`dontAsk`、`bypassPermissions` を使わない
- UI 発散では Grok の候補を使ってよいが、アプリ別設定不要、TCC 境界、Mac Mouse Fix 由来禁止、完成判定の証跡要件はメインスレッドのルールを優先する

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
