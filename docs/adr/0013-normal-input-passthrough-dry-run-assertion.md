# ADR-0013: 通常入力通過 dry-run の機械判定

- 状態: 採択
- 日付: 2026-07-09

## 背景

完成判定では、button 3 / 4 / 5未押下時と各buttonの解放後に、通常のclick、move、drag、wheelが変更、抑制、再生成されないことを証明する必要がある。
前面applicationでの実event投稿や物理操作が最後に残る場合でも、そこへ進む前に、`system-test normal-after-release`が2 / 3 / 4本指session終了後の通常入力通過を検証できるevent列を生成しているか機械判定する。

単に未マーク入力があるだけでは不十分である。
`kill-switch` も未マークキーイベントを生成するため、未マークキーだけを通常入力通過の前段証跡として扱うと、キルスイッチ証跡を通常入力通過証跡に誤用できてしまう。

## 決定

- `analyze-log` に `--assert-has-unmarked-passthrough-input` を追加する。
- この assertion は、未生成の移動またはスクロールが 1 件以上ある場合だけ成功する。
- 未生成キーだけでは通常入力通過証跡として扱わない。
- `scripts/collect-completion-evidence.sh`はbutton 3 / 4 / 5それぞれの`normal-after-release`を保存し、`analyze-log --json --assert-has-unmarked-passthrough-input`で終了コードを固定する。
- 2026-07-09 追補: 通常クリック / 通常ドラッグ / 通常ホイールの個別完了判定は [ADR-0016](0016-normal-input-kind-assertions.md) で扱う。`--assert-has-unmarked-passthrough-input` は互換的な粗い前段判定として残す。

## 影響

- 実event投稿やTCC許可前でも、各finger-count session後のdry-runが少なくとも通常入力系eventを含むことを粗く確認できる。完成判定ではADR-0016の種類別assertionを使う。
- `kill-switch` の未マークキーイベントを、通常入力通過の証跡として誤って採用しにくくなる。
- 最終的な通常クリック、ドラッグ、ホイールの証跡は、Reference Target App と `analyze-target-log --assert-has-unmarked-click --assert-has-unmarked-drag --assert-has-unmarked-wheel`、および必要な場合の実デバイス操作で埋める。

## 関連

- [Runtime event 証跡の自動化境界](0006-runtime-event-evidence-automation.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証手順](../verification.md)
