# nape-gesture リポジトリ運用記録

継続運用の正は [ADR 一覧](adr/README.md) に保存する。
この文書は、リポジトリ作成、初回 push、Issue 作成時点の実施記録として扱う。

## 現在の状態

2026-07-08 時点で、GitHub リポジトリは作成済み。

- Repository: <https://github.com/char5742/nape-gesture>
- Visibility: private
- Default branch: `main`
- Remote: `origin`
- Baseline commit: `0dacfc5 Initial nape-gesture baseline`
- Rename commit: `6fb14ae Rename project to nape-gesture`

## 初回 push 済みのローカル確認

初回 push 前に次を確認済み。

```sh
git status --short
swift build --scratch-path .build
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture generate-scroll --x 120 --y 0 --steps 3 --momentum-steps 2 --dry-run --log-json > /tmp/generated-scroll.jsonl
.build/debug/nape-gesture analyze-log /tmp/generated-scroll.jsonl
swift build -c release --scratch-path .build
.build/release/nape-gesture bundle-app --out .build/NapeGesture.app --replace
.build/release/nape-gesture verify-bundle .build/NapeGesture.app
```

追加で、`.app` 経由の `doctor --probe-hid --benchmark-events 10000 --json` も実行済み。
現時点の外部ブロッカーは次。

- アクセシビリティ権限は `accessibilityTrusted: false`
- 実機 Nape Pro は未識別で `matchedTargetDeviceCount: 0`
- Spaces / Mission Control の実機挙動は未検証

## Issue 作成

初期 Issue は `docs/github-issues.md` を基準に作成済み。
この件数は bootstrap 時点の記録であり、最新の Issue 数や close 数の正は GitHub 上の Issue 一覧と証跡コメントで確認する。

- Milestone: 5件
- Issue: 16件
- 完了扱いで close 済み: 4件（Issue 1、Issue 2、Issue 3、Issue 7）
- close 済み Milestone: Milestone 1
- bootstrap 時点の運用 label: 15件
- 後続追加 label: `need:human`

Issue、label、milestone の作成・更新・コメント・close は、基本的に `gh api` で行う。
重複を避けるため、再投入時は既存 title / label name / milestone title を先に取得してから差分だけ作成する。
label、milestone、Issue close の継続方針は [ADR-0002](adr/0002-github-labels-milestones-and-issue-close.md) に従う。

## 完了済みとして close する Issue

完了条件を満たした Issue は、証跡コメントを付けて close する。
bootstrap 時点で close 対象にしたものは次。

- Issue 1: リポジトリ名を nape-gesture として公開できる状態にする
- Issue 2: CI で debug / release build とコアテストを必須化する
- Issue 3: PR レビュー用チェックリストを整備する
- Issue 7: スクロールと慣性フェーズの生成ログを純正入力と比較可能にする

以後の close 方針と証跡項目は [ADR-0002](adr/0002-github-labels-milestones-and-issue-close.md) と [ADR-0005](adr/0005-issue-orchestration-and-evidence-close.md) に従う。

## メインスレッドの役割

このスレッドは、Issue 整理、PR レビュー、マージ判断、完成判定の証跡確認に集中する。
実装は `docs/parallel-development.md` の所有範囲に従ってサブエージェントへ分割する。
Issue orchestration と証跡付き close の方針は [ADR-0005](adr/0005-issue-orchestration-and-evidence-close.md) に従う。
