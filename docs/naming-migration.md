# nape-gesture 命名移行記録

`nape-gesture` 新リポジトリ化に伴い、旧 `Mac Gesture` / `mac-gesture` 系の命名から `Nape Gesture` / `nape-gesture` 系へ移行した内容を記録する。
権限対象、設定パス、JSON ログスキーマはユーザー環境に影響するため、残る互換項目を明示する。

## P0: 権限対象になる `.app` 名と bundle ID

移行後:

- 既定の `.app` 出力は `.build/NapeGesture.app`
- 表示名は `Nape Gesture`
- bundle ID は `dev.char5742.nape-gesture`
- 実行ファイル名は `nape-gesture`

注意点:

- 旧 `MacGesture.app` / `local.mac-gesture.app` に付与した macOS のアクセシビリティ権限と入力監視権限は、新 `NapeGesture.app` / `dev.char5742.nape-gesture` へ引き継がれない
- `doctor --json` と常駐 UI では、例示名より `runtimeIdentity` の実値を優先して案内する

## P0: SwiftPM 名と CLI 名

移行後:

- package: `NapeGesture`
- library: `NapeGestureCore`
- executable: `nape-gesture`
- test executable: `nape-gesture-core-tests`
- source directory: `Sources/nape-gesture`、`Sources/NapeGestureCore`

注意点:

- 新規公開前の baseline として `NapeGesture` / `NapeGestureCore` / `nape-gesture` へ統一済み
- 公開後は CLI 名や module 名の変更を破壊的変更として扱う

## P1: 設定パス

移行後:

- `~/Library/Application Support/NapeGesture/config.json`

注意点:

- 既に旧 `~/Library/Application Support/MacGesture/config.json` を使っている環境では、初回起動時にコピーまたは明示的な移行導線を出す必要がある
- 自動移行する場合も、対象デバイス設定と不正値検証を通す

## P1: 権限導線

移行後:

- README、doctor、help は `NapeGesture.app`、`Nape Gesture`、`dev.char5742.nape-gesture` を案内する

注意点:

- 旧 `.app` に権限を付けても新 `.app` には引き継がれない
- 最終的には `runtimeIdentity.bundlePath`、`runtimeIdentity.bundleIdentifier`、`runtimeIdentity.executablePath` を見て許可する説明へ寄せる

## P2: ログスキーマ

移行後:

- JSON Lines に `generatedByNapeGesture` がある

互換性:

- 新規出力は `generatedByNapeGesture` を使う
- 旧ログ互換のため、decode 時は `generatedByMacGesture` も読む
- encode 時は旧キーを出さない

## P2: 配布文書

移行後:

- `LICENSE`、`THIRD_PARTY_NOTICES.md`、bundle fallback に `Nape Gesture` がある

注意点:

- 実装contract、field番号、状態遷移、係数、調整値をApple公式資料、Apple OSS、自前ログまで追跡できる方針は維持する

## P3: UI 表示

移行後:

- メニューバー表示は `NG`
- Dock 表示名は `Nape Gesture`
- 設定ウィンドウや Reference Target App に `Nape Gesture` が残る

注意点:

- UI 名変更は権限導線と同じ検証で確認する
