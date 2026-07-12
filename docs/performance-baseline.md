# 性能測定基準

この文書は、button 3 / 4 / 5押下中の連続mouse event量を2 / 3 / 4本指trackpad入力へ変換する製品経路の性能と安全性を判定する。
速さだけでなく、event量保存、finger count、session terminal、passthrough、実機証跡、fail closedを同じrunで満たすことを性能合格の前提とする。
製品モデルの設計判断は[ADR-0049](adr/0049-fixed-button-to-finger-count-trackpad-input.md)を正とする。

## 現在の状態

改訂基準commit`55eb991`の`BenchmarkReport.schemaVersion == 3`は、旧recognizerと`scrollPlanner`の純粋ロジック、および旧mode / family別runtime countを対象にしている。
2 / 3 / 4 finger countごとのsource-to-output量、terminal、未押下passthrough、fail-closed経路を計測していないため、現行benchmarkの成功だけでは**未達**である。

既存コマンドは回帰確認として継続利用できるが、新しい計測schemaと実機runがそろうまで製品性能の完成証跡にしない。

## 測定単位

性能recordは旧modeや低レベルevent familyではなく、次の単位で集計する。

- run UUID
- session ID
- activation button
- expected finger count
- source event sequence
- source kind、unit、phase、capture order
- source event countとdelta合計
- generated frame count
- terminal種別
- passthroughか変換対象か
- successまたはfail-closed理由

`scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`は診断用の観測列として記録してよいが、性能bucket、ユーザーmode、製品capabilityのkeyにしない。

## 必須の正確性指標

次は速度指標より先に判定し、1件でも不一致なら性能run全体を不合格にする。

| 指標 | 合格基準 |
| --- | --- |
| accepted source events | source logと変換器入力の件数が完全一致 |
| source event量 | 変換前の`deltaX` / `deltaY`、順序、timestamp、累積量がbit単位で一致 |
| model output量 | 登録済み純正fixtureから導出した単一versioned単位変換contractの許容差内 |
| cross-button invariance | 同一source fixtureでは正規化入力の量、順序、時間間隔が一致し、finger count固有の物理encoding差だけが登録contractと一致 |
| duplicate / dropped / reordered | すべて0件 |
| finger count mismatch | button 3 / 4 / 5の2 / 3 / 4対応に対して0件 |
| terminal missing / duplicate | すべて0件 |
| terminal後のgenerated event | 0件 |
| passthrough mutation / suppression / generation | button未押下時はすべて0件 |
| logger drop / unflushed record | 0件 |
| fail-closed後の誤出力 | 0件 |

複数source sampleを1 sampleへcoalesceしない。batch投稿する場合も、各source sampleのdelta、timestamp、sample orderと生成eventの対応を保存する。
正負が相殺されるため、最終delta合計だけの一致をevent量保存の証拠にしない。

## 保存する機械証跡

最低限、次を同じrepo SHAとbinaryで保存する。

~~~sh
swift build --scratch-path .build
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture-product-output-tests
.build/debug/nape-gesture benchmark --events 200000 --json --assert-baseline
.build/debug/nape-gesture doctor --benchmark-events 50000 --json
~~~

既存`benchmark`と`doctor`が出力する旧schemaは移行回帰に限る。完成証跡に採用するreportは、少なくとも次をfinger count 2 / 3 / 4ごとに返す。

- source event件数と変換器入力件数
- duplicate、drop、reorder count
- source event量照合結果
- generated frame / event count
- finger count mismatch count
- session count、terminal count、stuck count
- passthrough event count、mutation / suppression / generation count
- fail-closed scenario countと誤出力count
- 各区間のp50 / p95 / p99 / max
- wall time、CPU time、1 core換算CPU
- measurement kindと、event tap / postingを含むか

純粋ロジックとruntime実測を同じ`measurementKind`へ混ぜない。

## 純粋ロジック基準

純粋ロジックは、event tap、実投稿、AppKit受信、画面反映を含まない。`includesEventTapAndPosting`は`false`でなければならない。

| 区間 | 基準 |
| --- | --- |
| source event記録とbutton-to-finger-count判定 | 平均2,000 ns/event以下、CPU 2,000 ns/event以下 |
| event量変換とframe計画 | 平均2,000 ns/event以下、CPU 2,000 ns/event以下 |
| session state更新 | 平均2,000 ns/event以下、CPU 2,000 ns/event以下 |
| 各区間のsample p95 | 50,000 ns/event以下 |
| 各区間のsample p99 | 250,000 ns/event以下 |

test dataはbutton 3 / 4 / 5を同数含み、同一source fixtureのcross-button比較、正負X/Y、斜め、停止、方向反転、異なるtimestamp間隔、正常terminal、cancelを含める。
未押下passthroughは別bucketで同数以上測り、変換対象eventだけを測って合格にしない。

## runtime遅延基準

runtime性能JSON Linesは、event tap受理、source量記録、最初のtrackpad event投稿、同frame投稿完了、terminal投稿完了を同じsession / source sequenceへ結び付ける。

| 区間 | 基準 |
| --- | --- |
| tap callbackから最初のtrackpad event投稿まで | p95 8 ms以下、p99 16 ms以下 |
| tap callbackから同一source eventに対応するframe系列投稿完了まで | p95 8 ms以下、p99 16 ms以下 |
| terminal原因受理からterminal投稿完了まで | p95 8 ms以下、p99 16 ms以下 |
| 未押下passthroughの追加処理時間 | p95 1 ms以下、p99 2 ms以下 |

投稿なしrecord、予定数と実投稿数の不一致、event作成失敗、finger count不一致、terminal欠落をpercentileから除外して成功扱いにしない。
失敗recordを含む正確性gateを先に判定し、その後で成功recordの遅延分布を出す。

## CPU基準

日常利用する`.app`を実行し、次をfinger count別に30秒以上測る。

| 状態 | 基準 |
| --- | --- |
| アイドル | 平均1%以下 |
| 未押下passthrough連続入力 | 平均10%以下 |
| 2本指変換 | 平均15%以下 |
| 3本指変換 | 平均15%以下 |
| 4本指変換 | 平均15%以下 |
| terminal後5秒 | 1%以下へ戻る |
| fail closed待機 | 平均1%以下 |

loggerを同時実行する場合は、製品processとlogger processのCPUを別々に保存する。
logger callback内copy、queue待ち、field scan / encode、flushを分離し、queue depthとdrop countを記録する。

## 実機測定

純粋ロジックbenchmarkだけでは、次を完了扱いにしない。

- Nape Proのsource eventがevent tapへ届くまで
- 2 / 3 / 4 finger countを含むtrackpad event系列の実投稿
- session terminal
- 未押下passthrough
- TCC、device、contract不一致時のfail closed
- AppKit受信
- OS/App画面結果

実機runでは、純正trackpad 2 / 3 / 4本指fixtureと、Nape Pro button 3 / 4 / 5のruntime logを同じOS buildで取得する。
各finger countについて短い列、長い列、高頻度列、方向反転、正常terminal、cancelを含める。

常駐CPUは別terminalでPIDを固定して採取する。

~~~sh
pid=$(pgrep -x nape-gesture | head -n 1)
top -l 30 -s 1 -pid "$pid" -stats pid,cpu,time,command
~~~

測定中の操作が成立していたことをsource log、generated log、session reportで示す。画面の動きだけを負荷区間の証拠にしない。

## OS/App結果の時間

低レベル投稿時間とOS/App結果の時間は別reportにする。

| 区間 | 扱い |
| --- | --- |
| post完了からAppKit受信まで | target logで測り、p95 16 ms以下を初期基準とする |
| AppKit受信から画面反映まで | Appごとの観測値として保存する |
| system gestureの画面完了まで | OS buildと設定ごとの観測値として保存する |

OS/App結果の遅延が大きくても、結果別mode、方向別action、application別設定、AX/PID/shortcut fallbackを追加しない。
低レベルcontractの遅延合格と、OS/App結果の遅延合格を別々に報告する。

## fail closed性能

unsupported OS/build、fixture改変、finger count不明、device不一致、TCC不足、現在boot外timestamp、source / contractにないtimestamp変換、部分投稿失敗をfailure injectionと実利用binaryで測る。

合格条件:

- readiness判定前にevent tapと抑制を開始しない
- rejection決定後のgenerated eventが0件
- active sessionはterminalまたは構造化された安全停止へ収束する
- 物理解放後にpassthroughへ戻る
- retry loopがCPU基準を超えない
- AX、PID、shortcut、別familyへのfallbackが0件

fail-closed経路をbenchmark対象から除外しない。

## 採用条件

性能証跡は次を全て満たす場合だけ採用する。

- 日常利用する`.app`と`doctor.runtimeIdentity`が一致する
- repo SHA、binary SHA-256、OS build、fixture identityがmanifestと一致する
- finger count 2 / 3 / 4と未押下passthroughを同じ基準で測定している
- 正確性指標が全て合格する
- runtime遅延とCPUが基準内にある
- 純正trackpadとNape Proの実機証跡がある
- fail-closed scenarioに誤出力がない
- OS/App結果時間を低レベル投稿時間へ混ぜていない

閾値超過や正確性違反があれば根本原因を修正し、純粋ロジック、runtime、実機、fail closedの全runを取り直す。
