# ADR 一覧

このディレクトリは、開発運用で繰り返し参照する意思決定を ADR として保存する場所である。
会話や PR 本文だけに残る判断は次回以降に再現しにくいため、継続運用に影響する方針はここへ追加する。

## 採択済み

| 番号 | タイトル | 主な対象 |
| --- | --- | --- |
| [ADR-0001](0001-adr-rules.md) | ADR の置き場、書式、番号ルール | ADR 作成、更新、廃止 |
| [ADR-0002](0002-github-labels-milestones-and-issue-close.md) | GitHub labels / milestones / Issue close 方針 | Issue 管理、label、milestone、close |
| [ADR-0003](0003-dependabot-daily-review-policy.md) | Dependabot の対象、頻度、PR レビュー方針 | `.github/dependabot.yml`、依存更新 |
| [ADR-0004](0004-main-thread-subagent-pr-and-merge-roles.md) | メインスレッドとサブエージェントの役割分担、PR レビュー、merge 判断 | 並列開発、PR レビュー、merge |
| [ADR-0005](0005-issue-orchestration-and-evidence-close.md) | Issue による orchestration と証跡付き close 方針 | Issue 分割、証跡、完了判定 |
| [ADR-0006](0006-runtime-event-evidence-automation.md) | Runtime event 証跡の自動収集と人間作業境界 | Issue #6/#12、TCC、target log、自動証跡 |
| [ADR-0007](0007-log-derived-tuning-parameters.md) | ログ由来チューニング候補の再導出 | Issue #8、純正トラックパッドログ、加速度、慣性 |
| [ADR-0008](0008-runtime-recovery-boundary-evidence.md) | Runtime recovery 境界条件の機械証跡化 | Issue #13、スリープ復帰、入力監視、復旧 |
| [ADR-0009](0009-target-device-association-window-assertion.md) | 対象デバイス紐づけ秒の機械判定 | Issue #5、HID / event tap 時刻差、associationWindow |
| [ADR-0011](0011-doctor-runtime-ready-assertion.md) | doctor runtime ready の機械判定 | Issue #13、Issue #16、権限、HID probe、対象デバイス一致 |
| [ADR-0012](0012-settings-ui-gesture-action-coverage.md) | 設定 UI の GestureAction 網羅性 | 設定 UI、GestureAction、アプリ別設定不要 |
| [ADR-0013](0013-normal-input-passthrough-dry-run-assertion.md) | 通常入力通過 dry-run の機械判定 | Issue #6、Issue #16、normal-after-release、analyze-log |
| [ADR-0014](0014-kill-switch-dry-run-shortcut-assertion.md) | キルスイッチ dry-run のショートカット機械判定 | Issue #12、Issue #16、kill-switch、analyze-log |
| [ADR-0015](0015-gesture-wheel-then-kill-switch-evidence.md) | ジェスチャー中キルスイッチの前段証跡 | Issue #12、Issue #16、gesture-wheel-then-kill-switch |
| [ADR-0016](0016-normal-input-kind-assertions.md) | 通常入力通過の種類別機械判定 | Issue #6、Issue #16、normal-after-release、analyze-log、analyze-target-log |
| [ADR-0018](0018-target-device-not-found-diagnostics.md) | targetDevice.notFound の matcher 詳細診断 | Issue #4、Issue #13、Issue #16、doctor、targetDeviceDiagnostics |
| [ADR-0019](0019-runtime-event-status-json.md) | Runtime event 証跡の status JSON | Issue #6、Issue #12、Issue #16、runtime event、status.json |
| [ADR-0020](0020-doctor-tcc-permission-target.md) | doctor TCC 権限付与対象の構造化 | Issue #13、Issue #16、doctor、TCC、permissionTarget |
| [ADR-0021](0021-settings-ui-field-catalog.md) | 設定 UI 編集項目 catalog の機械証跡化 | Issue #11、Issue #16、設定 UI、SettingsUIField |
| [ADR-0022](0022-benchmark-batch-percentile-metrics.md) | 純粋ロジック benchmark の batch p95 / p99 証跡 | Issue #14、Issue #16、benchmark、性能 |
| [ADR-0023](0023-repo-local-provenance-guard.md) | repo-local 由来ガード | Issue #1、Issue #15、Issue #16、ライセンス、由来 |
| [ADR-0024](0024-regular-gui-app-launch.md) | 通常 GUI アプリとして起動する | Issue #11、Issue #15、Issue #16、GUI、`.app` |
| [ADR-0025](0025-gui-permission-recovery-actions.md) | GUI 権限復旧導線の表示契約 | Issue #74、Issue #11、Issue #13、Issue #16、GUI、TCC |
| [ADR-0026](0026-runtime-performance-log-evidence.md) | runtime 性能ログによる tap-to-post 証跡 | Issue #14、Issue #16、runtime、性能、tap-to-post |
| [ADR-0028](0028-readme-product-dashboard.md) | README を製品入口兼状態ダッシュボードとして扱う | README、GUI、完成状態、Mermaid、キャプチャ |
| [ADR-0030](0030-computer-use-gui-operation-evidence.md) | Computer Use で GUI 操作と画面証跡を前進させる | computer-use、GUI、System Settings、画面証跡、need:human |
| [ADR-0031](0031-reference-target-cursor-focus.md) | Reference Target App の無人証跡では capture view へカーソルを固定する | runtime event、Reference Target App、system-test、target log |
| [ADR-0032](0032-reference-target-foreground-capture.md) | Reference Target App は foreground capture 経路を証跡化する | runtime event、Reference Target App、foreground capture、postToPid |
| [ADR-0033](0033-kill-switch-pending-release-suppression.md) | キルスイッチ後も進行中ジェスチャーの release は抑制する | Issue #12、kill-switch、activation button、元入力抑制 |
| [ADR-0035](0035-discontinue-grok-independent-audit.md) | Grokによる独立監査を廃止する | 独立監査、レビュー責任、サブエージェント |
| [ADR-0036](0036-emulate-trackpad-driver-output-events.md) | trackpad driver上位出力eventを再現する | gesture event、scroll、DockSwipe、NavigationSwipe、magnification |
| [ADR-0037](0037-separate-product-and-diagnostic-event-output.md) | 製品gesture出力と診断event出力を分離する | module境界、fail closed、monotonic clock、CI guard |

## 置換済み

| 番号 | タイトル | 置換先 |
| --- | --- | --- |
| [ADR-0027](0027-grok-cli-auxiliary-review.md) | Grok CLIを補助レビューと発散に使う | [ADR-0035](0035-discontinue-grok-independent-audit.md) |
| [ADR-0029](0029-grok-operational-surface.md) | Grok運用知見をAGENTS.mdとCodex skillに同期する | [ADR-0035](0035-discontinue-grok-independent-audit.md) |
| [ADR-0010](0010-system-test-discrete-assignment-dry-run-evidence.md) | 離散割り当てのSystem Behavior Test dry-run証跡 | [ADR-0036](0036-emulate-trackpad-driver-output-events.md) |
| [ADR-0017](0017-system-test-scenario-assertion.md) | System Behavior Test dry-runのシナリオ別機械判定 | [ADR-0036](0036-emulate-trackpad-driver-output-events.md) |

## 却下

| 番号 | タイトル | 理由 |
| --- | --- | --- |
| [ADR-0034](0034-reject-driverkit-virtual-trackpad.md) | DriverKit virtual trackpad案を却下する | 目標とするtrackpad driver上位出力と異なる層を実装するため |

## 追加時の確認

新しい ADR を追加する前に、[ADR-0001](0001-adr-rules.md) の番号ルールと書式を確認する。
既存 ADR と矛盾する場合は、既存 ADR を直接書き換えて意味を変えるのではなく、新しい ADR で置き換え理由を明記し、旧 ADR の状態を「置換済み」にする。
