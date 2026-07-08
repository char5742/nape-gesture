# Nape Gesture

Nape Pro などの通常マウス入力を、macOS 上でトラックパッド級のジェスチャー操作へ変換する常駐ツールです。

Mac Mouse Fix のコード、定数、状態遷移、係数は流用しません。公開 API と実機ログから独自に挙動を作ります。

## 現在の構成

- `NapeGestureCore`: ボタン押下中の移動・ホイールをジェスチャーへ変換する純粋ロジック
- `nape-gesture run`: グローバルイベントタップで入力を読み、生成スクロールイベントを投稿する常駐本体
- `nape-gesture log`: 実デバイス、純正トラックパッド、生成イベントを同じ JSON Lines 形式で記録するロガー
- `nape-gesture compare-log`: 純正入力ログと生成イベントログなど、2つの JSON Lines ログを比較する解析器
- `nape-gesture analyze-hid-log`: IOHID 生入力ログを device / usage ごとに集計する解析器
- `nape-gesture analyze-target-log`: Reference Target App が保存した AppKit 受信ログを集計する解析器
- `nape-gesture generate-scroll`: 任意のスクロールイベントを発火する生成器
- `nape-gesture target`: AppKit が受け取った `scrollWheel` / `swipe` / `magnify` などを表示し、JSON Lines に保存できる基準ターゲット
- `nape-gesture devices`: IOHID で認識できるマウス系または全 HID デバイスを一覧する補助コマンド

## 完成要件との対応

実装済みの基盤:

- 特定ボタン押下中だけジェスチャーモードへ入る状態機械
- ジェスチャーボタン未押下時の入力通過
- 微小移動をジェスチャー化しないデッドゾーン
- 方向ロック
- 速度に応じた加速度倍率
- 最大継続時間、無入力時間、軸ずれ比によるキャンセル条件
- `began` / `changed` / `ended` / `momentum` 相当の抽象フェーズ
- ピクセル単位スクロールイベント生成
- イベントログ、イベント生成、基準ターゲット
- 純正入力ログと生成イベントログの差分比較
- HID 生入力ログの usage 別解析
- メニューバー常駐UI
- 設定UIからの主要ジェスチャー割り当て、方向ロック比、加速度、慣性、キャンセル条件の調整
- `Control + Option + Command + G` によるキルスイッチ
- 権限とデバイスの確認導線
- 対象デバイス未検出、実行中のデバイス消失、権限未許可、スリープ復帰後の自動再試行
- マウス系に限らない全 HID デバイスからの対象照合
- 主要ロジックの自動テスト

未完了の大きな項目:

- 生成イベントによる Spaces / Mission Control の実機検証
- Nape Pro 固有のデバイス識別とイベントタップ入力の厳密な紐づけ
- 署名・公証済みリリース物の作成

## 使い方

```sh
swift run nape-gesture app
swift run nape-gesture help
swift run nape-gesture devices
swift run nape-gesture devices --all --json
swift run nape-gesture check-config
swift run nape-gesture hid-log --duration 10
swift run nape-gesture hid-log --vendor-id <ID> --product-id <ID> --usage-page <ID> --usage <ID> --duration 10
swift run nape-gesture analyze-hid-log Fixtures/sample-hid-log.jsonl
swift run nape-gesture analyze-target-log Fixtures/sample-target-log.jsonl
swift run nape-gesture log
swift run nape-gesture log --duration 8 --out trackpad-space-right.jsonl --exclude-generated
swift run nape-gesture analyze-log Fixtures/sample-log.jsonl
swift run nape-gesture compare-log Fixtures/sample-trackpad-scroll-log.jsonl Fixtures/sample-generated-scroll-log.jsonl
swift run nape-gesture target
swift run nape-gesture target --out target-events.jsonl
swift run nape-gesture generate-scroll --x 0 --y -480 --steps 24
swift run nape-gesture generate-scroll --x 0 --y -480 --steps 24 --momentum-steps 12 --dry-run
swift run nape-gesture generate-scroll --x 0 --y -480 --steps 24 --momentum-steps 12 --dry-run --log-json > generated-scroll.jsonl
swift run nape-gesture generate-scroll --x 1200 --y 0 --steps 30 --mode space-right --phase auto --dry-run --json
swift run nape-gesture system-test list
swift run nape-gesture system-test run --scenario space-left --target finder --dry-run
swift run nape-gesture system-test run --scenario space-left --target finder --dry-run --log-json --out system-space-left.jsonl
swift run nape-gesture benchmark --events 200000 --json
swift run nape-gesture doctor --probe-hid --benchmark-events 50000 --json
swift run nape-gesture init-config --out nape-gesture.config.json
swift run nape-gesture init-config --vendor-id <ID> --product-id <ID> --usage-page <ID> --usage <ID> --out nape-gesture.config.json
swift run nape-gesture run
swift run nape-gesture bundle-app --out .build/NapeGesture.app --replace
swift run nape-gesture verify-bundle .build/NapeGesture.app
swift run nape-gesture-core-tests
```

`run` と `log` はグローバル入力を扱うため、アクセシビリティ権限が必要です。
`log` は `--duration <秒>` で自動停止、`--out <path>` で JSON Lines を保存します。開始・終了などのメタ情報は標準エラーに出し、イベント本体だけを標準出力または `--out` に出します。`--exclude-generated` は純正入力や実デバイス入力だけ、`--only-generated` は Nape Gesture が生成したイベントだけを記録します。
`check-config --probe-hid` または対象デバイス設定つきの `run` は IOHID 入力を読むため、入力監視権限も必要です。
誤爆や暴走を感じた場合は `Control + Option + Command + G` を押してください。ジェスチャー生成と慣性を即座に停止し、再開は常駐UIの停止/開始またはプロセス再起動で行います。このショートカット自体は前面アプリへ渡さないよう抑制します。
`app` はメニューバー常駐UIを起動し、設定ファイルの作成、主要ジェスチャー割り当て、権限確認、常駐処理の開始・停止を行います。
`app` の「権限とデバイスを確認」は、アクセシビリティ、入力監視、権限付与対象、実行ファイル、bundle ID、HID デバイス数、対象一致数を表示します。
`app` は対象デバイス未検出、実行中の対象デバイス消失、アクセシビリティ未許可、入力監視未許可、スリープ復帰後の停止を検出した場合、手動で「停止」するまで 5 秒間隔で自動再試行します。実行中も同じ間隔で対象デバイスとアクセシビリティ権限を確認し、失われた場合は停止して自動再試行状態へ移行します。
`run`、`check-config`、`app` は `--config` を省略した場合、`~/Library/Application Support/NapeGesture/config.json` を使います。存在しない場合は Nape Pro 向けテンプレートを作成します。対象デバイス一致が必須のまま対象条件が空の場合は、全デバイスへ誤適用しないよう起動前に停止します。
設定ファイルは起動前に検証されます。感度、加速度、慣性、キャンセル条件、対象デバイス条件に不正値がある場合、`run` と `check-config` は開始せず、`doctor --json` は `settingsValidationIssues` に問題箇所を出します。
設定の `gesture.acceleration.isEnabled` は速度に応じた加速度倍率を有効化します。`thresholdVelocity` を超えた速度から倍率が上がり、`exponent` でカーブ、`maximumMultiplier` で最大倍率を調整します。デフォルトでは無効です。
設定の `gesture.momentum.isEnabled` はボタン解放後の慣性を有効化します。`minimumStartVelocity` で慣性開始速度、`stopVelocity` で終了速度、`decayPerSecond` で1秒あたりの減衰率、`frameInterval` で生成間隔を調整します。
設定の `gesture.cancellation.maximumDuration` はジェスチャー全体の最大秒数、`maximumInactivityInterval` は入力が途切れたときにキャンセルする秒数、`offAxisCancelRatio` は方向ロック後に直交方向へ逸れたときのキャンセル比です。各値は `0` で無効化できます。

権限確認:

```sh
swift run nape-gesture check-config --probe-hid
```

`kIOReturnNotPermitted` が出る場合は、システム設定の「プライバシーとセキュリティ」で、実行元の Codex、ターミナル、または `NapeGesture.app` に「入力監視」を許可してください。
権限を付与した直後に macOS が反映しない場合は、実行元アプリまたは `NapeGesture.app` を再起動してください。常駐UIは再起動後の初回起動で再度開始し、失敗時は自動再試行状態へ入ります。
`doctor --probe-hid` はアクセシビリティ、入力監視、対象デバイス一致、HID デバイス数、ベンチマークを一括で出し、失敗時の復旧手順も表示します。`--json` を付けると検証ログとして保存しやすい形式になります。
`doctor --json` には実行ファイル、bundle ID、bundle path などの `runtimeIdentity` も含めます。権限が未許可のときは、システム設定でどの `.app` または実行ファイルを許可すべきかをこの値で確認してください。
Nape Pro が通常の `devices` に出ない場合は、`devices --all --json` で全 HID デバイスを確認します。JSON には `stableID`、`vendorID`、`productID`、`primaryUsagePage`、`primaryUsage` が含まれます。対象らしい値が見つかったら、`hid-log --vendor-id <ID> --product-id <ID> --usage-page <ID> --usage <ID> --duration 10` を実行しながら Nape Pro を操作して、どの `usagePage` / `usage` で入力が来ているか確認します。取得した JSON Lines は `analyze-hid-log <path>` で集計し、イベント数、非ゼロ値、値域、`stableID` を見ます。`hid-log --all` は排他デバイスを含む環境で失敗することがあるため、通常はデバイスIDと usage を指定してください。
特定した値は `init-config --vendor-id <ID> --product-id <ID> --usage-page <ID> --usage <ID> --out <path>` で設定ファイルへ直接反映できます。必要なら `--manufacturer-contains`、`--product-contains`、`--transport-contains` も併用できます。設定UIでも vendor ID、product ID、usagePage、usage などを空欄任意の条件として編集できます。

## アプリバンドル

`.app` として使う場合は、先に通常どおりビルドしてからバンドルを作成します。

```sh
swift build -c release
.build/release/nape-gesture bundle-app --out .build/NapeGesture.app --replace
.build/release/nape-gesture verify-bundle .build/NapeGesture.app
```

`bundle-app` は `Info.plist`、実行ファイル、`LICENSE.txt`、`THIRD_PARTY_NOTICES.md` を含む `.app` を作成し、作成直後に同じ検証を実行します。`verify-bundle` は既存の `.app` を再検証するためのコマンドです。

作成した `NapeGesture.app` は引数なしで起動するとメニューバー常駐UIとして動きます。アクセシビリティや入力監視の許可は、この `.app` に対して付与してください。

## 検証方針

詳細な実機検証手順、完成判定に必要な証跡、既知の失敗条件と回復手順は `docs/verification.md` にまとめています。

1. `nape-gesture log --duration <秒> --out <path>` で純正トラックパッド、Nape Pro、生成イベントを同じ形式で記録する
2. `nape-gesture analyze-log <path>` で移動量分布と `deadZonePoints` 候補を確認する
3. `nape-gesture compare-log <純正ログ> <生成ログ>` でイベント数、precise 率、フェーズ分布、スクロール総量の差を確認する
4. `nape-gesture hid-log` と `nape-gesture analyze-hid-log <path>` で Nape Pro の HID usage と値域を確認する
5. `nape-gesture target --out <path>` で AppKit に届くイベント差分を画面と JSON Lines の両方で確認し、`analyze-target-log <path>` で集計する
6. `generate-scroll --dry-run --json` で began / changed / ended / momentum の生成計画を固定し、`--dry-run --log-json` で `compare-log` 用 JSON Lines を作る
7. `system-test list` でシナリオを確認し、`system-test run --scenario space-left --target finder --dry-run` で生成計画を確認する
8. `system-test run --scenario space-left --target finder --dry-run --log-json --out <path>` で System Behavior Test の生成予定イベントを JSON Lines として保存する
9. `benchmark --events 200000 --json` で認識器とスクロール計画の純粋ロジック処理時間を記録する
10. `doctor --benchmark-events 50000 --json` で権限、対象デバイス、実行主体、ベンチマークを一括記録する
11. `system-test run --scenario space-left --target finder` や `system-test run --scenario mission-control` で Spaces / Mission Control / Safari / Finder の挙動を実測する
12. 公開 API だけで連続 Spaces 操作が成立しない場合は、ログと画面挙動を根拠に限界を明文化する

`benchmark` と `doctor` 内の benchmark は `measurementKind: "pureLogic"` の証跡であり、イベントタップから投稿、AppKit 受信、画面反映までの入力遅延実測ではありません。
性能レビューで見る JSON キー、CPU 使用率、入力遅延の合格基準は `docs/performance-baseline.md` にまとめています。

## 開発運用

`nape-gesture` として新リポジトリ化するための作業は、次の文書で管理します。

- `docs/repository-setup.md`: GitHub リポジトリ作成、初回 push、Issue 作成の手順
- `docs/github-issues.md`: 初期 Issue の草案、依存関係、完了条件
- `docs/parallel-development.md`: メインスレッドとサブエージェントの役割分担
- `docs/pr-review-checklist.md`: PR レビューとマージ判断のチェックリスト
- `docs/naming-migration.md`: 旧 `Mac Gesture` 系の命名から `Nape Gesture` / `nape-gesture` へ移行した内容と残る互換項目

## ライセンス方針

Mac Mouse Fix のコードや調整値は取り込みません。実装パラメータはこのツールで取得したログから再導出します。
このリポジトリのライセンスは `LICENSE`、依存通知は `THIRD_PARTY_NOTICES.md` に記載します。アプリバンドルにはそれぞれ `Contents/Resources/LICENSE.txt` と `Contents/Resources/THIRD_PARTY_NOTICES.md` として同梱します。
