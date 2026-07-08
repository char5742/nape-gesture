# AGENTS.md

このファイルは、このリポジトリ全体に適用する Codex / サブエージェント向けの運用指示です。より深い階層にある `AGENTS.md` は、その配下でこの内容を補足または上書きします。

## 最優先ルール

- ユーザーに見える返答、通常コメント、doc comment、ドキュメントは日本語で書く。ログ、コマンド名、API 名など英語が必要な箇所はそのまま扱う。
- 問題が発生した場合は後回しにせず、根本原因を確認してから対応する。
- テスト失敗、CI 失敗、検証不足、実機未確認を完了扱いにしない。
- `chmod` は使用しない。実行ビットが必要な運用にせず、スクリプトは `sh scripts/<name>.sh` で実行する。
- 読み取り専用ファイルは編集しない。
- 既存の未コミット変更はユーザーまたは別エージェントの作業として扱い、明示依頼なしに戻さない。
- GitHub の Issue / PR コメント投稿、close、reply は、原則として `gh api` を使う。`gh pr comment` などで reply や review thread 文脈が欠ける場合は使わない。

## Codex ハーネス運用

- 実装を並列化する場合は、[docs/parallel-development.md](docs/parallel-development.md) と [docs/adr/0004-main-thread-subagent-pr-and-merge-roles.md](docs/adr/0004-main-thread-subagent-pr-and-merge-roles.md) を正とする。
- コード編集を伴うサブエージェントは、原則として Issue ごとの専用 `git worktree` と `codex/issue-XXX-*` ブランチで作業する。
- メイン checkout は PR レビュー、CI 確認、merge 後の `main` 同期に使い、複数エージェントの実装作業で共有しない。
- 作業範囲外のファイルを変更する必要がある場合は、理由を PR 本文または最終報告に明記する。
- PR は原則 draft で作成または更新し、ready 化と merge 判断はメインスレッドが行う。
- Issue close は [docs/adr/0005-issue-orchestration-and-evidence-close.md](docs/adr/0005-issue-orchestration-and-evidence-close.md) に従い、必要な証跡コメントを残してから行う。

## 検証ゲート

- コード、`Package.swift`、workflow に影響する変更では、少なくとも `swift build --scratch-path .build` と `.build/debug/nape-gesture-core-tests` を実行する。
- release / bundle / 配布に影響する変更では、`swift build -c release --scratch-path .build` と bundle 検証も実行する。
- docs/config のみの変更では Swift build を省略できるが、`git diff --check`、YAML parse、リンク確認など変更対象に合う検証を行い、省略理由を明記する。
- 由来、配布物、ライセンス、README、PR template、review checklist に影響する変更では `sh scripts/check-provenance.sh` を実行する。
- 実機、TCC、Nape Pro、Spaces / Mission Control、Developer ID 署名、公証が必要な項目は、dry-run や fixture だけで完了扱いにしない。

## 由来と安全性

- README と由来ガードで定めた外部プロジェクト由来のコード、定数、状態遷移、係数、調整値をコピーしない。
- 入力安全性を最優先にし、通常クリック、通常ドラッグ、通常ホイールの通過、元入力抑制、生成イベント再入力防止、キルスイッチを壊さない。
- `git reset --hard`、`git checkout -- <path>`、`git clean`、強制 push、未確認の大量削除など破壊的操作は、ユーザーの明示依頼なしに実行しない。

## 参照する正本

- 並列開発: [docs/parallel-development.md](docs/parallel-development.md)
- PR レビュー: [docs/pr-review-checklist.md](docs/pr-review-checklist.md)
- 完成判定: [docs/completion-checklist.md](docs/completion-checklist.md)
- 検証方針: [docs/verification.md](docs/verification.md)
- ADR 一覧: [docs/adr/README.md](docs/adr/README.md)
