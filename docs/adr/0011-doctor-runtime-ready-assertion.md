# ADR-0011: doctor runtime ready の機械判定

- 状態: 採択
- 日付: 2026-07-09

## 背景

`doctor --json` は、アクセシビリティ、HID inventory、対象デバイス一致、HID 入力監視プローブ、設定検証、runtimeIdentity を同じ JSON に保存できる。
しかし、所見を人間が読むだけでは、権限不足や対象デバイス不一致を completion evidence で見落とす余地が残る。

Issue #13 の復旧確認や Issue #16 の完成判定では、実機操作へ進む前に「この実行主体で runtime を開始してよいか」を終了コードで判断できる必要がある。

## 決定

- `doctor` に `--assert-runtime-ready` を追加する。
- `doctor --json` は `runtimeReadiness` と `tccStatus` を出力する。
- `doctor --json` は `targetDeviceDiagnostics` も出力し、対象デバイス不一致時の matcher 評価と近い候補を保存する。
- `runtimeReadiness.ready` は runtime 開始前提を満たす場合だけ `true` にする。
- `runtimeReadiness.failures` は `code`、`category`、`message`、`remediation` を持つ構造化配列にする。
- TCC / 権限系は `tccStatus.accessibility` と `tccStatus.inputMonitoring` に分け、入力監視は HID 入力監視プローブで確認する。
- `--assert-runtime-ready` は JSON または通常出力を出した後、runtime 開始前提を検査して不足があれば非ゼロ終了する。
- runtime ready の失敗条件は、設定不正、アクセシビリティ未許可、HID inventory 失敗、HID probe 未実行、HID probe 失敗、対象デバイス一致必須時の matcher 未設定または一致デバイスなしとする。
- `--assert-runtime-ready` は性能基準を判定しない。性能は `benchmark --assert-baseline` と `doctor` 内の benchmark 証跡で別に扱う。
- completion evidence は、`runtimeReadiness` / `tccStatus` の存在確認、`--probe-hid` なしの期待失敗、絶対に一致しない対象デバイス設定の期待失敗を保存する。
- 権限付与後の最終採否は、実利用する `.app` または実行ファイルで `doctor --probe-hid --json --assert-runtime-ready` を実行し、その終了コードと JSON を保存して行う。

## 影響

- TCC、入力監視、対象デバイス不一致、HID probe 未実行を、人間目視や日本語所見の grep ではなく、終了コードと構造化 JSON で検出できる。
- 対象デバイス不一致は `targetDeviceDiagnostics.bestEvaluation.mismatches` で、どの条件が外れたかを実機作業前に確認できる。
- `need:human` はシステム設定での許可操作、Nape Pro 接続、スリープ復帰などの物理作業または macOS UI 操作に限定し、診断結果の採否は CLI assertion に寄せられる。
- 実機や権限状態がない CI / ローカル環境でも、runtime ready でない状態を期待失敗として継続確認できる。

## 関連

- [GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [Runtime recovery 境界条件の機械証跡化](0008-runtime-recovery-boundary-evidence.md)
- [targetDevice.notFound の matcher 詳細診断](0018-target-device-not-found-diagnostics.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
