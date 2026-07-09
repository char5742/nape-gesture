# AGENTS.md

このリポジトリで作業するエージェントは、次の方針を守る。

## 基本姿勢

- ユーザーに見える返答、通常コメント、doc comment、Issue / PR コメントは日本語で書く。ログなど英語が自然な出力はそのまま扱ってよい。
- 問題が起きたら後回しにせず、根本原因から対応する。
- テスト失敗、CI 失敗、検証不足を見過ごさない。完了扱いにする前に証跡を残す。
- `chmod` は使わない。読み取り専用ファイルは編集しない。
- Issue / PR コメント投稿、PR review、reply など GitHub 上の書き込みは、可能な限り `gh api` または GitHub app / MCP を使う。

## Grok CLI

- Grok は補助レビュー、UI / UX 発散、文言確認、第三者視点、PR 差分の別観点チェックに積極的に使う。
- Grok の出力は助言であり、完成判定、CI、テスト、runtime 証跡、merge 判断の代替にしない。採否はメインスレッドが責任を持つ。
- レビュー用途では非対話実行を基本にし、`--model grok-4.5`、`--disable-web-search`、`--no-subagents`、`--permission-mode plan`、`--tools ''`、`--max-turns 1` を既定にする。
- 再現性が必要な場合は prompt、stdout、stderr、`grok version`、base/head SHA、対象 diff を `artifacts/grok-review/` に保存する。
- `--json-schema` 実行で `structuredOutputError` が出た場合は構造化レビュー失敗として扱う。プロンプトを絞って 1 回再実行し、それでも失敗する場合は plain/text の助言としてだけ扱い、証跡や gate にしない。
- Grok に編集させる場合は専用 branch / worktree / 所有範囲を分け、メインスレッドが差分をレビューしてから取り込む。
- ローカル skill `$grok-auxiliary-review` が使える場合は、Grok 運用の実行手順として優先的に参照する。詳細方針は [ADR-0027](docs/adr/0027-grok-cli-auxiliary-review.md) と [ADR-0029](docs/adr/0029-grok-operational-surface.md) を正とする。

## Nape Gesture 固有制約

- アプリごとの有効・無効、感度、割り当て設定は追加しない。特定ボタン未押下時は通常マウスとして振る舞う方針を維持する。
- `need:human` は、TCC 操作、純正トラックパッド操作、Nape Pro 実機操作、証明書操作など、人間が実作業しないと進められない項目だけに使う。レビュー待ちや判断待ちには使わない。
- 第三者プロジェクト由来のコード、定数、状態遷移、係数をコピーしない。実装パラメータはこのリポジトリのログと公開 API から再導出する。
- ユーザーが見る挙動、GUI、権限導線、検証手順、完成状態、配布手順を変える場合は README を更新する。更新不要なら PR 本文で理由を明記する。
