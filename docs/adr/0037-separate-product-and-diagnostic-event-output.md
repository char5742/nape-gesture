# ADR-0037: 製品gesture出力と診断event出力を分離する

- 状態: 採択
- 日付: 2026-07-11
- 更新日: 2026-07-14

## 背景

移行前の`EventPoster`は、製品runtime、`generate-scroll`、System Behavior Testから共有され、単純pixel scroll、forced horizontal scroll、keyboard shortcutを同じ境界で投稿している。`postToPid`もReference Target Appのsink診断として存在する。

これらをコード上の注意書きだけで区別すると、診断用経路が製品fallbackやcompletion evidenceへ再流入する。さらに、adapter未対応または投稿失敗時に元入力だけを抑制すると、通常操作を失う危険がある。

## 決定

- 製品runtimeは`NapeGestureProductOutput` targetの`ProductGestureOutput`境界だけを参照し、旧`EventPoster`相当は`NapeGestureDiagnosticOutput` targetへ分離する。
- `ProductGestureOutput`の配送先はsystem-wide固定とし、PID、frontmost application、AX element、keyboard shortcutを引数またはfallbackとして持たない。
- 単純pixel scroll、forced horizontal scroll、旧gesture shortcutは診断output targetだけに置く。`postToPid`はSystem Behavior TestのReference Target sink診断だけに限定し、いずれもCLIと証跡に`legacy diagnostic`を明示する。
- kill switchのkeyboard event監視とSystem Behavior Test内の未マーク入力注入は安全性診断であり、gesture代替ではないため明示allowlistで残す。
- daemonはevent tap開始前にcontract fixture、adapter capability、event構築可否を検査する。`unsupported`または`contractMismatch`では入力抑制を開始せずfail closedにする。
- `supported`はproduct output target内のregistryへ登録したfixture ID、SHA-256、schema、contract ID、fixture実体、収録元OS情報を含むasset provenanceが完全一致する場合だけ生成できる。実行中OS buildは診断にだけ使い、capability判定には渡さない。registryは純正fixture取得前は空に保つ。
- active sequence中の作成・投稿失敗ではterminal / cancelを試み、元入力抑制を解除してruntimeを安全停止する。別方式へのfallbackは行わない。
- output sessionは単一のmonotonic clock、sequence ID、event order、terminal stateを持つ。Unix wall clockをdelta計算へ混ぜない。
- CIはproduct sourceから`keyboardEventSource`、`postToPid`、`AXUIElement`、`forcedHorizontal`への依存を禁止し、診断moduleとkill switchだけをallowlistにする。
- completion analyzerはgesture scenarioへのkey event混入、companion event欠落、必要なevent family欠落、PID配送を失敗にする。

## 影響

- 旧出力は入力認識、安全停止、公開field比較のbaselineとして残せるが、Issue #9 / #10 / #117の完成証跡には使えない。
- product adapterが未完成の間は、不正確なgestureを送るより明示的な未対応状態で停止する。
- product / diagnostic output target分離とsource guardを先行実装する。完全なruntime target分離、daemon統合、共通session modelはIssue #124、#128、#130、#131で追跡する。

## 関連

- [trackpad driver上位出力eventを再現する](0036-emulate-trackpad-driver-output-events.md)
- [PR review checklist](../pr-review-checklist.md)
- [検証方針](../verification.md)
- [完成判定チェックリスト](../completion-checklist.md)
