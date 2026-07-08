# ADR-0015: ジェスチャー中キルスイッチの前段証跡

- 状態: 採択
- 日付: 2026-07-09

## 背景

キルスイッチ単体の dry-run は、`Control + Option + Command + G` が生成できることを示せる。
しかし、Issue #12 の目的は暴走時の停止であり、進行中のジェスチャー入力がある状態でキルスイッチが投入される経路も、実イベント前に再現できる必要がある。

## 決定

- `system-test` に `gesture-wheel-then-kill-switch` を追加する。
- このシナリオは activation button 押下、未生成ホイール入力、未生成 `Control + Option + Command + G`、activation button 解放を同じ JSON Lines 形式で生成する。
- `analyze-log` に `--assert-gesture-before-kill-switch` を追加し、キルスイッチ前に未生成の activation button 押下と移動またはスクロール入力がある場合だけ成功する。
- CI と completion evidence は、`gesture-wheel-then-kill-switch` dry-run を `--assert-kill-switch-shortcut --assert-gesture-before-kill-switch` で確認する。
- runtime event evidence は、アクセシビリティ許可済み環境で同じシナリオを実投稿し、daemon 停止ログ、`analyze-target-log --assert-no-leaks --assert-has-generated-event` で判定する。

## 影響

- キルスイッチ dry-run が単体ショートカット確認に留まらず、ジェスチャー中停止の前段証跡として使える。
- 進行中ジェスチャーを伴わない `kill-switch` シナリオを、暴走中停止の証跡として誤用しにくくなる。
- 最終的な物理キー操作や Nape Pro 実機確認は残るが、そこへ進む前に CGEvent 投稿で再現できる範囲を増やせる。

## 関連

- [Runtime event 証跡の自動化境界](0006-runtime-event-evidence-automation.md)
- [キルスイッチ dry-run のショートカット機械判定](0014-kill-switch-dry-run-shortcut-assertion.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証手順](../verification.md)
