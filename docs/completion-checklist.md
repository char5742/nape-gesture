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

次の証跡は、最新の機械証跡は証跡取得対象 commit `e22aa52a4565743d1530e6da87f12c5e480515fc` の main、GUI 権限付与後の runtime event 最新成功証跡は `runtime-event-kill-switch-release-suppression`、最新 GUI computer-use / System Events 画面証跡は main `24f0f7f1026918caa85912ae52b441350f4edd4b` に対して採用します。
GUI smoke 証跡は `gui-smoke` コマンド導入後の commit で採用し、PR merge 後の Issue コメントに対象 commit と CI run を残します。
後続 PR で文書や証跡収集スクリプトだけを更新した場合、完成判定では証跡取得対象 commit と文書の最新 commit を分けて扱います。

- 最新機械証跡 root: `artifacts/completion/2026-07-10/machine-evidence-main-e22aa52`
- 最新機械証跡 summary: `artifacts/completion/2026-07-10/machine-evidence-main-e22aa52/summary.md`
- 最新機械証跡 Issue コメント: https://github.com/char5742/nape-gesture/issues/16#issuecomment-4926823166
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
- GUI アプリ runtime event 最新 root: `artifacts/completion/2026-07-09/runtime-event-open-absolute-paths-final`
- GUI アプリ runtime event 最新 summary: `artifacts/completion/2026-07-09/runtime-event-open-absolute-paths-final/summary.md`
- GUI アプリ runtime event 最新 status: `artifacts/completion/2026-07-09/runtime-event-open-absolute-paths-final/status.json`
- GUI アプリ runtime event 最新 doctor: `artifacts/completion/2026-07-09/runtime-event-open-absolute-paths-final/doctor/doctor-debug.json`
- GUI アプリ runtime event 最新 Issue コメント: [#16](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4926725190), [#6](https://github.com/char5742/nape-gesture/issues/6#issuecomment-4926725331), [#12](https://github.com/char5742/nape-gesture/issues/12#issuecomment-4926725580)
- GUI アプリ runtime event 成功 root: `artifacts/completion/2026-07-09/runtime-event-kill-switch-release-suppression`
- GUI アプリ runtime event 成功 summary: `artifacts/completion/2026-07-09/runtime-event-kill-switch-release-suppression/summary.md`
- GUI アプリ runtime event 成功 status: `artifacts/completion/2026-07-09/runtime-event-kill-switch-release-suppression/status.json`
- GUI アプリ runtime event 成功 doctor: `artifacts/completion/2026-07-09/runtime-event-kill-switch-release-suppression/doctor/doctor-debug.json`
- GUI 権限復旧導線 root: `artifacts/completion/2026-07-09/gui-permission-recovery-actions`
- GUI 権限復旧導線 summary: `artifacts/completion/2026-07-09/gui-permission-recovery-actions/summary.md`
- GUI computer-use 最新 root: `artifacts/completion/2026-07-10/gui-computer-use-main-24f0f7f`
- GUI computer-use 最新 summary: `artifacts/completion/2026-07-10/gui-computer-use-main-24f0f7f/summary.md`
- GUI computer-use 最新 Dock AX log: `artifacts/completion/2026-07-10/gui-computer-use-main-24f0f7f/logs/dock-nape-gesture-items.txt`
- GUI computer-use 最新 Issue コメント: https://github.com/char5742/nape-gesture/issues/16#issuecomment-4926976780
- GUI computer-use 保存操作 root: `artifacts/completion/2026-07-09/gui-computer-use-main-f43e217`
- GUI computer-use 保存操作 summary: `artifacts/completion/2026-07-09/gui-computer-use-main-f43e217/summary.md`
- GUI computer-use doctor: `artifacts/completion/2026-07-09/gui-computer-use-main-f43e217/doctor/doctor-app.json`
- GUI smoke script root: `artifacts/completion/2026-07-09/gui-smoke-script-check`
- GUI smoke script JSON: `artifacts/completion/2026-07-09/gui-smoke-script-check/gui-smoke/gui-smoke-app.json`

上記の `artifacts/` は Git 管理外です。再現する場合は、それぞれ次のコマンドを実行します。

```sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-10/machine-evidence-main-e22aa52 sh scripts/collect-completion-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/machine-evidence-pr59-main-dddb583 sh scripts/collect-completion-evidence.sh
NAPE_RUNTIME_EVENT_USE_APP_BUNDLE=1 NAPE_RUNTIME_EVENT_ARTIFACT_ROOT=artifacts/completion/2026-07-09/runtime-event-evidence-app-pr59-main-dddb583 sh scripts/collect-runtime-event-evidence.sh
NAPE_RUNTIME_EVENT_USE_APP_BUNDLE=1 NAPE_RUNTIME_EVENT_ARTIFACT_ROOT=artifacts/completion/2026-07-09/runtime-event-status-json sh scripts/collect-runtime-event-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/doctor-permission-target sh scripts/collect-completion-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/settings-ui-field-catalog sh scripts/collect-completion-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/benchmark-percentile-metrics sh scripts/collect-completion-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/provenance-guard sh scripts/collect-completion-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/gui-app-mode sh scripts/collect-completion-evidence.sh
NAPE_RUNTIME_EVENT_USE_APP_BUNDLE=1 NAPE_RUNTIME_EVENT_ARTIFACT_ROOT=artifacts/completion/2026-07-09/runtime-event-open-absolute-paths-final sh scripts/collect-runtime-event-evidence.sh
NAPE_RUNTIME_EVENT_USE_APP_BUNDLE=1 NAPE_RUNTIME_EVENT_ARTIFACT_ROOT=artifacts/completion/2026-07-09/runtime-event-kill-switch-release-suppression sh scripts/collect-runtime-event-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/gui-permission-recovery-actions sh scripts/collect-completion-evidence.sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-09/gui-smoke-script-check sh scripts/collect-completion-evidence.sh
```

`machine-evidence-main-e22aa52/summary.md` では、由来ガード、debug / release build、core tests、`.app` 作成と検証、bundle identity、未署名 bundle の署名必須検証 expected failure、ad-hoc 署名、codesign verify、署名済み bundle 検証、license / third-party notices 同梱一致、AppKit `gui-smoke --json --assert`、`doctor` / `doctor --probe-hid` JSON、runtime readiness / TCC / permission target / targetDeviceDiagnostics field check、`doctor --assert-runtime-ready` の expected failure、benchmark p95 / p99 field check、`system-test` dry-run、fixtures 解析、`devices --all --json` が成功している。
この機械証跡の `doctor-hid-probe-debug.json` は debug executable 経路であり、`.app` の TCC 許可済み runtime event 証跡とは分けて扱う。
runtime event 証跡は、権限付与後の `.build/NapeGesture.app` で `doctor.runtimeReadiness.ready: true`、target ready diagnostics、foreground capture、元入力抑制、キルスイッチ、通常入力通過まで成功しました。`accessibility.missing` の外部ブロッカーではありません。
`runtime-event-kill-switch-release-suppression/status.json` では `status: "success"`、`failureCount: 0` として機械判定できます。
同じ artifact root の `doctor/doctor-debug.json` では `runtimeIdentity.isAppBundle: true`、`bundleIdentifier: "dev.char5742.nape-gesture"`、`tccStatus.inputMonitoring.status: "granted"`、`tccStatus.accessibility.status: "granted"`、`hidProbe.succeeded: true`、`runtimeReadiness.ready: true` を確認できます。
この`runtimeReadiness.ready: true`はtrackpad output contract gate導入前の履歴である。現行branchでは`outputContract.unsupported`をready failureへ追加したため、権限済み証跡としては残すが現在のruntime ready証跡には使わない。
同じ artifact root の `summary.md` では、`gesture-drag`、`gesture-wheel`、`kill-switch`、`gesture-wheel-then-kill-switch`、`normal-after-release` が成功し、gesture 系 runtime 性能ログも成功しています。
`runtime-event-open-absolute-paths-final` は、Reference Target App の target log 空問題を示す過去の失敗証跡として残します。空 target log は完成証跡として扱いません。
`gui-computer-use-main-24f0f7f/summary.md` では、computer-use による `.build/NapeGesture.app` の frontmost / running 観測、`Nape Gesture 設定` ウィンドウ、主要 UI 要素、System Events による `Nape Gesture` process と Dock item `NapeGesture` の観測を保存済みです。
Terminal の `screencapture` は Screen Recording 権限境界で失敗したため、この artifact では computer-use と System Events の観測ログを画面証跡として採用します。
`SystemUIServer` の Accessibility name 検索では status item が露出しなかったため、この結果だけで status item 不在とは判定しません。
`gui-computer-use-main-f43e217/summary.md` では、computer-use による `保存して再起動` 押下と設定ファイル更新、通常アプリメニューの権限導線を確認済みです。
`gui-smoke-script-check/gui-smoke/gui-smoke-app.json` では、active macOS GUI session 上の `.build/NapeGesture.app` 実行主体で AppKit 内に `activationPolicy: "regular"`、`statusItemTitle: "NG"`、設定ウィンドウ、通常アプリメニュー、status menu の状態、開始、緊急停止、停止、設定、権限導線が生成されることを `gui-smoke --config <artifact> --json --assert` で機械判定します。これは TCC 許可済み runtime、実イベント投稿、Nape Pro 実機操作の証跡ではありません。

## 状態と分類

状態は次の値で管理します。

| 状態 | 意味 |
| --- | --- |
| `未着手` | 証跡がまだない |
| `機械証跡待ち` | 実機なしで先に埋められる証跡が残っている |
| `人間作業待ち` | 物理操作または macOS UI 操作が最後の手段として残っている |
| `一部完了` | 証跡の一部はあるが、完成判定には不足がある |
| `要更新` | 要件変更により既存証跡が古くなり、現行要件での再取得が必要 |
| `完了` | 必要な証跡がそろい、未検証事項がない |

`need:human` はレビュー待ち、承認待ち、確認依頼、人間による判断待ちを表しません。
純正トラックパッド操作、Nape Pro 実機操作、スリープ、デバイス抜き差し、TCC 権限変更、システム設定の許可操作など、人間が手を動かして物理作業または macOS UI 操作を行う必要が最後の手段として残る項目だけに使います。
computer-use で代替できる GUI 表示確認、クリック、保存操作、メニュー表示確認は `need:human` にしません。
人間依存は最小化し、依頼前にdry-run、fixtures、Reference Target App、System Behavior Test、保存済みログ解析、権限済み環境でのsystem-wide event投稿で代替できる証跡を埋めます。ただし、純正trackpad driver output contractの正本は生成eventで代替せず、物理trackpad操作から取得します。
`完了` は、その行の必要証跡が現行 main でそろい、人間作業も残っていない場合にだけ使います。
`証跡リンク / 保存先` が `未設定` の行や、実機・TCC・公証などの外部作業が残る行は、状態にかかわらず最終完成扱いにしません。

## 完成判定 matrix

2026-07-11以前の単純pixel scroll、forced horizontal scroll、keyboard shortcutによるruntime / system-test証跡は、入力認識、元入力抑制、GUI、診断toolの退行確認にだけ使います。[ADR-0036](adr/0036-emulate-trackpad-driver-output-events.md)のtrackpad driver上位出力event完成証跡には使いません。

| 完成要件 | 必要な証跡 | 機械で先に埋める証跡 | 最後の手段として人間が必要な証跡 | 証跡リンク / 保存先 | 関連 Issue | 現在状態 |
| --- | --- | --- | --- | --- | --- | --- |
| debug / release build | `swift build` と `swift build -c release` の成功ログ | `swift build`、`swift build -c release` の stdout/stderr と終了コード | なし | `machine-evidence-pr59-main-dddb583/build-and-tests/`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #2, #15, #16 | `完了` |
| core tests | `nape-gesture-core-tests` の成功ログ | コアテストの stdout/stderr と終了コード | なし | `machine-evidence-pr59-main-dddb583/build-and-tests/core-tests.log`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #2, #16 | `完了` |
| app bundle / 署名 / 公証 | `.app` 作成、`verify-bundle`、bundle identity、通常 GUI app identity、署名検証、公証、stapler / Gatekeeper 評価のログ | `swift build -c release`、`bundle-app --replace`、`verify-bundle`、`CFBundleIdentifier` / `CFBundleExecutable` / `CFBundleName` / `CFBundleDisplayName` / `LSUIElement=false` の exact check、未署名時の `--require-signature` 期待失敗、ad-hoc 署名と署名必須検証、ライセンス同梱確認 | Developer ID 証明書、App Store Connect 認証情報、キーチェーン確認、公証提出が必要な場合の macOS UI または認証操作 | `machine-evidence-pr59-main-dddb583/bundle/`, `gui-app-mode/bundle/info-plist-identity-check.log`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #15, #16 | `一部完了` |
| 設定 UI / button mode | `.app` 起動時に設定ウィンドウが開き、方向別割り当てを表示せず、button 3 / 4 / 5ごとに`none`、`Scroll & Navigate`、`Spaces & Mission Control`、`Zoom`を選択できる証跡。既定button 3 / 4 / 5が順に`Scroll & Navigate` / `Spaces & Mission Control` / `Zoom`であることと、旧binding設定の安全なmigrationを含む | `SettingsUIField.descriptors`が方向別bindingを含まず3 buttonのmodeを網羅するcore test、各modeのrouting test、開始軸とsessionを維持して符号反転するproduct test、旧bindingを含む実設定ファイルの原子的migration、`GUIAppLaunchPresenter.regularGUIApp`、設定バリデーション、bundle identity、`gui-smoke --json --assert`、computer-useによるbutton mode表示 | なし。TCC許可、実イベント投稿、Nape Pro実機操作は別行で扱う | Issue #144 / PR #145のcore / product / migration test、release bundle検証、GUI smoke、computer-use AX treeで方向別項目なしと3 buttonのmode選択を確認。PR artifactへの永続化は統合時に行う | #11, #16, #144 | `進行中` |
| doctor 権限・runtimeIdentity | 実利用する `.app` または実行ファイルでの `doctor --probe-hid --benchmark-events ... --json --assert-runtime-ready` | `doctor --json` の `runtimeIdentity`、`runtimeReadiness`、`tccStatus`、`tccStatus.permissionTarget`、`grantRequired`、`targetDeviceDiagnostics`、`outputContract`、`settingsValidationIssues`、benchmark 部分、`--assert-runtime-ready` の期待失敗 code、`PermissionRecoveryPresenter` の権限別 System Settings 導線 core test | なし。2026-07-09 時点で `.build/NapeGesture.app` のアクセシビリティと入力監視は許可済み | 旧権限証跡は`machine-evidence-pr59-main-dddb583/doctor-and-performance/`など。`outputContract.supported`証跡は未設定 | #11, #13, #15, #16, #74, #117, #122, #130 | `一部完了` |
| Nape Pro HID 識別 | `devices --all --json`、Nape Pro 操作中の `hid-log`、`analyze-hid-log`、確定 matcher | `devices --all --json`、既存ログの解析、`analyze-hid-log`、`doctor --json` の `targetDeviceDiagnostics.bestEvaluation.mismatches` | Nape Pro 実機を接続して操作する物理作業 | `machine-evidence-pr59-main-dddb583/hid-inventory/devices-all.json`, `machine-evidence-pr59-main-dddb583/fixtures-analysis/analyze-sample-hid.txt`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #4, #16 | `人間作業待ち` |
| targetDeviceAssociation 実測 | Nape Pro HID 入力とイベントタップ入力の時刻差分、`associationWindow` の採用根拠、巻き込みなし確認 | `analyze-association --json --assert-valid-window --target-stable-id <ID>`、互換 HID usage 判定、runtime 非対応 AC Pan expected failure、非互換 HID 近傍 expected failure、対象外デバイス単体 expected failure、複数 HID デバイス採用 expected failure、保存済み HID / CGEvent / target log の時刻差分解析、設定検証、境界値テスト | Nape Pro と通常入力デバイスを同じ環境で操作し、実測分布と巻き込み有無を取る作業 | `machine-evidence-pr59-main-dddb583/fixtures-analysis/*association*`, [PR #59 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4918994890), [再収集コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #5, #16 | `一部完了` |
| 元入力抑制 | ジェスチャー成立後に未マークのクリック、ドラッグ、ホイール、キーが前面アプリへ漏れず、生成イベントが AppKit に届く target log | `scripts/collect-runtime-event-evidence.sh`、`target --out`、ready diagnostics、`system-test run`、`analyze-target-log --assert-no-leaks --assert-has-generated-event --assert-has-foreground-capture`、fixtures 回帰 | Nape Pro 実機で最終確認する場合は成立ジェスチャー操作 | `machine-evidence-pr59-main-dddb583/fixtures-analysis/*target-log*`, `runtime-event-kill-switch-release-suppression/summary.md`, `runtime-event-kill-switch-release-suppression/status.json`, `runtime-event-kill-switch-release-suppression/scenarios/gesture-*/analyze-target-log.json`, [#6 最新コメント](https://github.com/char5742/nape-gesture/issues/6#issuecomment-4926725331) | #6, #16 | `一部完了` |
| 通常クリック / ドラッグ / ホイール通過 | ジェスチャーボタン未押下時と解放後に通常クリック、通常ドラッグ、通常ホイールが過剰抑制されない target log | `scripts/collect-runtime-event-evidence.sh`、`system-test run --scenario normal-after-release --dry-run --log-json`、`analyze-log --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel`、`analyze-target-log --json --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel --assert-has-foreground-capture`、欠落 fixture 回帰 | 実デバイスで通常クリック、ドラッグ、ホイールを最終確認する場合のみ物理操作 | `machine-evidence-pr59-main-dddb583/system-test-dry-run/system-normal-after-release*`, `runtime-event-kill-switch-release-suppression/preflight/normal-after-release/`, `runtime-event-kill-switch-release-suppression/scenarios/normal-after-release/analyze-target-log.json`, [#6 最新コメント](https://github.com/char5742/nape-gesture/issues/6#issuecomment-4926725331) | #6, #16 | `一部完了` |
| Trackpad output event logger | 純正trackpadのevent type / subtype / raw field / serialized dataをJSON Linesへ保存し、確定captureをmanifestへ固定できる | `trackpad-event-log --duration --out --ready-file --ready-token --evidence-kind`、run固有pathの排他的ready lease、受付停止前のready撤回、deadline、安定化再検証する専用waiter、case / Unicodeを含むfile予定地の親子path拒否、captureIndex順、ordered raw field、非有限値bit pattern、bounded queue、SIGINT drain、0件期待失敗、開始 / 完了wall-clock、最終log / executable SHA、atomic manifest、physical生成marker拒否 | なし | [logger local smoke](evidence/2026-07-11-trackpad-event-logger-local-smoke.md)、[物理capture証跡](evidence/2026-07-11-physical-trackpad-contract-capture.md) | #117, #118, #125, #129, #132 | `logger完了` |
| Trackpad raw analyzer / scroll Phase 2 | 現行JSON Lines、manifest、serialized event、generated配送に加え、25F80 scroll / momentum / companion contractを機械判定できる | Phase 1 schema 1互換、Phase 1厳格parser / host / provenance、登録fixture ID / SHA / schema / OS build、document bytesとmanifestの再結合、capture index再検証、公開観測台帳と4 source identity /解析境界の照合、raw type / timestamp / continuous、scroll `1 -> 2* -> 4`、momentum `1 -> 2* -> 3`、全9 terminal deltaの`+0.0` bit pattern、generated type 29 classifier `0 / 6` allowlist、envelope、motion alias、phase / 順序 / 距離 / coverage、CLI正常系とterminal欠落 /未確定gesture異常系の終了コード`1` | なし | [ADR-0042](adr/0042-versioned-scroll-momentum-contract-comparison.md)、[Phase 2ローカル検証](evidence/2026-07-11-scroll-momentum-contract-phase2-local-verification.md)。NavigationSwipe / magnification / DockSwipeは未確定のため#129全体は未完了 | #117, #125, #129 | `scroll Phase 2完了` |
| Trackpad output session model | input / momentum lifecycle、session ID、capture order、起動後時刻、progress、終了速度、commit / cancel、terminalを全event familyで共通表現できる | `TrackpadOutputSessionMachine` pure testsで正常完結、順序欠落、上限直前のterminal、時刻逆行、現在boot外timestamp、began前change、二重terminal、stuck、非有限値、gesture decision欠落、familyと最終payload付きの明示cancelを判定する。product output境界の直接wall clock利用をCI guardで禁止する | なし | [ADR-0038](adr/0038-trackpad-output-session-and-monotonic-clock.md)。event adapterとdaemon統合は未完了 | #117, #128, #130 | `モデル完了` |
| 診断event時刻domain | `generate-scroll`、`system-test`、`DiagnosticEventPoster`がCGEventとdry-run logへmacOS起動後時刻だけを使い、投稿直前timestamp、shortcut全件生成、途中失敗時release / terminal収束を保証する | `nape-gesture-diagnostic-output-tests`のfailure injection、全13 system scenario、全48 generate patternの現在boot上限・件数・offset直接検証、`sh scripts/check-diagnostic-event-time.sh` | なし | [2026-07-11 local verification](evidence/2026-07-11-diagnostic-monotonic-clock-local-verification.md)。TCC付きevent tap到達はmain統合後に再取得する | #102 | `一部完了` |
| 純正トラックパッド比較 | 純正trackpadと生成eventを同一schemaで保存したtype、subtype、field、phase、momentum、timestamp、順序の比較結果 | logger / analyzer、[25F80観測台帳](../Fixtures/trackpad-contract/25F80/physical-observations.json)、[scroll / momentum contract](../Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json)、差分report | ready同期後にNavigationSwipe左右、pinch方向marker、DockSwipe反対方向 / cancel、Mission Control / App Exposéを追加収録する | [2026-07-11物理capture](evidence/2026-07-11-physical-trackpad-contract-capture.md)。scroll / momentumは登録fixture比較可能、他familyはcandidate /未取得を明示 | #7, #8, #117, #118, #125, #129 | `一部完了` |
| Trackpad scroll / momentum | continuous scroll eventとcompanion gesture eventのenvelope / phase / capture順上の局所対応、phase完結、momentum分離。timestamp同値や固定index差は要求しない | 25F80 fixture contract test、output model test、CGEvent contract test、Reference Targetの自動受信log | Nape Proと純正trackpadで最終体感比較する | [2026-07-11物理capture](evidence/2026-07-11-physical-trackpad-contract-capture.md)で純正scroll / momentum contractを固定。生成adapterとruntime比較は未完了 | #7, #117, #119, #125, #129 | `純正contract完了` |
| Spaces / Mission Control | DockSwipeのmotion、progress、phase、終了速度、画面連続追従、stuckなし | 25F80 fixture contract test、DockSwipe model / adapter test、system-wide output log | 純正trackpadでDockSwipe反対方向 / cancelとMission Control / App Exposéを再収録し、Nape Proで最終比較する | DockSwipeは1方向candidate。Mission Control / App Exposéは取得窓不成立。forced scroll / shortcutは参考専用 | #9, #117, #122, #125, #126, #128, #130 | `一部完了` |
| ページ戻る / 進む / ズーム / 横スクロール | NavigationSwipe、magnification / zoom、trackpad horizontal scrollのevent contractと通常OS処理結果 | 25F80 fixture contract test、output model / adapter test、Reference Target App、Safari runtime log | NavigationSwipe左右とpinch方向markerを純正trackpadで追加収録し、Nape Proで最終比較する | 横scroll contractは採用可能。NavigationSwipe / magnificationはcandidateで方向markerと完結系列待ち | #10, #117, #119, #122, #125, #127, #128, #130 | `一部完了` |
| macOS互換境界 | private contract隔離、supported / unsupported / contractMismatch、未知version fail closed | compatibility adapter test、OS build付きfixture、禁止symbol /依存方向guard | 新macOS実機で最終確認する場合のみ | 未設定 | #117, #122, #124 | `機械証跡待ち` |
| キルスイッチ | `Control + Option + Command + G` で生成と慣性が止まり、再有効化条件が限定される証跡 | `RuntimeSafetyState` の回帰テスト、`system-test run --scenario kill-switch --dry-run --log-json`、`analyze-log --json --assert-kill-switch-shortcut`、`system-test run --scenario gesture-wheel-then-kill-switch --dry-run --log-json`、`analyze-log --json --assert-kill-switch-shortcut --assert-gesture-before-kill-switch`、`scripts/collect-runtime-event-evidence.sh`、daemon 停止ログ、target log、`analyze-target-log --assert-no-leaks --assert-has-generated-event --assert-has-foreground-capture`、activation button pending release 抑制 | 物理キーボード由来イベントまで含める場合のみ実操作 | `machine-evidence-pr59-main-dddb583/system-test-dry-run/system-kill-switch*`, `runtime-event-kill-switch-release-suppression/preflight/gesture-wheel-then-kill-switch/`, `runtime-event-kill-switch-release-suppression/scenarios/gesture-wheel-then-kill-switch/analyze-target-log.json`, `runtime-event-kill-switch-release-suppression/summary.md`, [#12 最新コメント](https://github.com/char5742/nape-gesture/issues/12#issuecomment-4926725580) | #12, #16 | `一部完了` |
| スリープ復帰 / 抜き差し / 権限変更後復旧 | スリープ復帰、Nape Pro 抜き差し、TCC 権限変更後の停止、再試行、復旧ログ | `RuntimeRecoveryState` の回帰テスト、`RuntimeStatusPresenter` の UI 表示回帰テスト、`PermissionRecoveryPresenter` の権限別復旧導線テスト、`doctor --probe-hid --json`、設定検証、権限未許可時のエラー出力 | Mac のスリープ復帰、実デバイス抜き差し、システム設定での TCC 権限変更 | `machine-evidence-pr59-main-dddb583/build-and-tests/core-tests.log`, `runtime-event-open-absolute-paths-final/doctor/doctor-debug.json`, [runtime event 最新コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4926725190) | #13, #16, #74 | `人間作業待ち` |
| 性能 | 純粋ロジックbenchmark、doctor benchmark、常駐CPU、tapからtrackpad event系列投稿完了までの遅延 | `benchmark --events ... --json --assert-baseline`、doctor、recognizer / output modelのbatch p95 / p99、adapter投稿数、作成失敗、tap-to-post p95 / p99 | AppKit画面反映と体感差分は実機操作が必要 | 既存tap-to-simple-CGEvent値は参考専用。trackpad output adapter測定は未設定 | #14, #16, #117, #119, #122, #126, #127 | `一部完了` |
| ライセンス / 由来 | `LICENSE`、`THIRD_PARTY_NOTICES.md`、バンドル内同梱、実装contractとパラメータを資料・計測証跡まで追跡できる説明、実装上必要な実依存識別子と不要な外部参照の境界、repo-local 由来ガード | `verify-bundle`、ファイル存在確認、`cmp` による原本一致確認、依存通知確認、README / docs の説明確認、`sh scripts/check-provenance.sh`、`sh scripts/test-check-provenance.sh` | 公開配布物を最終成果物として目視確認する場合のみ | `machine-evidence-pr59-main-dddb583/bundle/license-cmp.log`, `machine-evidence-pr59-main-dddb583/bundle/third-party-notices-cmp.log`, `provenance-guard/provenance/check-provenance.log`, `provenance-guard/provenance/test-check-provenance.log`, [Issue #16 証跡コメント](https://github.com/char5742/nape-gesture/issues/16#issuecomment-4919012451) | #1, #15, #16 | `一部完了` |

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

スクリプトは`commands.txt`と`summary.md`を出力し、由来ガードとその回帰テストを独立ログへ保存した上で、debug / release build、core tests、app bundle、GUI smoke、署名構造、doctor、benchmark、既存system-test / fixture解析、device inventoryを収集します。trackpad driver上位output adapter統合前のsystem-test /生成scroll結果は退行確認であり、#117の完成証跡にはしません。#118以降のlogger、contract fixture、adapter testを統合後にこのscriptへ追加します。
`sh scripts/check-provenance.sh` はREADME / AGENTS / requirements / PR template / PR review checklistの一般化したrepo-local由来方針と識別子境界を確認し、`sh scripts/test-check-provenance.sh`は隔離fixtureで正常系と必須文言欠落時の失敗を検証します。特定の外部プロジェクトを識別するdenylistは保持せず、実装上必要な実依存のimport名、module / API名、設定識別子と法定通知は許容します。README、実装、コメント、テスト名、ユーザー向け文書を含むtracked files全体では、不要な外部固有名だけをレビューで除外します。`THIRD_PARTY_NOTICES.md`は実際に同梱する依存通知に限定します。このチェックは任意の固有名の自動検出や法的な完全証明ではなく、方針削除の早期検出ガードとして扱います。
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
`system-test run --scenario kill-switch --dry-run --log-json` と `analyze-log --assert-kill-switch-shortcut` は、物理キーボード操作なしで `Control + Option + Command + G` 相当の未生成 `keyDown` / `keyUp` と modifier flags を生成できることを記録します。実投稿時も同じ未マークイベント列を使い、`keyDown` / `keyUp` の間隔を `interval` で明示します。
`system-test run --scenario gesture-wheel-then-kill-switch --dry-run --log-json` と `analyze-log --assert-kill-switch-shortcut --assert-gesture-before-kill-switch` は、未生成ホイール入力がある進行中ジェスチャー状態でキルスイッチを投入する前段証跡を記録します。
`system-test run --scenario page-back/page-forward/zoom-in/zoom-out --dry-run --log-json`と`analyze-log --json --assert-system-scenario <name>`は、移行前shortcut prototypeの退行確認だけに使います。NavigationSwipe / magnification完成証跡には使いません。
`SettingsUIField.descriptors` の core test は、設定 UI がbutton 3 / 4 / 5ごとのmode、対象入力の紐づけ秒、感度、加速度、慣性、方向非依存のキャンセル条件、対象デバイスの設定パスを網羅し、方向別bindingを含まないこと、mode候補と既定値、control kind、表示名重複なし、設定パス重複なし、アプリ別設定なし、JSON round-trip を満たすことを記録します。
`GUIAppLaunchPresenter.regularGUIApp` の core test は、通常 GUI activation policy、起動時設定ウィンドウ表示、Dock 再オープン時の再表示、メニューバー `NG` 常駐 UI 維持、`LSUIElement=false` の方針を固定します。`gui-smoke --config <artifact> --json --assert` は `.app` 実行主体で AppKit 内に同じ UI 契約が実際に生成されることを確認します。
button modeの core / product test は、方向ではなく押下buttonのmodeで出力を選ぶこと、`none`が通常入力を通すこと、button 3 / 4 / 5の既定値、X / Y入力が途中で方向転換しても別modeへ切り替わらず同じsession IDとlifecycleを維持することを記録します。`Scroll & Navigate`は`scroll`経路と`NavigationSwipe`能力を区別し、adapter生成testだけをページnavigationの完成証跡にしません。旧binding migration testは、方向別bindingを含む既存設定を安全に読み込み、廃止項目を取り除き、旧値を暗黙の出力選択へ流用せず、保存後の設定と製品surfaceに方向別bindingが残らないことを記録します。
`Fixtures/sample-tuning-trackpad-log.jsonl` の `derive-parameters --json --assert-complete` は、純正トラックパッド実測ログ取得後に deadZone、加速度、慣性候補を同じ形式で保存し、未導出や警告がない場合だけ完了証跡として扱えることを記録します。
`Fixtures/sample-log.jsonl` の `derive-parameters --json --assert-complete` は、移動速度、慣性、timestamp 品質が足りないログを完了証跡として扱わず非ゼロ終了することを期待値として記録します。
`Fixtures/synthetic-timestamp-tuning-trackpad-log.jsonl` の `derive-parameters --json --assert-complete` は、候補値が出ていても合成 timestamp 警告が残るログを完了証跡として扱わず非ゼロ終了することを期待値として記録します。
`doctor --probe-hid --json` は、入力監視プローブの実行有無、成否、復旧手順、`runtimeIdentity`、`runtimeReadiness`、`tccStatus`、`tccStatus.permissionTarget`、`grantRequired` を保存します。ただし、TCC や対象デバイスの外部状態が残る場合は完了扱いにしません。
`doctor --json --assert-runtime-ready` は、HID probe 未実行や対象デバイス不一致など runtime 開始前提を満たさない診断を非ゼロ終了として記録します。期待失敗では `runtimeReadiness.failures[].code` に `inputMonitoring.notProbed` や `targetDevice.notFound` が含まれ、`targetDeviceDiagnostics.bestEvaluation` で matcher 不一致理由を確認できることも確認します。権限付与後の最終採否は、実利用主体で `--probe-hid --assert-runtime-ready` を併用した終了コードと `runtimeReadiness.ready` で行います。
`RuntimeStatusPresenter` の core test は、常駐 UI が実行中、停止中、自動再試行中、スリープ待機中を表示し、開始 / 緊急停止 / 停止の有効状態を復旧状態に合わせることを記録します。
`PermissionRecoveryPresenter` の core test は、アクセシビリティと入力監視の状態、System Settings URL、権限対象、権限変更後の再起動案内を分けて表示し、未許可または未判定の場合だけ該当設定を開く導線を必須表示することを記録します。
その他のコマンド、または `devices --all --json` が失敗した場合、スクリプト全体は非ゼロ終了し、`summary.md` に確認すべきログを残します。

このスクリプト単体で埋められるのは機械証跡だけです。
Nape Pro 実機、純正トラックパッド、Spaces / Mission Control の画面挙動、Developer ID 署名、公証、stapler、Gatekeeper 評価は別証跡がそろうまで完成扱いにしません。
TCC 許可済み runtime event、`run`、target 実測、常駐 CPU、入力遅延は、`scripts/collect-runtime-event-evidence.sh` と runtime performance 証跡で別途採否します。

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
- Nape Pro を接続し、`hid-log` 実行中にボタン、移動、ホイールなどを操作する。
- 純正トラックパッドで Spaces、Mission Control、ページ戻る/進む、ズーム、横スクロール相当のログを取る。
- Nape Pro 操作で同じシナリオを実行し、target log、CGEvent log、画面挙動を保存する。
- 通常クリック、通常ドラッグ、通常ホイールがジェスチャー処理後も壊れていないことを前面アプリで確認する。
- キルスイッチを実行中に押し、生成と慣性が止まり、通常入力が過剰抑制されないことを確認する。
- Mac をスリープ復帰させ、Nape Pro の抜き差しを行い、TCC 権限を一時的に変更して復旧導線を確認する。
- Developer ID 署名、公証、stapler、Gatekeeper 評価に必要な認証操作を行う。

人間作業で観察した内容は、必ず同じ scenario ディレクトリのログと対応付けます。
目視だけの「動いた」は完成証跡にせず、画面挙動メモは JSON / JSON Lines / コマンドログを補う材料として扱います。
