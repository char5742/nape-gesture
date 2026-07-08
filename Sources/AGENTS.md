# Sources/AGENTS.md

`Sources/` 配下では、Swift 実装とテスト容易性を最優先します。入力安全性、権限境界、証跡形式を崩す変更は小さく見えても高リスクとして扱います。

## 共通ルール

- `NapeGestureCore` は純粋ロジックの置き場として保ち、AppKit、CoreGraphics、IOKit など macOS 実行環境依存を持ち込まない。
- `nape-gesture` は CLI、AppKit、CGEvent、IOKit、bundle、doctor など実行環境依存を扱う境界とする。
- 公開 API、JSON schema、JSON Lines 形式、終了コードを変える場合は、fixture、analyzer、docs、CI smoke まで更新する。
- 生成イベント、通常入力、キルスイッチ、対象デバイス判定に関わる変更では、正常系だけでなく「通ってはいけない fixture」も維持する。
- 実機や TCC が必要な動作を、core test や dry-run だけで完了扱いにしない。

## 検証

- コード変更後は `swift build --scratch-path .build` と `.build/debug/nape-gesture-core-tests` を基本ゲートにする。
- bundle、署名、release path に触れた場合は `swift build -c release --scratch-path .build` と `verify-bundle` 系の検証を追加する。
- benchmark、doctor、system-test、analyze 系の JSON 契約を変えた場合は、対応する dry-run と analyzer assertion を実行する。
