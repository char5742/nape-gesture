# ADR-0012: 設定 UI の GestureAction 網羅性

- 状態: 採択
- 日付: 2026-07-09

## 背景

完成判定では、設定 UI から主要ジェスチャーを調整できる必要がある。
一方で、`GestureAction` に新しい割り当てを追加したとき、設定 UI のポップアップだけ更新を忘れると、設定ファイルでは表現できても UI から選べない状態になる。

また、このアプリはジェスチャーボタン未押下時に通常マウスとして振る舞うため、アプリ別の有効・無効、感度、割り当ては不要である。

## 決定

- 設定 UI の割り当て候補は `GestureAction.settingsSelectableActions` から生成する。
- `GestureAction.settingsSelectableActions` は `GestureAction.allCases` と一致させる。
- core tests で、設定 UI の割り当て候補が `GestureAction` 全ケースを網羅し、重複がなく、Mission Control、Spaces、ページ戻る/進む、ズーム、横スクロールを含むことを固定する。
- 設定 UI にはアプリ別の有効・無効、感度、割り当てを追加しない。

## 影響

- 新しい `GestureAction` を追加した場合、設定 UI の候補から漏れるとテストで検出できる。
- 設定 UI はデバイス全体の操作体系を調整する場所として維持され、アプリ別制御へ逸れない。
- 実機や TCC 権限がなくても、主要ジェスチャー割り当てを UI 候補として維持する前段証跡を CI で確認できる。

## 関連

- [GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [PR レビューチェックリスト](../pr-review-checklist.md)
