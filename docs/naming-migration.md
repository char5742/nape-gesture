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

## P0: 旧mode・固定mappingからbutton割り当てモデルへの移行

設計正本は[ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md)とする。Issue #148は移行時の追跡履歴であり、現在の仕様や実装状態の正本には使わない。

移行後の製品モデル:

- mouse button 3 / 4 / 5のそれぞれに`twoFingerScrollSwipe`、`threeFingerSystemSwipe`、`pinch`から1つを割り当てる
- 同じGestureClassを複数buttonへ割り当てられる
- 各buttonには常に1 classを割り当て、無効または未割り当てにはしない
- button 3 / 4 / 5未押下時は通常mouse入力を変更せず通す
- GestureClassから`scroll` / `dockSwipe` / `dockSwipePinch`へのProductOutput contractは変更しない

「2 / 3 / 4本指」はraw contact数やgeneric `fingerCount` transportではなく、GestureClassのユーザー向け説明である。各class固有のevent type、field、phase、companion、単位変換を使う。結果別mode、方向別action、application別の有効・無効、感度、割り当てへ戻してはならない。`gesture.systemGestureSensitivity`は3本指 / 4本指class共通のcanonical倍率として持ち、物理button番号ではなく選択されたclassへ適用する。

旧設定として扱う項目:

- `gesture.button3Mode`、`gesture.button4Mode`、`gesture.button5Mode`
- `none`、`twoFingerSwipe`、`systemSwipe`、`pinch`
- さらに古い`scrollAndNavigate`、`spacesAndMissionControl`、`zoom`
- 方向別actionまたはapplication別bindingの旧key
- `gesture.deadZonePoints`、`gesture.dragSensitivity`、`gesture.wheelSensitivity`、`gesture.acceleration`、`gesture.momentum`

canonical形式:

```json
{
  "gesture": {
    "buttonAssignments": {
      "button3": "twoFingerScrollSwipe",
      "button4": "threeFingerSystemSwipe",
      "button5": "pinch"
    },
    "systemGestureSensitivity": 1.0
  }
}
```

移行条件:

- `gesture.buttonAssignments`がない固定モデルの設定には、button 3 = `twoFingerScrollSwipe`、button 4 = `threeFingerSystemSwipe`、button 5 = `pinch`を既定値として補う
- 現行`buttonAssignments`は3 keyすべてを持ち、各値は3 GestureClassのいずれかとする。同じ値の重複を正規化または拒否しない
- `none`、null、欠落key、未知classを現行割り当てとして受け入れない
- 旧mode値を現行割り当てへ推測変換せず、旧mode / action / binding / tuning keyは他の有効な設定を保持したままcanonical configから除去する
- class固有の単位変換contractはfixtureとOS buildから選び、旧`dragSensitivity`、`wheelSensitivity`、加速度、dead zone、momentum係数を新しい`systemGestureSensitivity`へ移行または再保存しない
- canonicalな`gesture.systemGestureSensitivity`がない旧設定には1.0を補う。既に0.25から2.0のcanonical値がある場合だけその値を保持する
- 旧key除去、割り当て補完、canonical config保存は原子的に行い、再起動を繰り返しても同じ結果になる
- migration失敗時は元設定fileを保持し、3 buttonの割り当てが確定しない状態でruntimeを開始しない
- 設定UI、canonical JSON schema、runtime log、現行migration test fixtureに旧modeを現行設定として再出力しない
- historical fixtureや証跡へ旧modeを残す場合は旧モデルの記録であることを明記し、現行期待値へ使わない

`scroll`と`DockSwipe`はclass固有ProductOutputの内部contractとして、`NavigationSwipe`と`magnification`は履歴上の観測語彙として互換ログやfixtureに残せる。ただし、いずれもGUIの割り当て候補、ユーザーmode、独立製品機能、OS/App結果を表す名前には使わない。

2026-07-12のbaseline `55eb991` は旧mode keyと選択UIを保持していた移行前履歴であり、現在の実装状態を示さない。固定mappingへ移行した後の設定も、割り当てfieldを持たない移行元として扱う。現行判定では、canonical設定から旧modeと旧tuningを原子的に除去し、3 buttonの割り当てと共通感度だけを保存する。runtimeとmigration testでは重複割り当て、既定値補完、再起動後復元、選択class基準の感度適用を確認する。

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
- 現行ログはsource button、保存済み割り当て、sessionで選択したGestureClass、class固有ProductOutput、OS/App結果を別項目として検証可能にする

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
- buttonごとに3 GestureClassだけを選べるselectorを表示し、重複選択を許可する
- 無効・未割り当て、family名、方向別action、application別設定を選択肢として表示しない
- 「システムジェスチャー感度」だけを25%から200%、既定100%の共通sliderとして表示し、button別または方向別に分けない
