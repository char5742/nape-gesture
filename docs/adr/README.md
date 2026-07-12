# ADR 一覧

このディレクトリは、開発運用で繰り返し参照する意思決定を ADR として保存する場所である。
会話や PR 本文だけに残る判断は次回以降に再現しにくいため、継続運用に影響する方針はここへ追加する。

Nape Gestureの製品モデルは[ADR-0049](0049-fixed-button-to-finger-count-trackpad-input.md)だけを正本とする。ほかの採択済みADRは、このモデルを変更せず、安全、session、compatibility、証跡などの実装境界を定める。

## 採択済み

| 番号 | タイトル | 主な対象 |
| --- | --- | --- |
| [ADR-0001](0001-adr-rules.md) | ADR の置き場、書式、番号ルール | ADR 作成、更新、廃止 |
| [ADR-0002](0002-github-labels-milestones-and-issue-close.md) | GitHub labels / milestones / Issue close 方針 | Issue 管理、label、milestone、close |
| [ADR-0003](0003-dependabot-daily-review-policy.md) | Dependabot の対象、頻度、PR レビュー方針 | `.github/dependabot.yml`、依存更新 |
| [ADR-0004](0004-main-thread-subagent-pr-and-merge-roles.md) | メインスレッドとサブエージェントの役割分担、PR レビュー、merge 判断 | 並列開発、PR レビュー、merge |
| [ADR-0005](0005-issue-orchestration-and-evidence-close.md) | Issue による orchestration と証跡付き close 方針 | Issue 分割、証跡、完了判定 |
| [ADR-0006](0006-runtime-event-evidence-automation.md) | Runtime event 証跡の自動収集と人間作業境界 | Issue #6/#12、TCC、target log、自動証跡 |
| [ADR-0008](0008-runtime-recovery-boundary-evidence.md) | Runtime recovery 境界条件の機械証跡化 | Issue #13、スリープ復帰、入力監視、復旧 |
| [ADR-0009](0009-target-device-association-window-assertion.md) | 対象デバイス紐づけ秒の機械判定 | Issue #5、HID / event tap 時刻差、associationWindow |
| [ADR-0011](0011-doctor-runtime-ready-assertion.md) | doctor runtime ready の機械判定 | Issue #13、Issue #16、権限、HID probe、対象デバイス一致 |
| [ADR-0013](0013-normal-input-passthrough-dry-run-assertion.md) | 通常入力通過 dry-run の機械判定 | Issue #6、Issue #16、normal-after-release、analyze-log |
| [ADR-0014](0014-kill-switch-dry-run-shortcut-assertion.md) | キルスイッチ dry-run のショートカット機械判定 | Issue #12、Issue #16、kill-switch、analyze-log |
| [ADR-0015](0015-gesture-wheel-then-kill-switch-evidence.md) | ジェスチャー中キルスイッチの前段証跡 | Issue #12、Issue #16、gesture-wheel-then-kill-switch |
| [ADR-0016](0016-normal-input-kind-assertions.md) | 通常入力通過の種類別機械判定 | Issue #6、Issue #16、normal-after-release、analyze-log、analyze-target-log |
| [ADR-0018](0018-target-device-not-found-diagnostics.md) | targetDevice.notFound の matcher 詳細診断 | Issue #4、Issue #13、Issue #16、doctor、targetDeviceDiagnostics |
| [ADR-0019](0019-runtime-event-status-json.md) | Runtime event 証跡の status JSON | Issue #6、Issue #12、Issue #16、runtime event、status.json |
| [ADR-0020](0020-doctor-tcc-permission-target.md) | doctor TCC 権限付与対象の構造化 | Issue #13、Issue #16、doctor、TCC、permissionTarget |
| [ADR-0021](0021-settings-ui-field-catalog.md) | 設定UIの製品仕様と編集項目を機械証跡化する | 固定mapping、編集可能項目、runtime status、SettingsUIField |
| [ADR-0022](0022-benchmark-batch-percentile-metrics.md) | 純粋ロジック benchmark の batch p95 / p99 証跡 | Issue #14、Issue #16、benchmark、性能 |
| [ADR-0023](0023-repo-local-provenance-guard.md) | repo-local 由来ガード | Issue #1、Issue #15、Issue #16、ライセンス、由来 |
| [ADR-0024](0024-regular-gui-app-launch.md) | 通常 GUI アプリとして起動する | Issue #11、Issue #15、Issue #16、GUI、`.app` |
| [ADR-0025](0025-gui-permission-recovery-actions.md) | GUI 権限復旧導線の表示契約 | Issue #74、Issue #11、Issue #13、Issue #16、GUI、TCC |
| [ADR-0026](0026-runtime-performance-log-evidence.md) | finger-count入力変換のruntime性能を構造化記録する | source button、finger count、入出力量、tap-to-post |
| [ADR-0028](0028-readme-product-dashboard.md) | README を製品入口兼状態ダッシュボードとして扱う | README、GUI、完成状態、Mermaid、キャプチャ |
| [ADR-0030](0030-computer-use-gui-operation-evidence.md) | Computer Use で GUI 操作と画面証跡を前進させる | computer-use、GUI、System Settings、画面証跡、need:human |
| [ADR-0031](0031-reference-target-cursor-focus.md) | Reference Target App の無人証跡では capture view へカーソルを固定する | runtime event、Reference Target App、system-test、target log |
| [ADR-0032](0032-reference-target-foreground-capture.md) | Reference Target App は foreground capture 経路を証跡化する | runtime event、Reference Target App、foreground capture、postToPid |
| [ADR-0033](0033-kill-switch-pending-release-suppression.md) | キルスイッチ後もactive source buttonのreleaseを抑制する | Issue #12、kill-switch、finger count、元入力抑制 |
| [ADR-0034](0034-reject-driverkit-virtual-trackpad.md) | DriverKit virtual trackpadを製品出力に使わない | IOHID、event tap、driver上位event、fail closed |
| [ADR-0035](0035-discontinue-grok-independent-audit.md) | Grokによる独立監査を廃止する | 独立監査、レビュー責任、サブエージェント |
| [ADR-0036](0036-emulate-trackpad-driver-output-events.md) | trackpad driver上位入力を安全に再現する | ADR-0049、安全境界、system-wide、compatibility adapter、fail closed |
| [ADR-0037](0037-separate-product-and-diagnostic-event-output.md) | 製品gesture出力と診断event出力を分離する | module境界、fail closed、monotonic clock、CI guard |
| [ADR-0038](0038-trackpad-output-session-and-monotonic-clock.md) | finger count付きtrackpad入力sessionとmonotonic clockを共通化する | finger count固定、session、capture order、terminal、起動後時刻 |
| [ADR-0039](0039-strict-trackpad-event-analysis-and-capture-manifest.md) | trackpad eventログを厳格解析しcapture manifestへ固定する | JSON Lines、manifest、provenance、host再構築 |
| [ADR-0040](0040-capture-order-and-event-timestamp.md) | capture順とevent timestampを分離する | 純正trackpad実測、captureIndex、manifest開始・終了時刻 |
| [ADR-0041](0041-physical-capture-readiness-and-fixture-privacy.md) | 物理captureのready同期と公開fixture境界を固定する | 排他的ready lease、安定化waiter、生成marker、fixture privacy、need:human |
| [ADR-0042](0042-versioned-scroll-momentum-contract-comparison.md) | 25F80 scroll / momentum契約を独立fixtureで比較する | version fixture、lifecycle、terminal、scroll companion、CLI差分report |
| [ADR-0043](0043-trackpad-scroll-product-output.md) | 25F80のfinger count付きtrackpad入力compatibility contractを構成する | 25F80、単位変換、finger count、identity、provenance、fail closed |
| [ADR-0044](0044-atomic-app-bundle-installation.md) | 検証済みapp bundleを原子的に導入する | bundle-app、renameatx_np、fingerprint、既存bundle保持、strict CLI |
| [ADR-0049](0049-fixed-button-to-finger-count-trackpad-input.md) | buttonを指本数へ固定しイベント量をtrackpad入力へ置換する | 固定button、finger count、連続mouse event量、通常mouse通過、OS / App解釈、内部event contract |

## 追加時の確認

新しい ADR を追加する前に、[ADR-0001](0001-adr-rules.md) の番号ルールと書式を確認する。
製品モデルを扱うADRはADR-0049を唯一の正本として参照し、結果別mode、family別製品経路、application別routingを再導入しない。誤った記述はGit履歴だけに残し、現行treeでは全面改稿または削除して矛盾する製品モデルを残さない。
