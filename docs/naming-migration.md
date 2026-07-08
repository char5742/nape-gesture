# nape-gesture 命名移行メモ

`nape-gesture` 新リポジトリ化に伴い、現在の `Mac Gesture` / `mac-gesture` 命名をどう扱うかを分離して管理する。
権限対象、設定パス、JSON ログスキーマはユーザー環境に影響するため、単純な一括置換では進めない。

## P0: 権限対象になる `.app` 名と bundle ID

現状:

- 既定の `.app` 出力は `.build/MacGesture.app`
- 表示名は `Mac Gesture`
- bundle ID は `local.mac-gesture.app`
- 実行ファイル名は `mac-gesture`

方針:

- 最終的には `NapeGesture.app`、表示名 `Nape Gesture`、安定した bundle ID へ移行する
- bundle ID 変更後は macOS のアクセシビリティ権限と入力監視権限を再付与する必要がある
- `doctor --json` と常駐 UI では、例示名より `runtimeIdentity` の実値を優先して案内する

## P0: SwiftPM 名と CLI 名

現状:

- package: `MacGesture`
- library: `MacGestureCore`
- executable: `mac-gesture`
- test executable: `mac-gesture-core-tests`
- source directory: `Sources/mac-gesture`、`Sources/MacGestureCore`

方針:

- 新規公開前に `NapeGesture` / `NapeGestureCore` / `nape-gesture` へ移行するか決める
- 既存 JSON Lines、ドキュメント、テスト、CI、README の更新を同一 PR に閉じ込める
- CLI 名変更時は旧コマンド例を残さず、移行メモにだけ履歴として残す

## P1: 設定パス

現状:

- `~/Library/Application Support/MacGesture/config.json`

方針:

- 最終設定パスは `~/Library/Application Support/NapeGesture/config.json` を候補にする
- 旧設定が存在する場合、初回起動時にコピーまたは明示的な移行導線を出す
- 自動移行する場合も、対象デバイス設定と不正値検証を通す

## P1: 権限導線の旧名

現状:

- README、doctor、help に `MacGesture.app`、`Mac Gesture`、`local.mac-gesture.app` が残る

方針:

- 旧名例示を削除し、`runtimeIdentity.bundlePath`、`runtimeIdentity.bundleIdentifier`、`runtimeIdentity.executablePath` を見て許可する説明へ寄せる
- 旧 `.app` に権限を付けても新 `.app` には引き継がれないことを明記する

## P2: ログスキーマ

現状:

- JSON Lines に `generatedByMacGesture` がある

方針:

- 互換性重視なら legacy field として維持し、README と schema メモに明記する
- 完全移行するなら `generatedByNapeGesture` を追加し、旧キー decode 互換を用意してから fixture を更新する
- 比較ログが壊れるため、単純 rename はしない

## P2: 配布文書

現状:

- `LICENSE`、`THIRD_PARTY_NOTICES.md`、bundle fallback に `Mac Gesture` がある

方針:

- 配布物に含まれる表示名は release PR で新名へ統一する
- Mac Mouse Fix のコード、定数、状態遷移、係数をコピーしていない方針は維持する

## P3: UI 表示

現状:

- メニューバー表示は `MG`
- 設定ウィンドウや Reference Target App に `Mac Gesture` が残る

方針:

- 新名確定後に `NG`、`Nape Gesture 設定` へ更新する
- UI 名変更は権限導線と同じ PR で確認する
