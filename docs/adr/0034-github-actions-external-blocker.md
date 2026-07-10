# ADR-0034: GitHub Actions の外部停止は merge gate を代替しない

- 状態: 採択
- 日付: 2026-07-10
- 更新: 2026-07-11

## 背景

PR #90 で GitHub Actions の `Build and test` がジョブ開始前に失敗した。annotation は account payment または spending limit による停止を示し、コードやworkflowの失敗ではなかった。

ローカルのbuild/test成功をCIの代替にすると、PRごとの必須gateとGitHub上の監査可能な証跡が崩れる。またPrivate repositoryのActions課金を回避するため、ユーザー判断でrepositoryをPublicへ変更した。

## 決定

- billing、spending limit、account状態、runner quotaなどでジョブ開始前に失敗した場合、`blocked:external`と`need:human`で可視化する。
- ローカル検証は補助証跡であり、GitHub Actionsの成功statusを代替しない。外部状態の解消後、同じheadまたは最新headで再実行してからmerge判断する。
- `nape-gesture`はPublic repositoryとして運用し、public runnerでCIを実行する。visibility変更はユーザーの明示指示がある場合だけ行う。
- Public化後もCI gate、review、実機証跡、署名・公証の要件は緩和しない。
- secret、credential、署名鍵、notary認証情報、個人情報をtracked file、Issue、PR、artifact参照へ保存しない。公開変更時はcurrent treeとgit historyの既知token/private-key pattern、秘密情報らしいfilenameを検査する。
- 外部停止が解消したことは、過去の失敗表示ではなく再実行jobが開始し、最終的にsuccessになった証跡で判定する。

## 影響

- source、Issue、PR、履歴は一般公開される。
- Public化はActionsのジョブ開始前課金ブロックを解消できるが、コード起因の失敗は通常どおり修正が必要になる。
- Public化直後のPR #90 run `29067077174` attempt 2は全step成功した。Issue #91とPR #90の`blocked:external` / `need:human`を外し、両方へ証跡コメントを残してIssue #91をcloseした。

## 関連

- [ADR-0002: GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [ADR-0004: メインスレッドとサブエージェントの役割分担、PRレビュー、merge判断](0004-main-thread-subagent-pr-and-merge-roles.md)
- [PRレビューチェックリスト](../pr-review-checklist.md)
- Issue #91
- PR #90
