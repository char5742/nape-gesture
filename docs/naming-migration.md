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

## P0: 旧mode・tuning設定から固定finger countモデルへの移行

設計正本は[ADR-0049](adr/0049-fixed-button-to-finger-count-trackpad-input.md)、実装追跡はIssue #148とする。

移行後の製品モデル:

- mouse button 3押下中の連続mouse event量は2本指trackpad入力へ変換する
- mouse button 4押下中の連続mouse event量は3本指trackpad入力へ変換する
- mouse button 5押下中の連続mouse event量は4本指trackpad入力へ変換する
- button 3 / 4 / 5未押下時は通常mouse入力を変更せず通す

この対応は設定項目ではない。結果別mode、方向別action、application別の有効・無効、感度、割り当てへ移行してはならない。

旧設定として扱う項目:

- `gesture.button3Mode`、`gesture.button4Mode`、`gesture.button5Mode`
- `none`、`twoFingerSwipe`、`systemSwipe`、`pinch`
- さらに古い`scrollAndNavigate`、`spacesAndMissionControl`、`zoom`
- 方向別actionまたはapplication別bindingの旧key
- `gesture.deadZonePoints`、`gesture.dragSensitivity`、`gesture.wheelSensitivity`、`gesture.acceleration`、`gesture.momentum`

移行条件:

- 旧mode値を製品runtimeの分岐に使わず、button番号からfinger countを一意に決める
- `none`を含む旧mode値で固定mappingを無効化または変更しない
- 旧mode / action / binding / tuning keyは読込時に検出し、対象device条件や安全停止条件など他の有効な設定を保持したままcanonical configから除去する
- 単位変換contractはfixtureとOS buildから選び、旧感度、加速度、dead zone、momentum係数を移行または再保存しない
- 旧key除去とcanonical config保存は原子的に行い、再起動を繰り返しても同じ結果になる
- migration失敗時は元設定fileを保持し、固定mappingが確定しない状態でruntimeを開始しない
- 未知または壊れた旧値を結果別modeへ推測変換せず、安全停止と復旧可能なエラーを使う
- 設定UI、canonical JSON schema、runtime log、現行migration test fixtureに旧modeを現行設定として再出力しない
- historical fixtureや証跡へ旧modeを残す場合は旧モデルの記録であることを明記し、現行期待値へ使わない

`scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`という名前は、低レベルevent familyまたは観測語彙として互換ログやfixtureに残せる。ただし、ユーザーmode、button割り当て、独立製品機能、完成状態を表す名前には使わない。OS/App結果は別項目として扱う。

2026-07-12のbaseline `55eb991` は旧mode keyと選択UIを保持しているため、この移行は未完了である。旧設定のdecode成功や既定値へのrewriteだけでは完了とせず、Issue #148の設定、GUI、runtime、migration testが一体で合格するまで未達とする。

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
- 現行ログはbutton 3 / 4 / 5と2 / 3 / 4本指の固定対応を検証可能にし、低レベルevent familyやOS/App結果と混同しない

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
- buttonごとのmode / family選択、方向別action、application別設定を表示しない
- 固定button→finger count対応を表示する場合は説明用の読取専用表示とし、変更可能なcontrolにしない
