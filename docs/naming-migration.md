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

## P0: 旧mode・tuning設定から固定GestureClassモデルへの移行

設計正本は[ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md)とする。Issue #148は移行時の追跡履歴であり、現在の仕様や実装状態の正本には使わない。

移行後の製品モデル:

- mouse button 3押下中は固定`twoFingerScrollSwipe` classとして、type 22 scrollと必要なtype 29 companionへ変換する
- mouse button 4押下中は固定`threeFingerSystemSwipe` classとして、type 30 `DockSwipe` motion 1 / 2へ変換する
- mouse button 5押下中は固定`pinch` class（4本指system pinch相当）として、type 30 `DockSwipe` motion 4へ変換する
- button 3 / 4 / 5未押下時は通常mouse入力を変更せず通す

「2 / 3 / 4本指」はraw contact数やgeneric `fingerCount` transportではなく、固定GestureClassのユーザー向け説明である。各class固有のevent type、field、phase、companion、単位変換を使う。この対応は設定項目ではなく、結果別mode、方向別action、application別の有効・無効、感度、割り当てへ移行してはならない。例外として`gesture.systemGestureSensitivity`だけをbutton 4 / 5共通のcanonical倍率として持ち、button 3と固定mappingには適用しない。

旧設定として扱う項目:

- `gesture.button3Mode`、`gesture.button4Mode`、`gesture.button5Mode`
- `none`、`twoFingerSwipe`、`systemSwipe`、`pinch`
- さらに古い`scrollAndNavigate`、`spacesAndMissionControl`、`zoom`
- 方向別actionまたはapplication別bindingの旧key
- `gesture.deadZonePoints`、`gesture.dragSensitivity`、`gesture.wheelSensitivity`、`gesture.acceleration`、`gesture.momentum`

移行条件:

- 旧mode値を製品runtimeの分岐に使わず、button番号から固定GestureClassを一意に決める
- `none`を含む旧mode値で固定mappingを無効化または変更しない
- 旧mode / action / binding / tuning keyは読込時に検出し、対象device条件や安全停止条件など他の有効な設定を保持したままcanonical configから除去する
- class固有の単位変換contractはfixtureとOS buildから選び、旧`dragSensitivity`、`wheelSensitivity`、加速度、dead zone、momentum係数を新しい`systemGestureSensitivity`へ移行または再保存しない
- canonicalな`gesture.systemGestureSensitivity`がない旧設定には1.0を補う。既に0.25から2.0のcanonical値がある場合だけその値を保持する
- 旧key除去とcanonical config保存は原子的に行い、再起動を繰り返しても同じ結果になる
- migration失敗時は元設定fileを保持し、固定mappingが確定しない状態でruntimeを開始しない
- 未知または壊れた旧値を結果別modeへ推測変換せず、安全停止と復旧可能なエラーを使う
- 設定UI、canonical JSON schema、runtime log、現行migration test fixtureに旧modeを現行設定として再出力しない
- historical fixtureや証跡へ旧modeを残す場合は旧モデルの記録であることを明記し、現行期待値へ使わない

`scroll`と`DockSwipe`はclass固有ProductOutputの内部contractとして、`NavigationSwipe`と`magnification`は履歴上の観測語彙として互換ログやfixtureに残せる。ただし、いずれもユーザーmode、変更可能なbutton割り当て、独立製品機能、OS/App結果を表す名前には使わない。

2026-07-12のbaseline `55eb991` は旧mode keyと選択UIを保持していた移行前履歴であり、現在の実装状態を示さない。現行判定では、canonical設定から旧modeと旧tuningを原子的に除去し、新しい共通感度だけを保持または1.0で補完する。GUIの固定mappingを読取専用にし、runtimeとmigration testが3つの固定GestureClassおよびbutton 4 / 5共通感度へ一致していることを確認する。

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
- 現行ログはsource button、固定GestureClass、class固有ProductOutput、OS/App結果を別項目として検証可能にする

## P2: 配布文書

移行後:

- `LICENSE`、`THIRD_PARTY_NOTICES.md`、bundle fallback に `Nape Gesture` がある

注意点:

- 実装contract、field番号、状態遷移、係数、調整値をApple公式資料、Apple OSS、自前ログまで追跡できる方針は維持する

## P3: UI 表示

移行後:

- メニューバー表示はaccessibility label付きのsystem symbol
- Dock 表示名は `Nape Gesture`
- 設定ウィンドウや Reference Target App に `Nape Gesture` が残る

注意点:

- UI 名変更は権限導線と同じ検証で確認する
- buttonごとのmode / family選択、方向別action、application別設定を表示しない
- 固定button→GestureClass対応を説明用の読取専用表示とし、変更可能なcontrolにしない
- 「システムジェスチャー感度」だけを25%から200%、既定100%の共通sliderとして表示し、button別または方向別に分けない
