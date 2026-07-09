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
- Grok CLI を使った補助レビューがある場合でも、指摘採否、テスト、CI、merge 判断はメインスレッドが責任を持つ
- Grok 運用ルールを変えた場合、`AGENTS.md`、[ADR-0027](adr/0027-grok-cli-auxiliary-review.md)、[ADR-0029](adr/0029-grok-operational-surface.md)、必要なら `$grok-auxiliary-review` skill の同期を確認している
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
- `began` / `changed` / `ended` / `cancelled` / `momentum` の意味が崩れていない
- 方向ロック、加速度、キャンセル条件、慣性のテストが追加または更新されている

## Runtime / Event Tap 変更

- 自前生成イベントを再解釈しない
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

## 生成イベント / Spaces / Mission Control 変更

- 通常スクロールのフェーズは `scrollPhase`、慣性は `momentumPhase` に分離されている
- `generate-scroll --dry-run --log-json` で比較可能な JSON Lines を出せる
- `system-test run --dry-run --log-json` で生成予定イベントを保存し、`systemTestScenario` / `sequenceIndex` つきで `analyze-log --json --assert-system-scenario <name>` によるシナリオ別機械判定を通している
- `Ctrl + ←/→` などのショートカット送信を最終解として前提化していない
- Finder、Safari、Mission Control、Spaces で必要な実機検証が明記されている

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
