# ADR-0034: GitHub Actions の外部停止は merge gate を代替しない

- 状態: 採択
- 日付: 2026-07-10

## 背景

PR #90 で GitHub Actions の `Build and test` がジョブ開始前に失敗した。
annotation は `recent account payments have failed or your spending limit needs to be increased` であり、コード、workflow、runner 上のテスト失敗ではなく GitHub アカウントの billing / spending limit による外部停止だった。

この状態でローカルの `swift build`、core tests、provenance guard が成功していても、CI が実行されていない事実は残る。
ローカル検証を CI の代替として merge すると、PR ごとの必須 gate と監査可能な GitHub Actions 証跡が崩れる。

## 決定

- GitHub Actions が billing、spending limit、GitHub アカウント状態、runner quota などの外部状態でジョブ開始前に失敗した場合、PR には `blocked:external` と `need:human` を付ける。
- `need:human` は、この場合もレビュー待ちや承認待ちではなく、GitHub billing / spending limit を人間がアカウント設定で復旧する作業を表す。
- `gh api` または GitHub app で PR コメントに check annotation、run URL、ローカル検証結果、未 merge 理由を残す。
- ローカル検証は外部停止中の安全確認として残すが、GitHub Actions の成功 status の代替にはしない。
- CI が外部停止から復旧したら、同じ head SHA または最新 head SHA で checks を再実行し、成功を確認してから merge 判断を行う。
- docs/config のみの PR でも、CI が repository policy 上の必須 gate である場合は外部停止を無視して merge しない。例外を作る場合は、別 ADR で対象、理由、代替 gate、期限を先に決める。

## 影響

- GitHub Actions の外部停止とコード起因の CI 失敗を分けて扱える。
- billing / quota の復旧作業が `need:human` として可視化され、レビュー待ちと混ざらない。
- ローカル検証が CI の代替ではなく、復旧後に再確認するための補助証跡として扱われる。
- PR が mergeable でも、必須 CI が外部停止している間は完了扱いにしない。

## 関連

- [ADR-0002: GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [ADR-0004: メインスレッドとサブエージェントの役割分担、PR レビュー、merge 判断](0004-main-thread-subagent-pr-and-merge-roles.md)
- [PR レビューチェックリスト](../pr-review-checklist.md)
