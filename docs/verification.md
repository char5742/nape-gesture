# 検証手順と既知の失敗条件

この文書は、完成判定に必要な証跡、実機検証手順、既知の失敗条件と回復手順をまとめる。
「動いた気がする」ではなく、権限、対象デバイス、イベント列、画面挙動、体感差分を分けて確認する。

## 現在の確認状態

2026-07-08 時点の `nape-gesture` rename 後確認:

```sh
.build/debug/nape-gesture doctor --config /private/tmp/nape-gesture-doctor-config.json --probe-hid --benchmark-events 10000 --json
```

通常権限の実行では HID 入力監視プローブは成功した。入力監視権限は現在の実行経路から見えている。
一方で、アクセシビリティは未許可のまま。`matchedTargetDeviceCount` は 0 で、Nape Pro 実機識別は未完了。
サンドボックス内の実行では既定設定パス `~/Library/Application Support/NapeGesture/config.json` へ書き込めないため、検証時は `--config /private/tmp/...` を明示している。
`doctor` の `runtimeIdentity.executablePath` は次を示している。

```text
/Users/fujino/Documents/mac-gesture/.build/debug/nape-gesture
```

同じ時点で、再生成した `.app` からの確認も HID 入力監視プローブは成功、アクセシビリティは未許可だった。
`doctor` の `runtimeIdentity` は次を示している。

```text
bundlePath: /Users/fujino/Documents/mac-gesture/.build/NapeGesture.app
bundleIdentifier: dev.char5742.nape-gesture
executablePath: /Users/fujino/Documents/mac-gesture/.build/NapeGesture.app/Contents/MacOS/nape-gesture
```

現時点で `run`、`log`、実イベント投稿、Spaces / Mission Control の実機検証は、アクセシビリティ許可が実利用する `.app` または実行ファイルに付与されるまで完了扱いにしない。

## 権限確認

標準確認:

```sh
.build/debug/nape-gesture doctor --config <設定ファイル> --probe-hid --benchmark-events 50000 --json
```

完成判定では、少なくとも次が必要。

- `accessibilityTrusted` が `true`
- `hidProbe.requested` が `true`
- `hidProbe.succeeded` が `true`
- `runtimeIdentity` が、実際に日常利用する `.app` または実行ファイルを指している
- `requireMatchingTargetDevice` が `true` の場合、`matchedTargetDeviceCount` が `1` 以上

権限付与先を迷う場合は、`doctor --json` の `runtimeIdentity` を見る。
`.app` として使うなら `runtimeIdentity.isAppBundle` が `true` になる経路で確認し、システム設定でもその `.app` を許可する。
SwiftPM や debug バイナリを直接実行している場合は、`runtimeIdentity.executablePath` に出た実行ファイルを許可対象として扱う。

## 性能測定

入力遅延と CPU 使用率の基準は `docs/performance-baseline.md` を参照する。
PR レビューでは、まず純粋ロジックの benchmark と doctor 証跡を保存する。

```sh
.build/debug/nape-gesture benchmark --events 200000 --json
.build/debug/nape-gesture doctor --benchmark-events 50000 --json
```

`benchmark --json` と `doctor --benchmark-events ... --json` 内の benchmark は、`measurementKind: "pureLogic"`、`includesEventTapAndPosting: false` の測定である。
この値は `GestureRecognizer` と `ScrollGenerationPlanner` の処理コストを見るためのもので、IOHID、CGEvent tap、実イベント投稿、AppKit 受信、画面反映の遅延を含まない。

レビュー時に確認する主なキー:

- `recognizer.averageNanosecondsPerEvent`
- `recognizer.cpuNanosecondsPerEvent`
- `scrollPlanner.averageNanosecondsPerCommand`
- `scrollPlanner.cpuNanosecondsPerCommand`
- `reviewMetrics.totalCpuPercentOfOneCore`

常駐 CPU 使用率や tap-to-post 遅延を完了扱いにするには、アクセシビリティと入力監視が許可された実行主体で実機測定を行う。
`doctor --json` の `runtimeIdentity` が許可済みの `.app` または実行ファイルと一致していない場合、その測定は採用しない。
現時点の CLI だけでは tap callback から `CGEventPost` までの p95/p99 は自動算出できないため、入力遅延の完了判定には追加ログまたは同等の実測証跡が必要。

## Nape Pro 識別

対象デバイスが通常のマウス usage で出るとは限らないため、まず全 HID を見る。

```sh
.build/debug/nape-gesture devices --all --json
```

候補が見つかったら、vendor/product/usage を絞って生入力を取る。

```sh
.build/debug/nape-gesture hid-log --vendor-id <ID> --product-id <ID> --usage-page <ID> --usage <ID> --duration 10 > nape-hid.jsonl
.build/debug/nape-gesture analyze-hid-log nape-hid.jsonl
```

`analyze-hid-log` が出す `init-config` 候補を使い、対象条件を設定へ反映する。
`requireMatchingTargetDevice` を `true` にした状態で `doctor` の `matchedTargetDeviceCount` が `1` 以上になることを確認する。

## ログ比較

同じ形式で最低3種類のログを残す。

- 純正トラックパッド操作時の `nape-gesture log`
- Nape Pro 操作時の `nape-gesture log` または `hid-log`
- 生成イベントの `generate-scroll --dry-run --log-json`
- AppKit が受け取ったイベントの `nape-gesture target --out`

実入力ログ例:

```sh
.build/debug/nape-gesture log --duration 8 --out trackpad-space-right.jsonl --exclude-generated
.build/debug/nape-gesture log --duration 8 --out nape-space-right.jsonl --exclude-generated
.build/debug/nape-gesture target --out target-space-right.jsonl
```

生成イベントログ例:

```sh
.build/debug/nape-gesture generate-scroll --x 1200 --y 0 --steps 30 --mode space-right --phase auto --momentum-steps 8 --dry-run --log-json > generated-space-right.jsonl
.build/debug/nape-gesture system-test run --scenario space-right --target finder --dry-run --log-json --out system-space-right.jsonl
.build/debug/nape-gesture compare-log trackpad-space-right.jsonl generated-space-right.jsonl
```

`log` の開始・終了メッセージは標準エラーに出るため、`--out` や標準出力リダイレクトで保存したファイルは JSON Lines としてそのまま `analyze-log` / `compare-log` に渡せる。
`--exclude-generated` は純正入力や実デバイス入力の記録、`--only-generated` は Nape Gesture が投稿したイベント列の確認に使う。
`system-test run --dry-run --log-json` は、実イベントを投稿せず、System Behavior Test が生成する予定のスクロールまたはショートカットイベントを同じ JSON Lines 形式で保存する。Spaces のスクロール系シナリオは `compare-log` の候補ログとして使い、Mission Control やページ戻る/進むなどの離散シナリオは keyDown / keyUp の証跡として確認する。
`target --out` は AppKit が最終的に受け取った `scrollWheel`、`swipe`、`magnify`、`rotate`、マウスボタン、ドラッグを JSON Lines として保存する。`log` は CGEvent レベル、`target --out` は AppKit レベルの証跡として分けて扱う。
保存した AppKit 受信ログは `analyze-target-log <path>` で集計し、`scrollWheel`、`swipe`、`magnify`、`rotate`、phase、momentumPhase、precise scroll の有無を確認する。

比較では、イベント数、`precise` 相当の連続スクロール、`began` / `changed` / `ended` / `momentum` の分布、総スクロール量、方向を確認する。
JSON Lines では、通常スクロールの `began` / `changed` / `ended` は `scrollPhase`、慣性中と慣性終了は `momentumPhase` に出る。通常スクロール終了だけのイベント列で `momentumPhase` が立っている場合は、純正トラックパッドとの差分比較が汚れるため不正な生成ログとして扱う。
差分が残る場合は、しきい値、加速度、慣性、方向ロック、生成ステップ数、間隔を調整し、差分理由を記録する。

## Spaces / Mission Control 検証

完成形では、単なる `Ctrl + ←/→` の送信だけを最終解にしない。
まず生成したスクロール系イベントで macOS が純正トラックパッド相当に扱う範囲を実測する。

検証順:

1. 純正トラックパッドで Spaces 移動と Mission Control を実行し、`log` でイベント列を保存する
2. `generate-scroll --dry-run --log-json` で候補イベント列を生成し、純正ログと比較する
3. `system-test run --scenario space-left --target finder --dry-run` で実行計画を確認する
4. `system-test run --scenario space-left --target finder --dry-run --log-json --out system-space-left.jsonl` で生成予定イベント列を保存する
5. `target --out target-space-left.jsonl` を開き、基準ウィンドウ上で純正トラックパッド、Nape Pro、生成イベントの AppKit 受信差分を保存し、`analyze-target-log target-space-left.jsonl` で集計する
6. アクセシビリティが許可済みの状態で `system-test run --scenario space-left --target finder` を実行する
7. 画面挙動、CGEvent ログ、AppKit 受信ログ、体感差分を同じシナリオ名で記録する
8. `mission-control`、`space-right`、Safari のページ戻る/進む、ズームも同じ基準で確認する

公開 API だけで連続 Spaces 操作が成立しない場合は、次の証跡を残す。

- 純正トラックパッド操作のログ
- 生成イベントのログ
- AppKit 受信ログ
- `system-test` のパラメータ
- 画面挙動の結果
- 代替操作を使う場合の理由とチューニング値

## 既知の失敗条件

| 条件 | 主な症状 | 根本原因 | 回復手順 |
| --- | --- | --- | --- |
| 誤爆または暴走 | 意図しないスクロール、慣性継続、生成イベントが止まらない | 設定値、対象デバイス識別、公開 API の挙動差分 | `Control + Option + Command + G` を押してジェスチャー生成と慣性を即座に停止する。再開は常駐UIの停止/開始またはプロセス再起動で行う |
| 設定ファイルが不正 | `run` / `check-config` が設定エラーで開始しない、`doctor --json` の `settingsValidationIssues` が空ではない | JSON の直接編集、負の感度、0以下の慣性フレーム間隔、空の対象条件など | `settingsValidationIssues` の path を修正する。設定UIから保存し直すか、`init-config` でテンプレートを再生成する |
| アクセシビリティ未許可 | `accessibilityTrusted: false`、`run` / `log` / 実イベント投稿が開始できない | 許可が現在の実行主体に付いていない | `doctor --json` の `runtimeIdentity` を見て、該当 `.app` または実行ファイルをシステム設定のアクセシビリティへ追加し、プロセスを再起動する |
| 入力監視未許可 | `hidProbe.succeeded: false`、`kIOReturnNotPermitted` | IOHID を開く権限が現在の実行主体に付いていない | システム設定の入力監視で `runtimeIdentity` の対象を許可し、再起動後に `doctor --probe-hid` を再実行する |
| 対象条件が空 | 対象デバイス一致必須のまま起動できない | 全デバイス誤適用を防ぐ安全停止 | `init-config` または設定UIで vendor/product/usage/製品名のいずれかを設定する |
| 一致対象デバイスが0 | Nape Pro 操作を拾えない | matcher が実デバイスの HID 情報とずれている、または未接続 | `devices --all --json`、`hid-log`、`analyze-hid-log` で usage と値域を再特定する |
| `hid-log --all` が失敗 | 排他アクセスや一部デバイスで IOHID が開けない | 全 HID を一括で開こうとしている | `devices --all --json` で候補を絞り、vendor/product/usage を指定して記録する |
| `.app` が古い | CLI では存在するコマンドが `.app` にない、設定UIや診断が古い | `.app` 作成後に本体を更新した | `swift build -c release` 後に `bundle-app --replace` と `verify-bundle` を再実行する |
| 生成イベントが Spaces を動かさない | `compare-log` 上は近いが画面が動かない | CGEvent の公開 API 生成イベントを Mission Control が純正ジェスチャーと同等に扱わない可能性 | 純正ログ、生成ログ、`system-test` 結果を保存し、連続スクロール量、フェーズ、間隔、慣性を調整する。限界が残る場合は実測根拠つきで代替操作の品質目標を決める |
| 生成イベントを再入力して暴走する | 自分で投げたイベントを再解釈する | 生成元判定または抑制が欠けている | `generatedByNapeGesture` のログを確認し、イベントタップ側で自前生成イベントを無視できていることを確認する |
| スリープ復帰や抜き差し後に止まる | 常駐中に対象デバイスや権限を失う | HID 接続状態または TCC 状態が変わった | メニューバー常駐UIの自動再試行状態を確認し、`doctor` で対象デバイスと権限を再確認する |

## 完成判定チェック

完成扱いにするには、次の証跡をそろえる。

- debug と release のビルド成功
- `nape-gesture-core-tests` 成功
- `.app` 作成と `verify-bundle` 成功
- 実利用する `.app` の `doctor --probe-hid --json` でアクセシビリティと入力監視が成功
- `doctor --json` の `settingsValidationIssues` が空で、`check-config` が設定不正で停止しない
- Nape Pro の HID 識別ログと、設定への反映結果
- 純正トラックパッド、Nape Pro、生成イベントの比較ログ
- Finder、Safari、Spaces、Mission Control の `system-test` 結果
- 公開 API で不可能な挙動がある場合、その実測ログと代替操作のチューニング根拠
- 日常利用時に通常クリック、通常ドラッグ、通常ホイールが壊れていないことの確認
