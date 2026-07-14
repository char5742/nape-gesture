# ADR-0033: キルスイッチ後も進行中ジェスチャーの release は抑制する

- 状態: 採択
- 日付: 2026-07-09
- 更新日: 2026-07-14

## 背景

`gesture-wheel-then-kill-switch`のruntime event証跡で、キルスイッチ発火後に進行中sessionのsource button `otherMouseUp`が前面AppKit targetへ漏れた。
キルスイッチでtrackpad入力生成と物理contract上の継続eventは停止していたが、停止後の通常入力通過方針をそのまま適用したため、button 3 / 4 / 5のうち押下中だったbuttonの後始末releaseまで通常入力として通していた。

通常入力は停止後に通すべきだが、キルスイッチ直前から継続しているジェスチャー入力の release は、前面アプリから見ると孤立したボタン解放になり誤動作の原因になる。

## 決定

- キルスイッチ発火時にrecognizerがidleでなければ、active sessionのsource buttonをpending releaseとして記録する。設定値やraw contact数からbuttonを推測しない。
- 停止後でも、そのsource buttonの最初の`buttonUp`だけを抑制し、buttonが一致したときにpendingを消す。
- pending release 以外の通常入力は停止後も通す。
- この挙動は `RuntimeSafetyState` の純粋状態としてテストし、daemon はその判断に従う。
- `system-test run --scenario kill-switch` は、他の未マーク入力シナリオと同じ `UnmarkedInputEvent` 経路を使い、`keyDown` / `keyUp` の間隔を `interval` で明示する。ゼロ間隔の合成ショートカット投稿は daemon 停止証跡として採用しない。

## 影響

- 暴走停止時に、生成trackpad event、物理contract上の継続event、キルスイッチkey、active source button releaseが前面applicationへ漏れない。
- キルスイッチ後の通常クリック、通常ドラッグ、通常ホイールは引き続き通せる。
- runtime event 証跡では `gesture-wheel-then-kill-switch` が `analyze-target-log --assert-no-leaks --assert-has-generated-event --assert-has-foreground-capture` を満たす。

## 関連

- [ADR-0015: ジェスチャー中キルスイッチの前段証跡](0015-gesture-wheel-then-kill-switch-evidence.md)
- [ADR-0032: Reference Target App は foreground capture 経路を証跡化する](0032-reference-target-foreground-capture.md)
- [検証手順](../verification.md)
- [完成判定チェックリスト](../completion-checklist.md)
