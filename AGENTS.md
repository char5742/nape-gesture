# AGENTS.md

このリポジトリで作業するエージェントは、次の方針を守る。

## 基本姿勢

- ユーザーに見える返答、通常コメント、doc comment、Issue / PR コメントは日本語で書く。ログなど英語が自然な出力はそのまま扱ってよい。
- 問題が起きたら後回しにせず、根本原因から対応する。
- テスト失敗、CI 失敗、検証不足を見過ごさない。完了扱いにする前に証跡を残す。
- `chmod` は使わない。読み取り専用ファイルは編集しない。
- Issue / PR コメント投稿、PR review、reply など GitHub 上の書き込みは、可能な限り `gh api` または GitHub app / MCP を使う。

## 独立モデル監査

- Grok CLIによる独立監査、補助レビュー、UI / UX発散、文言確認、PR差分レビューは行わない。
- Grokの実行結果を設計判断、Issue要件、PR review、完成判定、CI gate、runtime証跡へ使わない。
- 設計、実装、レビュー、merge判断はメインスレッドが責任を持ち、並列化には通常のCodexサブエージェントだけを使う。
- `artifacts/grok-review/`へ新しい監査証跡を追加しない。旧証跡が存在しても現在の判断根拠にはしない。
- 詳細方針は[ADR-0035](docs/adr/0035-discontinue-grok-independent-audit.md)を正とする。

## Computer Use

- 専用 CLI、GitHub / browser / app plugin、スクリプトで完結する作業はそれらを優先する。
- ローカル Mac アプリ UI の読み取り、クリック、入力、スクロール、ドラッグ、画面証跡取得が必要な場合は computer-use を積極的に使う。
- `.app` 起動、設定ウィンドウ、メニューバー `NG`、System Settings pane の表示確認、スクリーンショット取得は computer-use で前進させる。
- TCC、アクセシビリティ、入力監視、VPN、OS セキュリティなど local system settings の変更直前には、具体的な操作内容とリスクを説明してユーザー確認を取る。
- computer-use で代替できる GUI 操作は `need:human` にしない。物理デバイス操作、ユーザー本人しか通せない認証、秘密情報入力など、エージェントが代替できない作業だけを `need:human` に残す。
- computer-use の画面証跡は、ログ、`doctor --json`、runtime evidence、CI の代替にしない。詳細方針は [ADR-0030](docs/adr/0030-computer-use-gui-operation-evidence.md) を正とする。

## Nape Gesture 固有制約

- アプリごとの有効・無効、感度、割り当て設定は追加しない。特定ボタン未押下時は通常マウスとして振る舞う方針を維持する。
- `need:human` は、computer-use と直前確認でも代替できない TCC 操作、純正トラックパッド操作、Nape Pro 実機操作、証明書操作など、人間が実作業しないと進められない項目だけに使う。レビュー待ちや判断待ちには使わない。
- 第三者プロジェクト由来のコード、定数、状態遷移、係数をコピーしない。実装契約とパラメータはApple公式資料、Apple OSS、このリポジトリの純正trackpad / Nape Proログから再導出する。
- 実装上必要な実依存の識別子と法定通知を除き、README、実装、コメント、テスト名、ユーザー向け文書へ不要な第三者プロジェクトの固有名、コンポーネント名、参照実装由来と読める表現を残さない。
- 製品のgesture出力はtrackpad driver上位出力相当のscroll / gesture、DockSwipe、NavigationSwipe、magnification eventに限定する。DriverKit virtual trackpad、AX scrollbar、対象PID配送、keyboard shortcutによるgesture代替は使わない。
- 通常SDK非公開のevent contractは最小のcompatibility adapterへ隔離し、未知のmacOS versionやcontract不一致ではfail closedにする。詳細は[ADR-0036](docs/adr/0036-emulate-trackpad-driver-output-events.md)を正とする。
- output contractの`supported`は登録済みfixture ID、SHA-256、schema、contract ID、OS version / build、fixture実体の完全一致でだけ生成する。未登録fixtureやhash不一致を文字列IDだけで通さない。
- 製品gesture出力と旧単純scroll / shortcut /対象PID配送を含む診断出力はmodule境界で分離する。診断出力を製品fallbackやcompletion evidenceへ使わない。詳細は[ADR-0037](docs/adr/0037-separate-product-and-diagnostic-event-output.md)を正とする。
- ユーザーが見る挙動、GUI、権限導線、検証手順、完成状態、配布手順を変える場合は README を更新する。更新不要なら PR 本文で理由を明記する。
