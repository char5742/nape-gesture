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
- ユーザーが見る挙動、GUI、権限導線、検証手順、完成状態、配布手順を変えた場合、README を更新している。更新不要の場合は PR 本文で理由を明記している
- 未検証事項を「完了」と表現していない
- Mac Mouse Fix のコード、定数、状態遷移、係数をコピーしていない
- 由来や配布物に影響する変更では `sh scripts/check-provenance.sh` が成功している
- Grok CLIによる独立監査、補助レビュー、発散、PR差分レビューを実行していない
- 外部モデルの出力を設計判断、PR review、完成判定、CI gate、runtime証跡に混ぜていない
- computer-use で代替できる GUI 操作を `need:human` にしていない。OS セキュリティ設定を変更する UI 操作では直前確認を取っている
- Mermaid 図やアプリキャプチャを使う場合、実装、docs、実際の画面証跡と矛盾していない

## 性能 / Benchmark 変更

- `benchmark --events 200000 --json --assert-baseline` の出力と終了コードが保存または PR 本文へ要約されている
- `doctor --benchmark-events 50000 --json` の出力が保存または PR 本文へ要約されている
- `measurementKind` が `pureLogic`、`includesEventTapAndPosting` が `false` であることを確認している
- `BenchmarkReport.schemaVersion` が `3` で、`sampledNanosecondsPerEvent` と `sampledNanosecondsPerCommand` の p95 / p99 が保存されている
- `--assert-baseline` が成功し、`recognizer.averageNanosecondsPerEvent`、`recognizer.cpuNanosecondsPerEvent`、`recognizer.sampledNanosecondsPerEvent.p95Nanoseconds`、`recognizer.sampledNanosecondsPerEvent.p99Nanoseconds`、`scrollPlanner.averageNanosecondsPerCommand`、`scrollPlanner.cpuNanosecondsPerCommand`、`scrollPlanner.sampledNanosecondsPerCommand.p95Nanoseconds`、`scrollPlanner.sampledNanosecondsPerCommand.p99Nanoseconds` が `docs/performance-baseline.md` の基準内である
- 純粋ロジック benchmark を、イベントタップから投稿までの入力遅延実測として扱っていない
- tap-to-post 遅延を完了扱いにする場合、`run --performance-log` または `NAPE_RUNTIME_PERFORMANCE_LOG` で取得した runtime 性能 JSON Lines と `analyze-performance-log --json --assert-baseline` の結果が保存されている
- runtime 性能ログを AppKit 受信や画面反映の証跡として扱っていない
- 常駐 CPU 使用率を完了扱いにする場合、実機・権限付きの測定手順と未検証事項が明記されている
- 閾値超過時に調整した設定値や生成パラメータが、ログと benchmark の再測定で確認されている

## Core 変更

- ジェスチャーボタン未押下時の入力通過を壊していない
- デッドゾーン内の微小揺れをジェスチャー確定にしていない
- ボタン解放後に必ず通常状態へ戻る
- scrollの`began` / `changed` / `ended` / `cancelled`とmomentumの`began` / `continued` / `ended`を別のlifecycleとして扱っている
- 方向ロック、加速度、キャンセル条件、慣性のテストが追加または更新されている

## Runtime / Event Tap 変更

- 自前生成イベントを再解釈しない
- 製品のgesture出力がtrackpad driver上位出力相当のevent adapterへ集約されている
- 製品runtimeが`NapeGestureProductOutput`だけを参照し、`DiagnosticEventPoster`を参照していない
- 旧単純scroll / shortcutは`NapeGestureDiagnosticOutput` targetにだけ存在し、許可したCLI command以外からimportされていない
- AX scrollbar、対象PID配送、frontmost application分岐、keyboard shortcutをgesture出力に使っていない
- 通常SDK非公開のevent contractがcompatibility adapter外へ漏れていない
- 未知のmacOS versionまたはcontract不一致で誤ったeventを送らずfail closedになる
- `supported`が登録済みfixture ID / SHA-256 / schema / contract ID / OS build / fixture実体の完全一致だけで生成される
- output contract未対応時はevent tapと入力抑制を開始せず、別方式へfallbackしない
- ジェスチャー成立後の元入力漏れを増やしていない
- 対象外デバイスの通常クリック、ドラッグ、ホイールを改変しない
- `doctor --json` の `targetDeviceDiagnostics` で、対象デバイス不一致時の matcher 条件差分を確認できる
- キルスイッチで生成と慣性を即時停止できる
- キルスイッチ自体を event tap で抑制し、前面アプリへ渡していない
- `system-test run --scenario kill-switch --dry-run --log-json` を `analyze-log --assert-kill-switch-shortcut` で確認している
- `system-test run --scenario gesture-wheel-then-kill-switch --dry-run --log-json` を `analyze-log --assert-kill-switch-shortcut --assert-gesture-before-kill-switch` で確認している
- キルスイッチ後も通常入力を勝手に抑制し続けない
- 一方向停止と明示 reset 以外で復帰しないことを Core の純粋テストで確認している
- `normal-after-release` dry-run を `analyze-log --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel` で確認し、未生成キーや activation button だけを通常入力通過証跡として扱っていない
- runtime event 証跡を更新した場合、`status.json.status`、`blockerCode`、`preflight/`、権限済み時の `scenarios/` の関係が崩れていない
- アクセシビリティ未許可時に安全に停止し、復旧導線を出す

## HID / Device 変更

- 全デバイス誤適用を避けている
- 複合 HID や特殊 usage を見落とさない調査経路がある
- 対象未検出時に安全停止する
- `devices --all --json`、`hid-log`、`analyze-hid-log` のどれで証跡を取るか明記されている
- 実機 Nape Pro が必要な項目をモックだけで完了扱いにしていない

## Trackpad driver出力 / Spaces / Mission Control変更

- raw loggerはcallback内をcopy・採番・bounded queue投入に限定し、0 event、queue飽和、write / flush / close失敗を成功扱いにしていない
- raw fieldは`fieldNumber`の数値昇順でzeroとdouble bit patternを保持し、serialized eventをCoreGraphicsで再構築できる
- `--out` captureはevidence kind、最終log SHA / bytes / event数 / timestamp範囲、metadata、logger executable SHA、完了wall-clockをmanifestへ固定し、失敗captureに旧sidecar、symlink、一時fileを残していない
- 厳格analyzerはtyped decodeの既定値補完前にLF終端、空行、重複key、nesting上限、整数精度、required field、nullable subtype、metadata、capture順、timestamp、raw field順、bit pattern、Base64を検証している
- unknown top-level / metadata fieldを捨てず、raw JSON表現とreportへ保持している
- generated product captureは生成marker、actual event type、raw target process fieldとprovenanceのlog SHA / 件数 / 順序 / timestamp / type / output session / familyを照合し、製品source境界guardと併せてPID、AX、shortcut、key / pointer / button経路を拒否している
- CoreGraphics再構築で保持されないraw field差分を捨てたり意味推測せず`rawFieldDifferences`へ分離し、type / timestamp / flags / subtype /公開named field不一致だけをPhase 1の再構築失敗にしている
- `--duration`なしのloggerはSIGINT後にevent受付を止め、queue drainとflush / closeを完了している
- output sessionはsession ID、0始まりで欠落のないcapture order、非減少の起動後timestamp、terminal stateを保持する
- input lifecycleとmomentum lifecycleを別型にし、input ended後のsession完了またはmomentum開始待ちを明示している
- kill switch、runtime stop、sleep、device切断、権限変更、output failureで、input開始前を含む全nonterminal stateから明示cancelしてterminalへ収束し、active cancellationのfamilyと最終payloadを失わない
- 製品gesture出力境界は`MonotonicEventClock`を使い、Unix wall clockや別のuptime取得を直接混在させていない
- `DiagnosticEventPoster`、`generate-scroll`、`system-test`の実投稿とdry-run logも`MonotonicEventClock`を使い、sequence先頭を投稿開始reference以下、元列を非減少として検証し、各実eventのtimestampを投稿直前の同一clock値から確定している
- shortcutはdown/upを両方生成・検証してから投稿し、sequence途中失敗ではactiveなscroll / momentum terminal、`mouseUp`、`keyUp`へ収束する
- `nape-gesture-diagnostic-output-tests`がboot外start、元timestamp回帰、未来予定offset、UInt64差分回帰、failure injection、全13 system scenario、全48 generate patternの現在boot上限・件数・offsetを直接検証し、`sh scripts/check-diagnostic-event-time.sh`も成功している
- trackpad scrollではcontinuous scroll eventと対応するscroll gesture eventを同一timestamp系列で出す
- scroll phaseとmomentum phaseを分離し、begin / change / end / cancelとmomentum begin / continue / endを完結させる
- Spaces / Mission Controlはprogressとphaseを持つDockSwipe event系列として実装し、forced horizontal scrollやkeyboard shortcutで代替していない
- page navigationはNavigationSwipe、zoomはmagnification / zoom eventとして実装している
- 純正trackpad logとtype、subtype、field、順序、timestamp、phase、momentumを同一schemaで比較している
- Mac Mouse Fix由来のfield番号、定数、係数、状態遷移をコピーせず、Apple公式資料、Apple OSS、自前ログから導出した根拠がある
- `generate-scroll` / `system-test`の旧単純CGEvent結果をtrackpad driver出力の完成証跡にしていない
- Finder、Safari、Mission Control、Spacesでsystem-wide配送の実機検証が明記されている

## UI / Doctor / 権限導線変更

- 設定 UI にアプリ別の有効・無効、感度、割り当てを追加していない
- 設定 UI の編集対象は `SettingsUIField.descriptors` に追加し、設定パス、control kind、JSON round-trip、アプリ別設定なしの core test を維持している
- 設定 UI の割り当て候補は `GestureAction.settingsSelectableActions` から生成し、`GestureAction.allCases` との網羅性テストを維持している
- 不正な設定値を保存前または起動前に止める
- `runtimeIdentity` で権限付与対象が分かる
- `runtimeReadiness.ready`、`runtimeReadiness.failures[].code`、`tccStatus.accessibility`、`tccStatus.inputMonitoring` で runtime ready と TCC 状態を構造化している
- `tccStatus.permissionTarget` と `grantRequired` で、権限を付与すべき `.app` または実行ファイルを機械的に引用できる
- アクセシビリティと入力監視の失敗を区別している
- doctor JSON 契約を変えた場合は CI smoke、completion evidence、関連 ADR を更新している
- 常駐 UI の実行中、停止中、自動再試行中、スリープ待機中表示が `RuntimeStatusPresenter` の core test で固定されている
- スリープ復帰、デバイス抜き差し、権限変更後の復旧状態を説明できる

## Release 変更

- `.app` バンドルを作成し、`verify-bundle` が成功する
- `LICENSE` と `THIRD_PARTY_NOTICES.md` が同梱される
- `LICENSE` と `THIRD_PARTY_NOTICES.md` はバンドル内の同梱ファイルと `cmp` で一致している
- `CFBundleIdentifier`、`CFBundleExecutable`、`CFBundleName`、`CFBundleDisplayName`、`LSUIElement=false` の exact check が成功している
- active macOS GUI session で `.build/NapeGesture.app/Contents/MacOS/nape-gesture gui-smoke --config <tmp> --json --assert` が成功し、通常 GUI activation policy、設定ウィンドウ、status item `NG`、通常アプリメニュー、status menu の生成契約を検査している。CI runner に active console session がなく skip された場合は、ローカル completion evidence を PR または Issue に残している
- `.app` を通常 GUI アプリとして起動し、設定ウィンドウを初期表示する方針と矛盾していない
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
