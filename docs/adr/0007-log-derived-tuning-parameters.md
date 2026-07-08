# ADR-0007: ログ由来チューニング候補の再導出

- 状態: 採択
- 日付: 2026-07-09

## 背景

Issue #8 では、純正トラックパッドログから加速度、しきい値、慣性パラメータを再導出する必要がある。
一方で、実機ログが少ない段階で設定値を固定すると、合成 fixture や短いログに過剰適合する。

## 決定

- ログ由来の候補値は `nape-gesture derive-parameters <path> [--json]` で出す。
- `derive-parameters` は `analyze-log` の互換出力を壊さず、候補値と未導出理由を別の構造化レポートとして保存する。
- 出力する候補は `deadZonePoints`、`acceleration.thresholdVelocity`、`momentum.minimumStartVelocity`、`momentum.stopVelocity`、`momentum.decayPerSecond`、`momentum.frameInterval` とする。
- 十分な移動速度サンプルや `momentumPhase` サンプルがない場合、推測値で埋めず `warnings` に未導出理由を残す。
- `timestamp` の差分が 0.1ms 未満のログは、CGEvent.timestamp 由来ではない合成ログの可能性があるため、速度推定を参考扱いにする警告を出す。
- `scripts/collect-completion-evidence.sh` は `Fixtures/sample-tuning-trackpad-log.jsonl` の再導出結果を保存し、純正トラックパッド実測ログ取得前でも解析パイプラインを回帰確認する。

## 影響

- Issue #8 は、実機ログ取得前でも再導出ロジックと証跡保存手順を先に検証できる。
- 実測ログ取得後は、同じ CLI で候補値と未導出理由を Issue コメントへ残せる。
- 候補値は自動的に実利用設定へ反映しない。採用時はログ、候補値、体感差分、比較結果を確認してから設定に反映する。
- 合成 fixture の成功は Issue #8 の完了条件ではない。純正トラックパッドと Nape Pro の実測ログは引き続き必要である。

## 関連

- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
- [Issue による orchestration と証跡付き close 方針](0005-issue-orchestration-and-evidence-close.md)
