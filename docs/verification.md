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
.build/debug/nape-gesture benchmark --events 200000 --json --assert-baseline
.build/debug/nape-gesture doctor --benchmark-events 50000 --json
```

`benchmark --json --assert-baseline` と `doctor --benchmark-events ... --json` 内の benchmark は、`measurementKind: "pureLogic"`、`includesEventTapAndPosting: false` の測定である。
この値は `GestureRecognizer` と `ScrollGenerationPlanner` の処理コストを見るためのもので、IOHID、CGEvent tap、実イベント投稿、AppKit 受信、画面反映の遅延を含まない。
`--assert-baseline` は純粋ロジック基準を満たさない場合に非ゼロ終了する。

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
HID ログとイベントタップログは、同じ10秒の操作範囲を別ターミナルで同時取得する。

```sh
# ターミナル1
.build/debug/nape-gesture hid-log --vendor-id <ID> --product-id <ID> --usage-page <ID> --usage <ID> --duration 10 > nape-hid.jsonl

# ターミナル2
.build/debug/nape-gesture log --duration 10 --out nape-event.jsonl --exclude-generated

# 両方の取得完了後
.build/debug/nape-gesture analyze-hid-log nape-hid.jsonl
.build/debug/nape-gesture analyze-association nape-hid.jsonl nape-event.jsonl --window 0.12 --json --assert-valid-window
```

`analyze-hid-log` が出す `init-config` 候補を使い、対象条件を設定へ反映する。
`requireMatchingTargetDevice` を `true` にした状態で `doctor` の `matchedTargetDeviceCount` が `1` 以上になることを確認する。

## 対象入力の紐づけ秒

`targetDeviceAssociation.associationWindow` は、対象 HID 入力の直近時刻とイベントタップ入力を同一入力として扱う秒数です。
デフォルトは従来挙動と同じ `0.12` 秒です。設定ファイル、`init-config --association-window <秒>`、設定UIから変更できます。

自動テストでは、次を純粋ロジックとして固定する。

- 設定値が `TargetDeviceGate` に反映される
- 設定値を超えたクリック、ドラッグ、ホイールは対象外入力として処理しない
- 古い設定JSONは `0.12` 秒を補い、既存挙動を維持する
- `0` 以下または非有限値は設定検証で拒否する

実機で完了判定するには、Nape Pro 操作時の HID ログとイベントタップログを同じシナリオで保存し、`analyze-association` で最も近い HID 入力とイベントタップ入力の時刻差分布、associationWindow 内外件数、推奨 `associationWindow` を確認する。収まらない場合は実測分布を根拠に `associationWindow` を調整し、調整後に通常マウス、通常ドラッグ、通常ホイールが巻き込まれないことを Reference Target App または System Behavior Test で確認する。
`--assert-valid-window` は、解析対象イベントがない場合、HID 候補なしがある場合、または associationWindow 外のイベントがある場合に非ゼロ終了する。実機ログ取得後の採否は、人間判断ではなく `analyze-association --json --assert-valid-window` の終了コードと `matches` の時刻差で行う。

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
.build/debug/nape-gesture target --out target-space-right.jsonl --duration 8 --ready-file target-space-right.ready.json
```

生成イベントログ例:

```sh
.build/debug/nape-gesture generate-scroll --x 1200 --y 0 --steps 30 --mode space-right --phase auto --momentum-steps 8 --dry-run --log-json > generated-space-right.jsonl
.build/debug/nape-gesture system-test run --scenario space-right --target finder --dry-run --log-json --out system-space-right.jsonl
.build/debug/nape-gesture system-test run --scenario horizontal-scroll --dry-run --log-json --out system-horizontal-scroll.jsonl
.build/debug/nape-gesture analyze-log system-horizontal-scroll.jsonl --json
.build/debug/nape-gesture derive-parameters trackpad-space-right.jsonl --json
.build/debug/nape-gesture compare-log trackpad-space-right.jsonl generated-space-right.jsonl
```

`log` の開始・終了メッセージは標準エラーに出るため、`--out` や標準出力リダイレクトで保存したファイルは JSON Lines としてそのまま `analyze-log` / `compare-log` に渡せる。
`derive-parameters` は、純正トラックパッドログから `deadZonePoints`、`acceleration.thresholdVelocity`、`momentum.minimumStartVelocity`、`momentum.stopVelocity`、`momentum.decayPerSecond`、`momentum.frameInterval` の候補を出す。十分な移動速度や `momentumPhase` サンプルがない場合は、推測値で埋めず `warnings` に未導出理由を残す。
`timestamp` の差分が 0.1ms 未満の合成ログでは速度推定が実機ログとして扱えないため、`warnings` が出た場合は候補値を参考扱いにする。
`--exclude-generated` は純正入力や実デバイス入力の記録、`--only-generated` は Nape Gesture が投稿したイベント列の確認に使う。
`system-test run --dry-run --log-json` は、実イベントを投稿せず、System Behavior Test が生成する予定のスクロールまたはショートカットイベントを同じ JSON Lines 形式で保存する。Spaces のスクロール系シナリオは `compare-log` の候補ログとして使い、`horizontal-scroll` は通常の横スクロール割り当ての scrollWheel イベント列として `analyze-log` で pointDeltaX / scrollDeltaX と precise/continuous 率を確認する。Mission Control やページ戻る/進むなどの離散シナリオは keyDown / keyUp の証跡として確認する。
Issue #10 の横スクロールは Safari / 対応アプリでの画面挙動確認が残るため、`horizontal-scroll` の dry-run と `analyze-log` は実機前証跡であり、完了扱いにはしない。
`target --out` は AppKit が最終的に受け取った `scrollWheel`、`swipe`、`magnify`、`rotate`、マウスボタン、ドラッグを JSON Lines として保存する。`log` は CGEvent レベル、`target --out` は AppKit レベルの証跡として分けて扱う。
`target --duration <秒>` を指定すると、指定秒数後に Reference Target App が自動終了する。`--duration` を指定しない場合は従来どおり手動終了する。
`target --ready-file <path>` を指定すると、target window が開いて JSON Lines 出力の準備ができた時点で ready file を JSON として書き出す。別プロセスの `run` / `system-test` と同期する場合は、古い ready file を消してから target をバックグラウンド起動し、ready file の作成を待ってからイベント生成側を開始する。
target log を検証する場合、`system-test run` には `--target finder` / `--target safari` を付けない。`--target` を指定すると Finder または Safari が前面化するため、Reference Target App の AppKit 受信ログではなく、`log` や画面挙動の検証として扱う。
保存した AppKit 受信ログは `analyze-target-log <path>` で集計し、`scrollWheel`、`swipe`、`magnify`、`rotate`、phase、momentumPhase、precise scroll の有無を確認する。
Issue #6 / #12 の最終実測へ進む前に、まず `analyze-target-log <path> --assert-no-leaks` で target log を機械判定する。
通常入力通過を確認する `normal-after-release` では、解放後の未マーク `mouseMoved` / `scrollWheel` が AppKit に届くことが期待値になる。この場合は `--assert-no-leaks` ではなく、`analyze-target-log <path> --json --assert-has-unmarked-input` で未マーク入力の存在を機械判定する。
Reference Target App が gesture 系イベントを扱えるかの前段確認は、実トラックパッド操作へ進む前に `Fixtures/gesture-target-log.jsonl` と `analyze-target-log --json --assert-has-gesture` で固定する。
この assertion は `swipe`、`magnify`、`rotate` のいずれかが target log に含まれることを確認し、Issue #10 のページ戻る / 進む / ズーム / 横スクロール検証で AppKit gesture 受信形式を先に機械判定するために使う。
人間の物理操作や macOS UI 操作は最後の手段とし、先に保存済みログ、`generate-scroll` / `system-test` の dry-run、アクセシビリティ許可済み環境での CGEvent 投稿で代替できる確認を済ませる。

自動実行の基本形:

```sh
target_log=/tmp/nape-target-space-right.jsonl
ready_file=/tmp/nape-target-space-right.ready.json
rm -f "$target_log" "$ready_file"
.build/debug/nape-gesture target --out "$target_log" --duration 8 --ready-file "$ready_file" &
target_pid=$!
until test -f "$ready_file"; do sleep 0.1; done
.build/debug/nape-gesture system-test run --scenario space-right
wait "$target_pid"
.build/debug/nape-gesture analyze-target-log "$target_log" --json --assert-no-leaks
```

Issue #6 / #12 の runtime event 証跡は、手順の取り違えを避けるため次のスクリプトを正とする。
このスクリプトは `doctor --json` で `accessibilityTrusted: true` を確認し、未許可の場合は target log を空ログとして扱わず外部ブロッカーとして記録する。

```sh
NAPE_RUNTIME_EVENT_ARTIFACT_ROOT=artifacts/completion/$(date +%F)/runtime-event-evidence sh scripts/collect-runtime-event-evidence.sh
```

実利用する `.build/NapeGesture.app` に TCC 権限を集約する場合は、次のように `.app` 作成と検証を含める。これにより、debug CLI へ別途権限を付ける必要を避け、`doctor --json` の `runtimeIdentity` を日常利用主体へ近づける。

```sh
NAPE_RUNTIME_EVENT_USE_APP_BUNDLE=1 \
NAPE_RUNTIME_EVENT_ARTIFACT_ROOT=artifacts/completion/$(date +%F)/runtime-event-evidence \
sh scripts/collect-runtime-event-evidence.sh
```

既に検証用の実行ファイルを固定している場合は、`NAPE_RUNTIME_EVENT_TOOL=<実行ファイル>` で `run`、`target`、`system-test`、`analyze-target-log`、`doctor` に使う実行主体を明示できる。

アクセシビリティ許可済みの場合、スクリプトは次を実行する。

- `gesture-drag`: `analyze-target-log --json --assert-no-leaks` でジェスチャードラッグ中の元入力漏れがないことを確認する
- `gesture-wheel`: `analyze-target-log --json --assert-no-leaks` でジェスチャーホイール中の元入力漏れがないことを確認する
- `kill-switch`: daemon log にキルスイッチ停止ログが出ることと、`analyze-target-log --json --assert-no-leaks` で `keyDown` / `keyUp` が前面アプリへ漏れないことを確認する
- `normal-after-release`: `analyze-target-log --json --assert-has-unmarked-input` で解放後の通常入力が過剰抑制されていないことを確認する

未マーク元入力の抑制を `run` と組み合わせて確認する場合は、Reference Target App を前面に保ったまま `gesture-drag` / `gesture-wheel` を `--target` なしで実行する。`--target finder` / `--target safari` を付けると Finder または Safari が前面化し、Reference Target App の AppKit 受信ログではなくなる。
CGEvent system-test は HID 対象デバイスの生入力を伴わないため、`requireMatchingTargetDevice=true` の設定では対象デバイス gate に引っかかる可能性がある。デーモンと組み合わせる検証では、必要に応じて `init-config --allow-unmatched` で作った検証用設定を使い、実利用設定とは分けて扱う。

```sh
config=/tmp/nape-system-test-allow-unmatched.json
.build/debug/nape-gesture init-config --allow-unmatched --out "$config"

for scenario in gesture-drag gesture-wheel; do
  target_log="/tmp/nape-target-${scenario}.jsonl"
  ready_file="/tmp/nape-target-${scenario}.ready.json"
  rm -f "$target_log" "$ready_file"
  .build/debug/nape-gesture run --config "$config" &
  daemon_pid=$!
  .build/debug/nape-gesture target --out "$target_log" --duration 8 --ready-file "$ready_file" &
  target_pid=$!
  until test -f "$ready_file"; do sleep 0.1; done
  .build/debug/nape-gesture system-test run --scenario "$scenario"
  wait "$target_pid"
  kill "$daemon_pid" 2>/dev/null || true
  wait "$daemon_pid" 2>/dev/null || true
  .build/debug/nape-gesture analyze-target-log "$target_log" --json --assert-no-leaks
done
```

`normal-after-release` は有効化ボタン解放後の通常入力通過を確認する材料を投稿する。Reference Target App を前面に保ち、同じく `--target` なしで実行する。解放後の `mouseMoved` / `scrollWheel` は未マーク通常入力として AppKit に届くことが期待値なので、`analyze-target-log --json --assert-has-unmarked-input` で未マーク入力が存在することを確認する。`--assert-no-leaks` はこのシナリオでは非ゼロ終了してよく、成功した場合は通常入力が過剰に抑制されていないかを疑う。

```sh
config=/tmp/nape-system-test-allow-unmatched.json
target_log=/tmp/nape-target-normal-after-release.jsonl
ready_file=/tmp/nape-target-normal-after-release.ready.json
rm -f "$target_log" "$ready_file"
.build/debug/nape-gesture init-config --allow-unmatched --out "$config"
.build/debug/nape-gesture run --config "$config" &
daemon_pid=$!
.build/debug/nape-gesture target --out "$target_log" --duration 8 --ready-file "$ready_file" &
target_pid=$!
until test -f "$ready_file"; do sleep 0.1; done
.build/debug/nape-gesture system-test run --scenario normal-after-release
wait "$target_pid"
kill "$daemon_pid" 2>/dev/null || true
wait "$daemon_pid" 2>/dev/null || true
.build/debug/nape-gesture analyze-target-log "$target_log" --json --assert-has-unmarked-input
```

Finder / Safari を対象にした画面挙動検証では、target log とは別に CGEvent レベルの `log` を保存する。

```sh
.build/debug/nape-gesture log --duration 8 --out system-finder-space-right.jsonl --only-generated &
log_pid=$!
.build/debug/nape-gesture system-test run --scenario space-right --target finder
wait "$log_pid"
.build/debug/nape-gesture analyze-log system-finder-space-right.jsonl --json
```

### Issue #6: 元入力漏れ候補の自動判定

ジェスチャー成立後の元入力抑制は、Reference Target App の target log に出る `generatedByNapeGesture` と `analyze-target-log --json` の漏れ候補数で初期判定する。
Nape Gesture が投稿した生成イベントは `generatedByNapeGesture: true` として記録されるため、Reference Target App に届いても元入力漏れ候補には数えない。
一方で、`generatedByNapeGesture: false` の `mouseDown`、`mouseUp`、`mouseMoved`、`mouseDragged`、`otherMouseDown`、`otherMouseUp`、`otherMouseDragged`、`rightMouseDown`、`rightMouseUp`、`rightMouseDragged`、`scrollWheel`、`keyDown`、`keyUp` は、前面アプリへ届いた未マーク入力として漏れ候補に数える。

確認例:

```sh
target_log=/tmp/nape-issue6-target.jsonl
ready_file=/tmp/nape-issue6-target.ready.json
rm -f "$target_log" "$ready_file"
.build/debug/nape-gesture target --out "$target_log" --duration 8 --ready-file "$ready_file" &
target_pid=$!
until test -f "$ready_file"; do sleep 0.1; done
# ここで対象デバイス操作、または --target を付けない system-test / CGEvent 投稿を別プロセスで実行する。
wait "$target_pid"
.build/debug/nape-gesture analyze-target-log "$target_log" --json --assert-no-leaks
```

`--assert-no-leaks` は通常の集計出力を維持したまま、`leakCandidateEvents` が1件以上ある場合に非ゼロ終了する。
CI やレビューでは、失敗時の詳細を回収できるように必要に応じて `--json --assert-no-leaks` を使い、JSON 出力後の終了コードで判定する。

主に見る値:

- `generatedEvents`: Nape Gesture 生成イベントとして届いた数
- `unmarkedEvents`: 生成マークなしで届いた総数
- `unmarkedMouseEvents`、`unmarkedScrollEvents`、`unmarkedKeyEvents`: 未マーク入力の分類別件数
- `leakCandidateEvents`: 漏れ候補として扱った実レコード
- `leakCandidateCounts`: 漏れ候補のイベント名別件数

既存の古い target log は `generatedByNapeGesture` フィールドを持たないため、互換性のため未マーク入力として扱われる。Issue #6 の最終証跡には、現在の Reference Target App で取り直した target log を使う。
`Fixtures/clean-target-log.jsonl` は生成イベントだけが AppKit に届いた例、`Fixtures/leaky-target-log.jsonl` は未マークのボタン、ドラッグ、スクロール、キーが混ざった失敗例として扱う。

Issue #6 の最終 close には、AX 許可済みの実行主体で event tap と Reference Target App を併用し、ジェスチャー成立後に `leakCandidateEvents` が空である証跡を残す必要がある。
漏れ候補が出た場合は、Reference Target App 側で候補レコードの `timestamp` と `name` を確認し、同じ時間帯の `nape-gesture log --exclude-generated` と照合する。
生成イベントが候補に混ざる場合は `CGEventUtilities.setGeneratedMarker` の付与漏れまたは `generatedByNapeGesture` 判定経路を直す。
未マークのボタン、ドラッグ、ホイール、キー入力が候補に残る場合は、イベントタップ callback の抑制判定、ジェスチャー成立前後の状態遷移、対象デバイス紐づけ秒を根本原因として追い、前面アプリへ通す前に抑制されるように修正する。

Issue #12 のキルスイッチと暴走停止の回帰確認でも、最終的な人間操作の前に `target --duration` と target log の assertion を使う。
暴走停止シナリオの前後で `target --out <path> --duration <秒> --ready-file <path>` を保存し、キルスイッチ後に Nape Gesture 由来でない `scrollWheel`、ドラッグ、ボタン、キー入力が混ざっていないことを `analyze-target-log <path> --json --assert-no-leaks` で確認する。
この target log 証跡では Reference Target App を前面に保つため、`system-test` へ `--target finder` / `--target safari` は指定しない。
実イベント投稿が必要な範囲は `system-test run` や `generate-scroll` で再現できるものを先に実行し、macOS UI 上の体感確認はログで代替できない最後の差分だけに限定する。

比較では、イベント数、`precise` 相当の連続スクロール、`began` / `changed` / `ended` / `momentum` の分布、総スクロール量、方向を確認する。
JSON Lines では、通常スクロールの `began` / `changed` / `ended` は `scrollPhase`、慣性中と慣性終了は `momentumPhase` に出る。通常スクロール終了だけのイベント列で `momentumPhase` が立っている場合は、純正トラックパッドとの差分比較が汚れるため不正な生成ログとして扱う。
差分が残る場合は、しきい値、加速度、慣性、方向ロック、生成ステップ数、間隔を調整し、差分理由を記録する。

## Spaces / Mission Control 検証

完成形では、単なる `Ctrl + ←/→` の送信だけを最終解にしない。
まず生成したスクロール系イベントで macOS が純正トラックパッド相当に扱う範囲を実測する。

検証順:

1. 純正トラックパッドで Spaces 移動と Mission Control を実行し、`log` でイベント列を保存する
2. `generate-scroll --dry-run --log-json` で候補イベント列を生成し、純正ログと比較する
3. `system-test run --scenario space-left --target finder --dry-run` で Finder 向け実行計画を確認する
4. `system-test run --scenario space-left --target finder --dry-run --log-json --out system-space-left.jsonl` で生成予定イベント列を保存する
5. `target --out target-space-left.jsonl --duration 8 --ready-file target-space-left.ready.json` を開き、Reference Target App を前面にしたまま `system-test run --scenario space-left` を実行して AppKit 受信差分を保存し、`analyze-target-log target-space-left.jsonl --json --assert-no-leaks` で集計する
6. アクセシビリティが許可済みの状態で `system-test run --scenario space-left --target finder` を実行し、Finder 前面時の画面挙動と `log` の生成イベント列を確認する
7. 画面挙動、CGEvent ログ、target log、体感差分を同じシナリオ名で記録する。ただし Finder / Safari を前面化した実行結果は target log と混同しない
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
| 設定ファイルが不正 | `run` / `check-config` が設定エラーで開始しない、`doctor --json` の `settingsValidationIssues` が空ではない | JSON の直接編集、負の感度、0以下の慣性フレーム間隔、0以下の対象入力紐づけ秒、空の対象条件など | `settingsValidationIssues` の path を修正する。設定UIから保存し直すか、`init-config` でテンプレートを再生成する |
| 対象入力の紐づけ秒が長すぎる | 別デバイスのクリック、ドラッグ、ホイールがジェスチャー処理へ巻き込まれる | `targetDeviceAssociation.associationWindow` が実測時刻差より大きすぎる | まず `0.12` 秒へ戻す。Nape Pro の HID ログ、イベントタップログ、Reference Target App の受信ログを同一シナリオで取り、巻き込みが出ない最小値へ調整する |
| アクセシビリティ未許可 | `accessibilityTrusted: false`、`run` / `log` / 実イベント投稿が開始できない | 許可が現在の実行主体に付いていない | `doctor --json` の `runtimeIdentity` を見て、該当 `.app` または実行ファイルをシステム設定のアクセシビリティへ追加し、プロセスを再起動する |
| 入力監視未許可 | `hidProbe.succeeded: false`、`kIOReturnNotPermitted` | IOHID を開く権限が現在の実行主体に付いていない | システム設定の入力監視で `runtimeIdentity` の対象を許可し、再起動後に `doctor --probe-hid` を再実行する |
| 対象条件が空 | 対象デバイス一致必須のまま起動できない | 全デバイス誤適用を防ぐ安全停止 | `init-config` または設定UIで vendor/product/usage/製品名のいずれかを設定する |
| 一致対象デバイスが0 | Nape Pro 操作を拾えない | matcher が実デバイスの HID 情報とずれている、または未接続 | `devices --all --json`、`hid-log`、`analyze-hid-log` で usage と値域を再特定する |
| `hid-log --all` が失敗 | 排他アクセスや一部デバイスで IOHID が開けない | 全 HID を一括で開こうとしている | `devices --all --json` で候補を絞り、vendor/product/usage を指定して記録する |
| `.app` が古い | CLI では存在するコマンドが `.app` にない、設定UIや診断が古い | `.app` 作成後に本体を更新した | `swift build -c release` 後に `bundle-app --replace` と `verify-bundle` を再実行する |
| 生成イベントが Spaces を動かさない | `compare-log` 上は近いが画面が動かない | CGEvent の公開 API 生成イベントを Mission Control が純正ジェスチャーと同等に扱わない可能性 | 純正ログ、生成ログ、`system-test` 結果を保存し、連続スクロール量、フェーズ、間隔、慣性を調整する。限界が残る場合は実測根拠つきで代替操作の品質目標を決める |
| 生成イベントを再入力して暴走する | 自分で投げたイベントを再解釈する | 生成元判定または抑制が欠けている | `generatedByNapeGesture` のログを確認し、イベントタップ側で自前生成イベントを無視できていることを確認する |
| スリープ復帰や抜き差し後に止まる | 常駐中に対象デバイスや権限を失う | HID 接続状態または TCC 状態が変わった | メニューバー常駐UIの自動再試行状態を確認し、`doctor` で対象デバイスと権限を再確認する |

キルスイッチの一方向停止は `NapeGestureCore` の `RuntimeSafetyState` で回帰テストする。`Control + Option + Command + G` 自体は event tap で抑制し、発火後はジェスチャー処理と慣性を停止する。停止後の通常入力は前面アプリへ通し、通常入力や再度のキルスイッチでは再有効化しない。再開は常駐UIの停止/開始による daemon 再作成、プロセス再起動、または明示 reset に限定する。

Issue #13 の実機前に機械で固定できる復旧条件は `NapeGestureCore` の `RuntimeRecoveryState` で回帰テストする。スリープ前停止、スリープ中の自動再試行禁止、wake 後の遅延再開、自動復旧可能な失敗の再試行、設定修正が必要な失敗と手動停止後の再試行禁止、手動開始または設定保存による再有効化を純粋ロジックとして確認する。
加えて、wake 後の再試行予約を手動停止で破棄すること、既存の失敗再試行予約を sleep で破棄すること、ready になった再試行予約を `.automaticRetry` として消費すること、負の wake retry delay を即時再試行として丸めることを境界条件として固定する。
`scripts/collect-completion-evidence.sh` は `doctor --probe-hid --json` も保存する。これは入力監視プローブ、`runtimeIdentity`、復旧手順を確認する機械証跡であり、スリープ、抜き差し、TCC 変更の実機操作ログを代替しない。

## 完成判定チェック

完成判定の証跡台帳と現在状態は `docs/completion-checklist.md` を正本にする。
この文書は、各証跡を取るための詳細手順、既知の失敗条件、回復手順を補足する。

完成扱いにするには、`docs/completion-checklist.md` の全 matrix 行が証跡リンク付きで `完了` になり、実機未検証の項目が残っていない必要がある。
