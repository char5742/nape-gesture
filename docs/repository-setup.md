# nape-gesture リポジトリ作成手順

## 現在のブロッカー

2026-07-08 時点では、ローカルの `gh` は `char5742` として認証情報を持っているが、トークンが無効で GitHub API に接続できない。
Codex の GitHub コネクタでは `char5742` の既存リポジトリ閲覧と Issue 作成はできるが、新規リポジトリ作成 API は提供されていない。

そのため、`char5742/nape-gesture` の作成には次のどちらかが必要。

- GitHub Web UI で空リポジトリ `nape-gesture` を作成する
- `gh auth login -h github.com` で再認証し、`gh repo create char5742/nape-gesture` を実行できる状態にする

## 初回 push 前のローカル確認

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

## リポジトリ作成後の操作

```sh
git remote add origin git@github.com:char5742/nape-gesture.git
git add .
git commit -m "Initial nape-gesture baseline"
git push -u origin main
```

HTTPS remote を使う場合:

```sh
git remote add origin https://github.com/char5742/nape-gesture.git
git push -u origin main
```

## Issue 作成

初期 Issue は `docs/github-issues.md` を基準に作成する。
GitHub コネクタで `char5742/nape-gesture` が見えるようになったら、Issue 作成はコネクタを優先する。

ラベルは先に次を作成する。

- `area:core`
- `area:runtime`
- `area:hid`
- `area:verification`
- `area:ui`
- `area:release`
- `area:docs`
- `type:feature`
- `type:bug`
- `type:research`
- `type:qa`
- `priority:p0`
- `priority:p1`
- `parallel:ready`
- `blocked:external`

## メインスレッドの役割

このスレッドは、Issue 整理、PR レビュー、マージ判断、完成判定の証跡確認に集中する。
実装は `docs/parallel-development.md` の所有範囲に従ってサブエージェントへ分割する。
