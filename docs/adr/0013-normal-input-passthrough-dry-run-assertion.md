# ADR-0013: 通常入力通過 dry-run の機械判定

- 状態: 採択
- 日付: 2026-07-09

## 背景

完成判定では、ジェスチャーボタン未押下時と解放後に、通常の移動やホイールが過剰抑制されないことを証明する必要がある。
最終確認には前面アプリでの実イベント投稿と目視確認が残るが、物理操作へ進む前に、`system-test normal-after-release` が通常入力通過を検証できるイベント列を生成しているかを機械判定できる必要がある。

単に未マーク入力があるだけでは不十分である。
`kill-switch` も未マークキーイベントを生成するため、未マークキーだけを通常入力通過の前段証跡として扱うと、キルスイッチ証跡を通常入力通過証跡に誤用できてしまう。

## 決定

- `analyze-log` に `--assert-has-unmarked-passthrough-input` を追加する。
- この assertion は、未生成の移動またはスクロールが 1 件以上ある場合だけ成功する。
- 未生成キーだけでは通常入力通過証跡として扱わない。
- `scripts/collect-completion-evidence.sh` は `system-test run --scenario normal-after-release --dry-run --log-json` を保存し、`analyze-log --json --assert-has-unmarked-passthrough-input` で終了コードを固定する。

## 影響

- 実イベント投稿や TCC 許可前でも、通常入力通過シナリオの dry-run が移動またはホイールを含むことを CI で確認できる。
- `kill-switch` の未マークキーイベントを、通常入力通過の証跡として誤って採用しにくくなる。
- 最終的な通常クリック、ドラッグ、ホイールの証跡は、引き続き Reference Target App と `analyze-target-log --assert-has-unmarked-input`、および実デバイス確認で埋める。

## 関連

- [Runtime event 証跡の自動化境界](0006-runtime-event-evidence-automation.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証手順](../verification.md)
