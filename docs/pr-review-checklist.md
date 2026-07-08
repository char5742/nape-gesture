# PR レビューチェックリスト

メインスレッドはこのチェックリストを基準に、Issue 整理、PR レビュー、マージ判断へ集中する。
実装量ではなく、ゴール要件に対する証跡と安全性で判断する。
開発運用の継続方針は [ADR 一覧](adr/README.md) を正とする。

## 共通ゲート

- 対応 Issue が明記されている
- 変更ファイルの所有範囲が説明されている
- コード、Package、workflow に影響する変更では `swift build --scratch-path .build` が成功している
- コード、Package、workflow に影響する変更では `.build/debug/nape-gesture-core-tests` が成功している
- release build が必要な変更では `swift build -c release --scratch-path .build` が成功している
- docs/config のみの変更では、変更対象に合った検証と Swift build を省略した理由が PR 本文に明記されている
- 未検証事項を「完了」と表現していない
- Mac Mouse Fix のコード、定数、状態遷移、係数をコピーしていない

## 性能 / Benchmark 変更

- `benchmark --events 200000 --json --assert-baseline` の出力と終了コードが保存または PR 本文へ要約されている
- `doctor --benchmark-events 50000 --json` の出力が保存または PR 本文へ要約されている
- `measurementKind` が `pureLogic`、`includesEventTapAndPosting` が `false` であることを確認している
- `--assert-baseline` が成功し、`recognizer.averageNanosecondsPerEvent`、`recognizer.cpuNanosecondsPerEvent`、`scrollPlanner.averageNanosecondsPerCommand`、`scrollPlanner.cpuNanosecondsPerCommand` が `docs/performance-baseline.md` の基準内である
- 純粋ロジック benchmark を、イベントタップから投稿までの入力遅延実測として扱っていない
- 常駐 CPU 使用率や tap-to-post 遅延を完了扱いにする場合、実機・権限付きの測定手順と未検証事項が明記されている
- 閾値超過時に調整した設定値や生成パラメータが、ログと benchmark の再測定で確認されている

## Core 変更

- ジェスチャーボタン未押下時の入力通過を壊していない
- デッドゾーン内の微小揺れをジェスチャー確定にしていない
- ボタン解放後に必ず通常状態へ戻る
- `began` / `changed` / `ended` / `cancelled` / `momentum` の意味が崩れていない
- 方向ロック、加速度、キャンセル条件、慣性のテストが追加または更新されている

## Runtime / Event Tap 変更

- 自前生成イベントを再解釈しない
- ジェスチャー成立後の元入力漏れを増やしていない
- 対象外デバイスの通常クリック、ドラッグ、ホイールを改変しない
- キルスイッチで生成と慣性を即時停止できる
- キルスイッチ自体を event tap で抑制し、前面アプリへ渡していない
- キルスイッチ後も通常入力を勝手に抑制し続けない
- 一方向停止と明示 reset 以外で復帰しないことを Core の純粋テストで確認している
- アクセシビリティ未許可時に安全に停止し、復旧導線を出す

## HID / Device 変更

- 全デバイス誤適用を避けている
- 複合 HID や特殊 usage を見落とさない調査経路がある
- 対象未検出時に安全停止する
- `devices --all --json`、`hid-log`、`analyze-hid-log` のどれで証跡を取るか明記されている
- 実機 Nape Pro が必要な項目をモックだけで完了扱いにしていない

## 生成イベント / Spaces / Mission Control 変更

- 通常スクロールのフェーズは `scrollPhase`、慣性は `momentumPhase` に分離されている
- `generate-scroll --dry-run --log-json` で比較可能な JSON Lines を出せる
- `system-test run --dry-run --log-json` で生成予定イベントを保存できる
- `Ctrl + ←/→` などのショートカット送信を最終解として前提化していない
- Finder、Safari、Mission Control、Spaces で必要な実機検証が明記されている

## UI / Doctor / 権限導線変更

- 設定 UI にアプリ別の有効・無効、感度、割り当てを追加していない
- 不正な設定値を保存前または起動前に止める
- `runtimeIdentity` で権限付与対象が分かる
- アクセシビリティと入力監視の失敗を区別している
- スリープ復帰、デバイス抜き差し、権限変更後の復旧状態を説明できる

## Release 変更

- `.app` バンドルを作成し、`verify-bundle` が成功する
- `LICENSE` と `THIRD_PARTY_NOTICES.md` が同梱される
- ローカル検証では ad-hoc 署名、公開配布では Developer ID Application 署名と公証を使う境界が明記されている
- 公開配布前は `verify-bundle --require-signature` と `codesign --verify --deep --strict --verbose=2` が成功している
- 公証が未完了なら、未完了理由と次の作業が明記されている
- 権限付与対象の `.app` 名と bundle ID が README / doctor / Info.plist で矛盾していない

## 差し戻し基準

- 実機が必要な検証を dry-run だけで完了扱いにしている
- 入力安全性に影響する変更でテストまたはログがない
- 旧名、新名、bundle ID、設定パスの混在が増えている
- Mac Mouse Fix 由来のコードや係数を持ち込んでいる
- CI やローカル検証の失敗を後回しにしている
