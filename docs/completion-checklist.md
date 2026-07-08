# 完成判定チェックリスト

この文書は Issue #16「完成判定チェックリストを実測証跡で埋める」で使う証跡台帳です。
最終完成判定では、この文書の matrix を正本として、各行に実測ログ、コマンド出力、PR、Issue コメントへのリンクを埋めます。
Issue #16 は実機作業が残るため、この台帳を作っただけでは close しません。

## 証跡保存場所

証跡ログはリポジトリへ追加せず、次のようなディレクトリ名で保存します。
`artifacts/` は `.gitignore` 対象とし、GitHub Issue / PR にはログ本体ではなく要約と保存先を残します。

```text
artifacts/completion/YYYY-MM-DD/<scenario>/
```

例:

- `artifacts/completion/2026-07-09/build-and-tests/`
- `artifacts/completion/2026-07-09/doctor-app-runtime/`
- `artifacts/completion/2026-07-09/nape-pro-hid-identification/`
- `artifacts/completion/2026-07-09/spaces-mission-control/`

各 scenario には、実行コマンドを残す `commands.txt`、標準出力または JSON を残す `*.json` / `*.jsonl`、画面操作が必要だった場合の短い観察メモ `notes.md` を置きます。
runtime event 証跡は、総合状態を機械判定するために `status.json` も置きます。
PR や Issue へは、ログ本体ではなく、保存場所、主要コマンド、判定結果、未検証事項を証跡コメントとして残します。

## 直近の証跡

次の証跡は、機械証跡は証跡取得対象 commit `dddb58306f5971dace4527d0457b201827dc4554` の main、GUI 権限復旧導線追加後の runtime event blocker は main `d9004a5` に対して採用します。
後続 PR で文書や証跡収集スクリプトだけを更新した場合、完成判定では証跡取得対象 commit と文書の最新 commit を分けて扱います。

- 機械証跡 root: `artifacts/completion/2026-07-09/machine-evidence-pr59-main-dddb583`
- 機械証跡 summary: `artifacts/completion/2026-07-09/machine-evidence-pr59-main-dddb583/summary.md`
- 機械証跡 Issue コメント: https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451
- runtime event 外部ブロッカー root: `artifacts/completion/2026-07-09/runtime-event-evidence-app-pr59-main-dddb583`
- runtime event 外部ブロッカー summary: `artifacts/completion/2026-07-09/runtime-event-evidence-app-pr59-main-dddb583/summary.md`
- runtime event 外部ブロッカー Issue コメント: https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919020358
- runtime event status JSON root: `artifacts/completion/2026-07-09/runtime-event-status-json`
- runtime event status JSON: `artifacts/completion/2026-07-09/runtime-event-status-json/status.json`
- runtime event preflight: `artifacts/completion/2026-07-09/runtime-event-status-json/preflight/`
- doctor permission target root: `artifacts/completion/2026-07-09/doctor-permission-target`
- doctor permission target summary: `artifacts/completion/2026-07-09/doctor-permission-target/summary.md`
- settings UI field catalog root: `artifacts/completion/2026-07-09/settings-ui-field-catalog`
- settings UI field catalog summary: `artifacts/completion/2026-07-09/settings-ui-field-catalog/summary.md`
- benchmark percentile metrics root: `artifacts/completion/2026-07-09/benchmark-percentile-metrics`
- benchmark percentile metrics summary: `artifacts/completion/2026-07-09/benchmark-percentile-metrics/summary.md`
- 由来ガード root: `artifacts/completion/2026-07-09/provenance-guard`
- 由来ガード summary: `artifacts/completion/2026-07-09/provenance-guard/summary.md`
- GUI アプリ起動 root: `artifacts/completion/2026-07-09/gui-app-mode`
- GUI アプリ起動 summary: `artifacts/completion/2026-07-09/gui-app-mode/summary.md`
- GUI アプリ runtime event blocker root: `artifacts/completion/2026-07-09/runtime-event-gui-permission-main-d9004a5`
- GUI アプリ runtime event blocker summary: `artifacts/completion/2026-07-09/runtime-event-gui-permission-main-d9004a5/summary.md`
- GUI アプリ runtime event blocker status: `artifacts/completion/2026-07-09/runtime-event-gui-permission-main-d9004a5/status.json`
- GUI アプリ runtime event blocker doctor: `artifacts/completion/2026-07-09/runtime-event-gui-permission-main-d9004a5/doctor/doctor-debug.json`
- GUI アプリ runtime event blocker Issue コメント: [#16](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4920133711), [#6](https://github.com/char5742/nape-gesture/issues/6#issuecomment-4920133714), [#12](https://github.com/char5742/nape-gesture/issues/12#issuecomment-4920133722)
- GUI 権限復旧導線 root: `artifacts/completion/2026-07-09/gui-permission-recovery-actions`
- GUI 権限復旧導線 summary: `artifacts/completion/2026-07-09/gui-permission-recovery-actions/summary.md`

上記の `artifacts/` は Git 管理外です。再現する場合は、それぞれ次のコマンドを実行します。

```sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/machine-evidence-pr59-main-dddb583 sh scripts/collect-completion-evidence.sh
NAPE_RUNTIME_EVENT_USE_APP_BUNDLE=1 NAPE_RUNTIME_EVENT_ARTIFACT_ROOT=artifacts/completion/2026-07-09/runtime-event-evidence-app-pr59-main-dddb583 sh scripts/collect-runtime-event-evidence.sh
NAPE_RUNTIME_EVENT_USE_APP_BUNDLE=1 NAPE_RUNTIME_EVENT_ARTIFACT_ROOT=artifacts/completion/2026-07-09/runtime-event-status-json sh scripts/collect-runtime-event-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/doctor-permission-target sh scripts/collect-completion-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/settings-ui-field-catalog sh scripts/collect-completion-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/benchmark-percentile-metrics sh scripts/collect-completion-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/provenance-guard sh scripts/collect-completion-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/gui-app-mode sh scripts/collect-completion-evidence.sh
NAPE_RUNTIME_EVENT_USE_APP_BUNDLE=1 NAPE_RUNTIME_EVENT_ARTIFACT_ROOT=artifacts/completion/2026-07-09/runtime-event-gui-permission-main-d9004a5 sh scripts/collect-runtime-event-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/gui-permission-recovery-actions sh scripts/collect-completion-evidence.sh
```

runtime event 証跡は、最新の `.build/NapeGesture.app` でも `accessibilityTrusted: false` により実イベント投稿へ進まず、外部ブロッカーとして記録されています。空ログや未実行シナリオを完成証跡として扱いません。
`runtime-event-gui-permission-main-d9004a5/status.json` では `status: "blocked"`、`blockerCode: "accessibility.missing"` として機械判定できます。
同じ artifact root の `doctor/doctor-debug.json` では `runtimeIdentity.isAppBundle: true`、`bundleIdentifier: "dev.char5742.nape-gesture"`、`tccStatus.inputMonitoring.status: "granted"`、`tccStatus.accessibility.status: "missing"`、`hidProbe.succeeded: true` を確認できます。
同じ artifact root の `preflight/gesture-wheel-then-kill-switch/` と `preflight/normal-after-release/` には、TCC 判定前に成功した dry-run JSON Lines と `analyze-log` 結果を保存します。

## 状態と分類

状態は次の値で管理します。

| 状態 | 意味 |
| --- | --- |
| `未着手` | 証跡がまだない |
| `機械証跡待ち` | 実機なしで先に埋められる証跡が残っている |
| `人間作業待ち` | 物理操作または macOS UI 操作が最後の手段として残っている |
| `一部完了` | 証跡の一部はあるが、完成判定には不足がある |
| `完了` | 必要な証跡がそろい、未検証事項がない |

`need:human` はレビュー待ち、承認待ち、確認依頼、人間による判断待ちを表しません。
純正トラックパッド操作、Nape Pro 実機操作、スリープ、デバイス抜き差し、TCC 権限変更、システム設定の許可操作など、人間が手を動かして物理作業または macOS UI 操作を行う必要が最後の手段として残る項目だけに使います。
人間依存は最小化し、依頼前に dry-run、fixtures、Reference Target App、System Behavior Test、保存済みログ解析、権限済み環境での CGEvent 投稿で代替できる証跡を埋めます。
`完了` は、その行の必要証跡が現行 main でそろい、人間作業も残っていない場合にだけ使います。
`証跡リンク / 保存先` が `未設定` の行や、実機・TCC・公証などの外部作業が残る行は、状態にかかわらず最終完成扱いにしません。

## 完成判定 matrix

| 完成要件 | 必要な証跡 | 機械で先に埋める証跡 | 最後の手段として人間が必要な証跡 | 証跡リンク / 保存先 | 関連 Issue | 現在状態 |
| --- | --- | --- | --- | --- | --- | --- |
| debug / release build | `swift build` と `swift build -c release` の成功ログ | `swift build`、`swift build -c release` の stdout/stderr と終了コード | なし | `machine-evidence-pr59-main-dddb583/build-and-tests/`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #2, #15, #16 | `完了` |
| core tests | `nape-gesture-core-tests` の成功ログ | コアテストの stdout/stderr と終了コード | なし | `machine-evidence-pr59-main-dddb583/build-and-tests/core-tests.log`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #2, #16 | `完了` |
| app bundle / 署名 / 公証 | `.app` 作成、`verify-bundle`、bundle identity、通常 GUI app identity、署名検証、公証、stapler / Gatekeeper 評価のログ | `swift build -c release`、`bundle-app --replace`、`verify-bundle`、`CFBundleIdentifier` / `CFBundleExecutable` / `CFBundleName` / `CFBundleDisplayName` / `LSUIElement=false` の exact check、未署名時の `--require-signature` 期待失敗、ad-hoc 署名と署名必須検証、ライセンス同梱確認 | Developer ID 証明書、App Store Connect 認証情報、キーチェーン確認、公証提出が必要な場合の macOS UI または認証操作 | `machine-evidence-pr59-main-dddb583/bundle/`, `gui-app-mode/bundle/info-plist-identity-check.log`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #15, #16 | `一部完了` |
| 設定 UI / 主要ジェスチャー調整 | `.app` 起動時に設定ウィンドウが開き、設定 UI から activation button、感度、加速度、慣性、キャンセル条件、対象デバイス、対象入力の紐づけ秒、主要割り当てを編集できる証跡 | `SettingsUIField.descriptors` の編集対象設定パス、control kind、JSON round-trip、アプリ別設定なしの core test、`GestureAction.settingsSelectableActions` と `GestureAction.allCases` の網羅性テスト、`GUIAppLaunchPresenter.regularGUIApp` の通常 GUI 起動方針 core test、設定バリデーション、設定 JSON round-trip、`LSUIElement=false` の bundle identity check | 最終的な `.app` 起動、Dock 表示、設定ウィンドウ表示、保存操作の目視操作確認 | `gui-app-mode/build-and-tests/core-tests.log`, `gui-app-mode/bundle/info-plist-identity-check.log`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #11, #16 | `一部完了` |
| doctor 権限・runtimeIdentity | 実利用する `.app` または実行ファイルでの `doctor --probe-hid --benchmark-events ... --json --assert-runtime-ready` | `doctor --json` の `runtimeIdentity`、`runtimeReadiness`、`tccStatus`、`tccStatus.permissionTarget`、`grantRequired`、`targetDeviceDiagnostics`、`settingsValidationIssues`、benchmark 部分、`--assert-runtime-ready` の期待失敗 code、`PermissionRecoveryPresenter` の権限別 System Settings 導線 core test | システム設定でアクセシビリティと入力監視を実利用主体へ許可し、権限反映後に再実行する操作 | `machine-evidence-pr59-main-dddb583/doctor-and-performance/`, `runtime-event-gui-permission-main-d9004a5/doctor/doctor-debug.json`, [GUI アプリ blocker コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4920133711) | #11, #13, #15, #16, #74 | `人間作業待ち` |
| Nape Pro HID 識別 | `devices --all --json`、Nape Pro 操作中の `hid-log`、`analyze-hid-log`、確定 matcher | `devices --all --json`、既存ログの解析、`analyze-hid-log`、`doctor --json` の `targetDeviceDiagnostics.bestEvaluation.mismatches` | Nape Pro 実機を接続して操作する物理作業 | `machine-evidence-pr59-main-dddb583/hid-inventory/devices-all.json`, `machine-evidence-pr59-main-dddb583/fixtures-analysis/analyze-sample-hid.txt`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #4, #16 | `人間作業待ち` |
| targetDeviceAssociation 実測 | Nape Pro HID 入力とイベントタップ入力の時刻差分、`associationWindow` の採用根拠、巻き込みなし確認 | `analyze-association --json --assert-valid-window --target-stable-id <ID>`、互換 HID usage 判定、runtime 非対応 AC Pan expected failure、非互換 HID 近傍 expected failure、対象外デバイス単体 expected failure、複数 HID デバイス採用 expected failure、保存済み HID / CGEvent / target log の時刻差分解析、設定検証、境界値テスト | Nape Pro と通常入力デバイスを同じ環境で操作し、実測分布と巻き込み有無を取る作業 | `machine-evidence-pr59-main-dddb583/fixtures-analysis/*association*`, [PR #59 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4918994890), [再収集コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #5, #16 | `一部完了` |
| 元入力抑制 | ジェスチャー成立後に未マークのクリック、ドラッグ、ホイール、キーが前面アプリへ漏れず、生成イベントが AppKit に届く target log | `scripts/collect-runtime-event-evidence.sh`、`target --out`、`system-test run`、`analyze-target-log --assert-no-leaks --assert-has-generated-event`、fixtures 回帰 | 実行主体へのアクセシビリティ許可。Nape Pro 実機で最終確認する場合は成立ジェスチャー操作 | `machine-evidence-pr59-main-dddb583/fixtures-analysis/*target-log*`, `runtime-event-gui-permission-main-d9004a5/summary.md`, `runtime-event-gui-permission-main-d9004a5/status.json`, [#6 blocker コメント](https://github.com/char5742/nape-gesture/issues/6#issuecomment-4920133714) | #6, #16 | `人間作業待ち` |
| 通常クリック / ドラッグ / ホイール通過 | ジェスチャーボタン未押下時と解放後に通常クリック、通常ドラッグ、通常ホイールが過剰抑制されない target log | `scripts/collect-runtime-event-evidence.sh`、`system-test run --scenario normal-after-release --dry-run --log-json`、`analyze-log --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel`、`analyze-target-log --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel`、欠落 fixture 回帰 | 実行主体へのアクセシビリティ許可。実デバイスで通常クリック、ドラッグ、ホイールを最終確認する場合の物理操作 | `machine-evidence-pr59-main-dddb583/system-test-dry-run/system-normal-after-release*`, `runtime-event-gui-permission-main-d9004a5/preflight/normal-after-release/`, [#6 blocker コメント](https://github.com/char5742/nape-gesture/issues/6#issuecomment-4920133714) | #6, #16 | `人間作業待ち` |
| 純正トラックパッド比較 | 純正トラックパッド操作ログ、生成イベントログ、比較結果、差分理由 | `generate-scroll --dry-run --log-json`、`derive-parameters --json --assert-complete`、`compare-log`、保存済みログ解析 | 純正トラックパッドで Spaces、スクロール、ズームなどを操作してログを取る作業 | `machine-evidence-pr59-main-dddb583/fixtures-analysis/compare-sample-scroll.txt`, `machine-evidence-pr59-main-dddb583/fixtures-analysis/derive-*`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #7, #8, #9, #10, #16 | `人間作業待ち` |
| Spaces / Mission Control | Finder など前面時の `system-test` 実行ログ、生成イベントログ、画面挙動メモ、公開 API の限界がある場合の根拠 | `system-test list`、`system-test run --dry-run --log-json`、Reference Target App での AppKit 受信ログ | アクセシビリティ許可済み環境で Spaces / Mission Control の画面遷移を実測する操作 | `machine-evidence-pr59-main-dddb583/system-test-dry-run/system-space-*`, `machine-evidence-pr59-main-dddb583/system-test-dry-run/system-mission-control*`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #9, #16 | `人間作業待ち` |
| ページ戻る / 進む / ズーム / 横スクロール | Safari または Reference Target App でのシナリオ別ログ、画面挙動メモ、割り当てとパラメータ | `system-test run --scenario page-back/page-forward/zoom-in/zoom-out/horizontal-scroll --dry-run --log-json`、`analyze-log`、`target --out`、`analyze-target-log --assert-has-gesture` | Safari など対象アプリでページ遷移、ズーム、横スクロールを実操作して確認 | `machine-evidence-pr59-main-dddb583/system-test-dry-run/system-page-*`, `machine-evidence-pr59-main-dddb583/system-test-dry-run/system-zoom-*`, `machine-evidence-pr59-main-dddb583/system-test-dry-run/system-horizontal-scroll*`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #10, #16 | `人間作業待ち` |
| キルスイッチ | `Control + Option + Command + G` で生成と慣性が止まり、再有効化条件が限定される証跡 | `RuntimeSafetyState` の回帰テスト、`system-test run --scenario kill-switch --dry-run --log-json`、`analyze-log --json --assert-kill-switch-shortcut`、`system-test run --scenario gesture-wheel-then-kill-switch --dry-run --log-json`、`analyze-log --json --assert-kill-switch-shortcut --assert-gesture-before-kill-switch`、`scripts/collect-runtime-event-evidence.sh`、daemon 停止ログ、target log、`analyze-target-log --assert-no-leaks` | 実行主体へのアクセシビリティ許可。物理キーボード由来イベントまで最終証跡に含める場合のみ実操作 | `machine-evidence-pr59-main-dddb583/system-test-dry-run/system-kill-switch*`, `runtime-event-gui-permission-main-d9004a5/preflight/gesture-wheel-then-kill-switch/`, `runtime-event-gui-permission-main-d9004a5/summary.md`, [#12 blocker コメント](https://github.com/char5742/nape-gesture/issues/12#issuecomment-4920133722) | #12, #16 | `人間作業待ち` |
| スリープ復帰 / 抜き差し / 権限変更後復旧 | スリープ復帰、Nape Pro 抜き差し、TCC 権限変更後の停止、再試行、復旧ログ | `RuntimeRecoveryState` の回帰テスト、`RuntimeStatusPresenter` の UI 表示回帰テスト、`PermissionRecoveryPresenter` の権限別復旧導線テスト、`doctor --probe-hid --json`、設定検証、権限未許可時のエラー出力 | Mac のスリープ復帰、実デバイス抜き差し、システム設定での TCC 権限変更 | `machine-evidence-pr59-main-dddb583/build-and-tests/core-tests.log`, `runtime-event-gui-permission-main-d9004a5/doctor/doctor-debug.json`, [GUI アプリ blocker コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4920133711) | #13, #16, #74 | `人間作業待ち` |
| 性能 | 純粋ロジック benchmark、doctor benchmark、常駐 CPU、tap-to-post または同等の入力遅延測定 | `benchmark --events ... --json --assert-baseline`、`doctor --benchmark-events ... --json`、`BenchmarkReport.schemaVersion: 3`、認識器とスクロール計画の batch p95 / p99、結果の基準照合 | 権限済み実行主体で常駐中の CPU と実入力遅延を測る操作 | `machine-evidence-pr59-main-dddb583/doctor-and-performance/benchmark-debug.json`, `machine-evidence-pr59-main-dddb583/doctor-and-performance/doctor-debug.json`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #14, #16 | `一部完了` |
| ライセンス / 由来 | `LICENSE`、`THIRD_PARTY_NOTICES.md`、バンドル内同梱、Mac Mouse Fix 由来コードを含まない説明、repo-local 由来ガード | `verify-bundle`、ファイル存在確認、`cmp` による原本一致確認、依存通知確認、README / docs の説明確認、`sh scripts/check-provenance.sh` | 公開配布物を最終成果物として目視確認する場合のみ | `machine-evidence-pr59-main-dddb583/bundle/license-cmp.log`, `machine-evidence-pr59-main-dddb583/bundle/third-party-notices-cmp.log`, `provenance-guard/provenance/check-provenance.log`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #1, #15, #16 | `一部完了` |

## 先に自動実行するコマンド束

実機や TCC 操作なしで先に埋められる機械証跡は、次のスクリプトを正とします。
スクリプトは実行ビットなしで管理し、必ず `sh` 経由で実行します。

```sh
sh scripts/collect-completion-evidence.sh
```

既定の証跡 root は `artifacts/completion/$(date +%F)/machine-evidence` です。
保存先を変える場合は `NAPE_COMPLETION_ARTIFACT_ROOT` を指定します。

```sh
NAPE_COMPLETION_ARTIFACT_ROOT=/tmp/nape-completion-machine-evidence sh scripts/collect-completion-evidence.sh
```

スクリプトは `commands.txt` と `summary.md` を出力し、由来ガード、debug / release build、core tests、app bundle 作成と検証、bundle identity exact check、`LSUIElement=false` の通常 GUI app check、未署名時の署名必須検証の期待失敗、ad-hoc 署名、署名済み bundle 検証、ライセンス原本一致、doctor、`doctor --json` の `runtimeReadiness` / `tccStatus` / `permissionTarget` / `grantRequired` / `targetDeviceDiagnostics` 存在確認、`doctor --probe-hid`、`doctor --assert-runtime-ready` の期待失敗と failure code、`benchmark --assert-baseline`、benchmark JSON の `schemaVersion: 3` / batch p95 / p99 field check、system-test dry-run と `analyze-log --assert-system-scenario`、生成スクロール dry-run、fixture 解析、`derive-parameters --json --assert-complete`、`devices --all --json` を収集します。
`sh scripts/check-provenance.sh` は、外部ソースを読まずに tracked files だけを対象とし、Mac Mouse Fix 由来の code-like identifier 混入、説明文の配置範囲、README / `THIRD_PARTY_NOTICES.md` / PR template / PR review checklist の由来方針維持を確認します。このチェックは法的な完全証明ではなく、由来混入の早期検出ガードとして扱います。
`Fixtures/clean-association-event-log.jsonl` の `analyze-association --assert-valid-window --target-stable-id <ID>` は、解析対象イベントがすべて `associationWindow` 内に収まることを記録します。
`Fixtures/sample-association-event-log.jsonl` の `analyze-association --assert-valid-window --target-stable-id <ID>` は、window 外のイベントを検出して非ゼロ終了することを期待値として記録します。
`Fixtures/empty-association-hid-log.jsonl`、`Fixtures/association-scroll-mismatch-*.jsonl`、`Fixtures/association-ac-pan-*.jsonl`、`Fixtures/association-button-mismatch-*.jsonl`、`Fixtures/association-non-target-*.jsonl`、`Fixtures/association-mixed-device-*.jsonl` は、空 HID、usage 不一致、runtime 非対応 AC Pan、対象外デバイス単体、複数 HID デバイス採用を有効な対象デバイス紐づけ証跡として扱わないことを expected failure として記録します。
`Fixtures/leaky-target-log.jsonl` の `analyze-target-log --assert-no-leaks` は、漏れ候補を検出して非ゼロ終了することを期待値として記録します。
`Fixtures/clean-target-log.jsonl` の `analyze-target-log --assert-has-generated-event` は、ジェスチャー生成シナリオで Nape Gesture 由来イベントが AppKit に届くことを記録します。
`Fixtures/no-generated-target-log.jsonl` の `analyze-target-log --assert-no-leaks --assert-has-generated-event` は、漏れ候補がなくても生成イベントがない target log をジェスチャー生成成立証跡として扱わないことを期待値として記録します。
`Fixtures/normal-input-target-log.jsonl` の `analyze-target-log --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel` は、通常クリック / 通常ドラッグ / 通常ホイールが AppKit に届くことを個別に記録します。
`Fixtures/normal-input-missing-click-target-log.jsonl`、`Fixtures/normal-input-missing-drag-target-log.jsonl`、`Fixtures/normal-input-missing-wheel-target-log.jsonl` は、欠落した種類を expected failure として記録し、3種類の判定が同じカウントへ退行しないことを固定します。
`system-test run --scenario normal-after-release --dry-run --log-json` と `analyze-log --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel` は、解放後の通常入力通過シナリオが未生成の通常クリック、通常ドラッグ、通常ホイールを含み、activation button やキルスイッチの未生成キーだけを通常入力通過証跡として扱わないことを記録します。
`Fixtures/gesture-target-log.jsonl` の `analyze-target-log --assert-has-gesture` は、Reference Target App が `swipe`、`magnify`、`rotate` を同じ target log 形式で解析できることを記録します。
`system-test run --scenario kill-switch --dry-run --log-json` と `analyze-log --assert-kill-switch-shortcut` は、物理キーボード操作なしで `Control + Option + Command + G` 相当の未生成 `keyDown` / `keyUp` と modifier flags を生成できることを記録します。
`system-test run --scenario gesture-wheel-then-kill-switch --dry-run --log-json` と `analyze-log --assert-kill-switch-shortcut --assert-gesture-before-kill-switch` は、未生成ホイール入力がある進行中ジェスチャー状態でキルスイッチを投入する前段証跡を記録します。
`system-test run --scenario page-back/page-forward/zoom-in/zoom-out --dry-run --log-json` と `analyze-log --json --assert-system-scenario <name>` は、Safari や対応アプリで実操作する前に、`systemTestScenario`、`sequenceIndex`、離散割り当ての keyDown / keyUp、keyCode、余計な modifier を含まない exact modifier flags を同じ JSON Lines 形式と終了コードで記録します。
`SettingsUIField.descriptors` の core test は、設定 UI が activation button、対象入力の紐づけ秒、感度、加速度、慣性、キャンセル条件、対象デバイス、主要割り当ての設定パスを網羅し、control kind、表示名重複なし、設定パス重複なし、アプリ別設定なし、JSON round-trip を満たすことを記録します。
`GUIAppLaunchPresenter.regularGUIApp` の core test は、通常 GUI activation policy、起動時設定ウィンドウ表示、Dock 再オープン時の再表示、メニューバー `NG` 常駐 UI 維持、`LSUIElement=false` の方針を固定します。
`GestureAction.settingsSelectableActions` の core test は、設定 UI の割り当て候補が Mission Control、Spaces、ページ戻る/進む、ズーム、横スクロールを含む全 `GestureAction` を網羅することを記録します。
`Fixtures/sample-tuning-trackpad-log.jsonl` の `derive-parameters --json --assert-complete` は、純正トラックパッド実測ログ取得後に deadZone、加速度、慣性候補を同じ形式で保存し、未導出や警告がない場合だけ完了証跡として扱えることを記録します。
`Fixtures/sample-log.jsonl` の `derive-parameters --json --assert-complete` は、移動速度、慣性、timestamp 品質が足りないログを完了証跡として扱わず非ゼロ終了することを期待値として記録します。
`Fixtures/synthetic-timestamp-tuning-trackpad-log.jsonl` の `derive-parameters --json --assert-complete` は、候補値が出ていても合成 timestamp 警告が残るログを完了証跡として扱わず非ゼロ終了することを期待値として記録します。
`doctor --probe-hid --json` は、入力監視プローブの実行有無、成否、復旧手順、`runtimeIdentity`、`runtimeReadiness`、`tccStatus`、`tccStatus.permissionTarget`、`grantRequired` を保存します。ただし、TCC や対象デバイスの外部状態が残る場合は完了扱いにしません。
`doctor --json --assert-runtime-ready` は、HID probe 未実行や対象デバイス不一致など runtime 開始前提を満たさない診断を非ゼロ終了として記録します。期待失敗では `runtimeReadiness.failures[].code` に `inputMonitoring.notProbed` や `targetDevice.notFound` が含まれ、`targetDeviceDiagnostics.bestEvaluation` で matcher 不一致理由を確認できることも確認します。権限付与後の最終採否は、実利用主体で `--probe-hid --assert-runtime-ready` を併用した終了コードと `runtimeReadiness.ready` で行います。
`RuntimeStatusPresenter` の core test は、常駐 UI が実行中、停止中、自動再試行中、スリープ待機中を表示し、開始 / 緊急停止 / 停止の有効状態を復旧状態に合わせることを記録します。
`PermissionRecoveryPresenter` の core test は、アクセシビリティと入力監視の状態、System Settings URL、権限対象、権限変更後の再起動案内を分けて表示し、未許可または未判定の場合だけ該当設定を開く導線を必須表示することを記録します。
その他のコマンド、または `devices --all --json` が失敗した場合、スクリプト全体は非ゼロ終了し、`summary.md` に確認すべきログを残します。

このスクリプトで埋められるのは機械証跡だけです。
Nape Pro 実機、純正トラックパッド、TCC、Spaces / Mission Control の画面挙動、`run`、実イベント投稿、target 実測、常駐 CPU、入力遅延、Developer ID 署名、公証、stapler、Gatekeeper 評価は未完了のままです。
これらは実機または macOS UI 操作を伴う証跡がそろうまで、完成扱いにしません。

実イベント投稿や target log を使う半自動証跡は、アクセシビリティ許可済みの実行主体でのみ完成判定へ採用します。
`doctor --json` の `runtimeIdentity` が日常利用する `.app` または実行ファイルと一致しない場合、その証跡は参考扱いです。
Issue #6 / #12 の実 event tap 経路は、アクセシビリティ許可済み環境で次のスクリプトを正として収集します。

```sh
sh scripts/collect-runtime-event-evidence.sh
```

実利用する `.build/NapeGesture.app` に TCC 権限を集約する場合は、次の環境変数で release build、`.app` 作成、bundle 検証、runtime event 証跡を一続きに実行します。

```sh
NAPE_RUNTIME_EVENT_USE_APP_BUNDLE=1 sh scripts/collect-runtime-event-evidence.sh
```

このスクリプトは `status.json`、`commands.txt`、`summary.md`、`doctor/doctor-debug.json`、`preflight/`、権限済みの場合の `scenarios/` を出力します。
`status.json.status` は `success`、`blocked`、`failed` のいずれかで、TCC 外部ブロッカーは `blockerCode` で確認します。
このスクリプトは `doctor --json` で `accessibilityTrusted: true` と HID 入力監視プローブ成功を確認してから、`run`、Reference Target App、未マーク `system-test`、`analyze-target-log` を組み合わせます。
TCC 判定前に `gesture-wheel-then-kill-switch` と `normal-after-release` の dry-run preflight を保存するため、実イベント未実行時も計画イベント列の前段証跡は残ります。
アクセシビリティ未許可または HID 入力監視プローブ未成功の場合は実イベントを投稿せず、外部ブロッカーとして `summary.md` に runtimeIdentity と該当診断を残します。

## 最後に人間が必要な作業リスト

次の作業は、機械証跡を先に埋めても代替できない場合だけ実施します。

- システム設定で、実利用する `.app` または実行ファイルへアクセシビリティと入力監視を許可する。
- `.app` を通常起動し、Dock 表示、設定ウィンドウ表示、メニューバーの `NG` メニュー、保存操作を確認する。
- Nape Pro を接続し、`hid-log` 実行中にボタン、移動、ホイールなどを操作する。
- 純正トラックパッドで Spaces、Mission Control、ページ戻る/進む、ズーム、横スクロール相当のログを取る。
- Nape Pro 操作で同じシナリオを実行し、target log、CGEvent log、画面挙動を保存する。
- 通常クリック、通常ドラッグ、通常ホイールがジェスチャー処理後も壊れていないことを前面アプリで確認する。
- キルスイッチを実行中に押し、生成と慣性が止まり、通常入力が過剰抑制されないことを確認する。
- Mac をスリープ復帰させ、Nape Pro の抜き差しを行い、TCC 権限を一時的に変更して復旧導線を確認する。
- Developer ID 署名、公証、stapler、Gatekeeper 評価に必要な認証操作を行う。

人間作業で観察した内容は、必ず同じ scenario ディレクトリのログと対応付けます。
目視だけの「動いた」は完成証跡にせず、画面挙動メモは JSON / JSON Lines / コマンドログを補う材料として扱います。
