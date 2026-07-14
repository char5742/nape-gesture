# ADR-0015: ジェスチャー中キルスイッチの前段証跡

- 状態: 採択
- 日付: 2026-07-09
- 更新日: 2026-07-14

## 背景

キルスイッチ単体の dry-run は、`Control + Option + Command + G` が生成できることを示せる。
しかし、Issue #12の目的は暴走時の停止であり、button 3 / 4 / 5の割り当てから選択されたGestureClass sessionが進行中の状態でキルスイッチが投入される経路も、実event前に再現できる必要がある。

## 決定

- 診断互換scenario IDとして`gesture-wheel-then-kill-switch`を使うが、製品modeまたはwheel専用経路を意味させない。
- scenarioはsource button、期待GestureClass、未生成source moveまたはwheel、未生成`Control + Option + Command + G`、対応button解放を同じJSON Lines schemaで生成する。
- `analyze-log`の`--assert-gesture-before-kill-switch`は、キルスイッチ前にbutton 3 / 4 / 5のいずれかと期待GestureClass、source event量がある場合だけ成功する。
- CIとcompletion evidenceはbutton 3 / 4 / 5の全てについて、`--assert-kill-switch-shortcut --assert-gesture-before-kill-switch`を確認する。
- runtime event evidence は、アクセシビリティ許可済み環境で同じシナリオを実投稿し、daemon 停止ログ、`analyze-target-log --assert-no-leaks --assert-has-generated-event` で判定する。

## 影響

- キルスイッチdry-runが単体shortcut確認に留まらず、各固定GestureClass session中停止の前段証跡として使える。
- 進行中ジェスチャーを伴わない `kill-switch` シナリオを、暴走中停止の証跡として誤用しにくくなる。
- 最終的な物理key操作やNape Pro実機確認は残るが、そこへ進む前に生成eventで再現できる範囲を増やせる。

## 関連

- [Runtime event 証跡の自動化境界](0006-runtime-event-evidence-automation.md)
- [キルスイッチ dry-run のショートカット機械判定](0014-kill-switch-dry-run-shortcut-assertion.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証手順](../verification.md)
