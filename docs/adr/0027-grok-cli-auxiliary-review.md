# ADR-0027: Grok CLI を補助レビューと発散に使う

- 状態: 置換済み
- 日付: 2026-07-09
- 置換先: [ADR-0035](0035-discontinue-grok-independent-audit.md)

## 背景

本環境には `grok` CLI があり、非対話実行で別モデルの視点を得られる。
UI 開発、文言、レビュー観点の抜け、第三者視点の確認では、メインスレッドだけで閉じるよりも異なるモデルの反応を使った方が見落としを減らせる。

一方で、実装責任、テスト実行、PR レビュー、merge 判断、Issue close の責任はメインスレッドが持つ。
Grok の出力は証跡や助言として扱い、検証済み事実や完成判定の代替にしない。

## 決定

- Grok は補助レビュー、UI / UX 発散、第三者視点、PR 差分の別観点チェックに使う。
- GPT-5.5 / Codex は、実装、既存コードとの整合、テスト、CI、PR レビュー、merge、Issue 反映を主担当にする。
- Grok の結果は、採用する前にメインスレッドがコード、docs、テスト、Issue 要件と照合する。
- Grok は `grok -p` または `grok --prompt-file` による非対話実行を基本にする。
- 再現性が必要なレビューでは `--model grok-4.5` のように model を固定する。速度重視で `grok-composer-2.5-fast` を使う場合は、その理由をログまたは PR 本文に残す。
- PR / diff レビューでは、対象差分と base/head commit SHA を `--prompt-file` に明示的に含める。単に「このPR」「この差分」と書くだけのプロンプトは採用しない。
- 再現性が必要なレビューでは、prompt、stdout、stderr を `artifacts/grok-review/` などへ保存する。
- 構造化された結果が必要な場合は `--json-schema` を使い、`structuredOutput` を保存または PR 本文に要約する。`structuredOutputError` が出た場合は構造化レビュー失敗として扱い、必要なら再実行する。
- `structuredOutputError` が出た場合は、プロンプトを短くして 1 回再実行する。それでも失敗する場合は plain/text の助言としてだけ扱い、構造化レビュー証跡や PR gate にしない。
- UI や文言の候補生成では Grok の発散力を使ってよいが、プロダクト方針、アプリ別設定不要、TCC / 実機検証境界、Mac Mouse Fix 由来禁止にはメインスレッドのルールを優先する。
- CI や完成判定では、Grok の意見だけで合格扱いにしない。必ず `swift build`、core tests、script、GitHub Actions、runtime evidence などの機械証跡を使う。
- Grok がファイル編集を行う必要がある場合は、通常のサブエージェントと同様に専用 branch / worktree / 所有範囲を分ける。レビュー用途では読み取り・要約に留める。
- レビュー用途では `--permission-mode plan` を基本にし、編集権限を前提にしない。
- Grok に編集を許す場合でも、専用 branch / worktree で `--permission-mode default` から始め、最初から `--always-approve`、`auto`、`dontAsk`、`bypassPermissions` を使わない。必要な範囲を明示し、メインスレッドが差分をレビューしてから取り込む。

## 確認した CLI 挙動

この環境で確認した結果:

- `grok` は `/opt/homebrew/bin/grok`
- version は `grok 0.2.91 (39d0c6872354) [stable]`
- default model は `grok-4.5`
- available models は `grok-4.5` と `grok-composer-2.5-fast`
- `grok -p <prompt>` / `grok --single <prompt>` は単発実行して標準出力へ返す
- `grok --prompt-file <path>` はプロンプトをファイルから読む
- `--output-format` は `plain`、`json`、`streaming-json`
- `--json-schema <schema>` は JSON schema に従う `structuredOutput` を返す
- `--disable-web-search` は web search / fetch を無効化する
- `--no-subagents` は Grok 側の subagent spawning を無効化する
- `--permission-mode plan` は非対話実行で使用でき、レビュー用途の基本権限として使える
- `--tools ''` は非対話実行で受け付けられる。prompt に含めた差分だけを見るレビューでは、built-in tools を空にする
- `--max-turns <N>` は agent turn 数を制限する
- `grok inspect` はこのディレクトリの設定、permissions、skills、MCP、hooks を表示する
- 非対話実行では未認証 MCP の警告が標準エラーに出る場合がある。レビュー証跡として残す場合は stdout と stderr を分けて保存する

単発の発散例:

```sh
grok -p "Nape Gesture の設定画面で、初心者が迷いやすい UI リスクを日本語で3点だけ挙げてください。" \
  --model grok-4.5 \
  --disable-web-search \
  --no-subagents \
  --permission-mode plan \
  --tools '' \
  --max-turns 1
```

差分レビューを再現可能にする例:

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

構造化出力例:

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

## 影響

- UI、文言、レビュー観点の発散を速くできる。
- 異なるモデルを使うことで、メインスレッドの思い込みを検出しやすくなる。
- ただし、Grok の出力は未検証の助言であり、PR の合否や完成判定の根拠として単独では使えない。
- 非対話 Grok の stderr には環境警告が出ることがあるため、保存ログの扱いを明確にする必要がある。

## 関連

- [メインスレッドとサブエージェントの役割分担、PR レビュー、merge 判断](0004-main-thread-subagent-pr-and-merge-roles.md)
- [Issue による orchestration と証跡付き close 方針](0005-issue-orchestration-and-evidence-close.md)
- [並列開発運用](../parallel-development.md)
- [PR レビューチェックリスト](../pr-review-checklist.md)
