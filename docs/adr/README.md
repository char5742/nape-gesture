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

## 追加時の確認

新しい ADR を追加する前に、[ADR-0001](0001-adr-rules.md) の番号ルールと書式を確認する。
既存 ADR と矛盾する場合は、既存 ADR を直接書き換えて意味を変えるのではなく、新しい ADR で置き換え理由を明記し、旧 ADR の状態を「置換済み」にする。
