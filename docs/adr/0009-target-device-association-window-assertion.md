# ADR-0009: 対象デバイス紐づけ秒の機械判定

- 状態: 採択
- 日付: 2026-07-09

## 背景

Issue #5 の対象デバイス紐づけでは、Nape Pro の HID 入力と event tap 入力の時刻差を実測し、`targetDeviceAssociation.associationWindow` の妥当性を説明する必要がある。
表示だけの解析では、人間が `outsideWindowCount` や `missingHIDCandidateEventCount` を見落とす余地が残る。

## 決定

- `analyze-association` は `--assert-valid-window` を持つ。
- `--assert-valid-window` は、`--target-stable-id <ID>` が指定され、解析対象 event tap 入力が 1 件以上あり、互換 HID 候補なしが 0 件、非互換 HID 近傍が 0 件、対象外互換 HID 近傍が 0 件、採用 HID デバイスが対象 stableID の 1 件、associationWindow 外が 0 件の場合だけ成功する。
- event tap 入力の種別に応じて、移動/ドラッグは HID Generic Desktop X/Y、スクロールは runtime が記録する Generic Desktop Wheel、ボタンは `buttonNumber + 1` の HID Button usage とだけ関連付ける。
- 空ログ、互換 HID 候補なし、runtime が記録しない AC Pan、非互換 HID 近傍、対象外互換 HID 近傍、複数 HID デバイス採用、associationWindow 外の入力を、完了証跡として扱わない。
- 実機ログ取得後の採否は、`analyze-association --json --assert-valid-window --target-stable-id <ID>` の終了コードと `matches` の時刻差で行う。
- completion evidence では、成功 fixture と期待失敗 fixture の両方を残し、判定が甘くならないことを確認する。
- runtime の `TargetDeviceGate` は、対象デバイスの activation button が押下中でも、move / wheel を無条件には処理しない。直近の対象 HID pointer / wheel が `associationWindow` 内にある場合だけ処理する。
- activation button の `buttonUp` は、対象 HID の buttonDown から生じた解放待ちを 1 回だけ消費して stuck 防止のため通す。これにより、対象デバイス release の event tap と HID release の到着順が前後しても通常状態へ戻れる。
- `cancel` は状態復旧のため常に処理し、activation button 以外の buttonDown / buttonUp は押下中でもジェスチャー処理へ渡さない。

## 影響

- `need:human` は Nape Pro 実機操作や TCC などの外部作業に限定し、ログ取得後の採否は機械判定へ寄せられる。
- associationWindow の調整は、表示値の目視ではなく、非ゼロ終了した `matches` を根拠に行う。
- 空ログ、時刻だけ近い usage 不一致ログ、対象外デバイス単体ログ、複数デバイス混在ログを「実測済み」として扱う事故を防ぐ。
- 対象デバイスの activation button を押したまま、別マウスの移動やホイールが入っても、直近の対象 HID 活動がなければジェスチャー処理へ渡さない。
- activation button 以外の button を押下中のジェスチャー状態に巻き込まず、通常クリックや補助ボタンの過剰抑制を避ける。

## 関連

- [GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [Issue による orchestration と証跡付き close 方針](0005-issue-orchestration-and-evidence-close.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
