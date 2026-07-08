# ADR-0016: 通常入力通過の種類別機械判定

- 状態: 採択
- 日付: 2026-07-09

## 背景

Issue #6 の完成条件は、ジェスチャーボタン解放後に通常クリック、通常ドラッグ、通常ホイールが過剰抑制されないことである。
従来の `--assert-has-unmarked-input` や `--assert-has-unmarked-passthrough-input` は未マーク入力の合算または移動 / スクロールの粗い判定であり、クリック欠落、ドラッグ欠落、ホイール欠落を個別に落とせない。

人間作業は最後の手段であり、トラックパッドや実機操作へ進む前に、CGEvent dry-run、Reference Target App、fixture、終了コードで代替できる判定を先に埋める必要がある。

## 決定

- `analyze-log` と `analyze-target-log` に `--assert-has-unmarked-click`、`--assert-has-unmarked-drag`、`--assert-has-unmarked-wheel` を追加する。
- 3種類をまとめて確認する互換ショートカットとして `--assert-has-unmarked-click-drag-wheel` も提供する。
- 通常クリックは通常左 / 右クリックの down と up の両方がある場合だけ成立とする。activation button の `otherMouseDown` / `otherMouseUp` は通常クリックに数えない。
- 通常ドラッグは通常左 / 右ドラッグを数える。activation button の `otherMouseDragged` は通常ドラッグに数えない。
- 通常ホイールは未生成または未マークの `scrollWheel` を数える。
- `normal-after-release` は activation button 解放後に通常移動、通常左クリック、通常左ドラッグ、通常ホイールを順に投稿する。
- `Fixtures/normal-input-target-log.jsonl` は3種類が揃う成功 fixture とし、クリック欠落、ドラッグ欠落、ホイール欠落 fixture を expected failure として CI と completion evidence に含める。
- `collect-runtime-event-evidence.sh` の `normal-after-release` は target log を `--assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel` で判定する。

## 影響

- 通常入力通過の証跡が「何か未マーク入力がある」から「クリック / ドラッグ / ホイールがそれぞれ届く」へ強化される。
- 人間が通常クリック、通常ドラッグ、通常ホイールを物理操作する前に、機械証跡で欠落種類を切り分けられる。
- `need:human` はレビュー待ちや判断待ちではなく、機械証跡で代替できない物理操作または macOS UI 操作だけに限定し続ける。

## 関連

- [Runtime event 証跡の自動化境界](0006-runtime-event-evidence-automation.md)
- [通常入力通過 dry-run の機械判定](0013-normal-input-passthrough-dry-run-assertion.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証手順](../verification.md)
