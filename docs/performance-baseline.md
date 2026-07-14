# 性能測定基準

この文書は、固定button入力から3つの上位GestureClassをsystem-wideへ投稿する製品経路の性能と正確性を判定する。製品モデルは[ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md)を正とする。

速度だけを測って合格にしない。source sample 1対1 command化、exact timestamp、capture order、class固有ProductOutput、single terminal、passthrough、fail closedが同じrunで成立することを前提とする。

## 測定単位

性能recordは次の単位で集計する。

- run UUID
- repo SHA、binary SHA-256、OS version / build
- session ID、activation button、固定GestureClass
- source sequence、source kind、X/Y量、capture order、timestamp
- source sample countとcommand count
- ProductOutput family、generated batch count、generated event count
- terminal種別とretry count
- passthroughまたは変換対象
- successまたはfail-closed理由

`scroll`、`dockSwipe`、`dockSwipePinch`は内部ProductOutput familyとして記録する。`dockSwipePinch`はtype 30 / classifier 23のIOHID `DockSwipe` motion 4であり、application magnificationではない。ユーザーmodeまたはapplication別bucketにはしない。classごとにgenerated event数と単位が異なるため、event数のcross-class一致を要求しない。

## 正確性gate

次はlatencyより先に判定し、1件でも不一致ならrun全体を不合格にする。

| 指標 | 合格基準 |
| --- | --- |
| accepted source samples | source log、recognizer入力、fixed command件数が完全一致 |
| source sample identity | source kind、X/Y、符号、capture order、exact timestamp、session IDが一致 |
| duplicate / dropped / coalesced / reordered | すべて0件 |
| fixed class mismatch | button 3 / 4 / 5と2本指scroll / 3本指system swipe / 4本指system pinchの不一致0件 |
| family mismatch | classと`scroll` / `dockSwipe` / `dockSwipePinch`の不一致0件 |
| class contract mismatch | 2本指のtype 22 + type 29、3本指のtype 30 DockSwipe motion 1 / 2、4本指のtype 30 DockSwipe motion 4について、field、phase、batch、単位変換がregistered fixtureの許容差内 |
| terminal missing / duplicate | すべて0件 |
| terminal後のgenerated event | 0件 |
| partial batch order violation | 0件 |
| passthrough mutation / suppression / generation | button未押下時はすべて0件 |
| logger drop / unflushed record | 0件 |
| fail-closed後の誤出力 | 0件 |

1 source commandからscroll companionなど複数eventを生成してよい。source command、generated batch、batch内eventを別々に数え、複数eventをsource duplicateと誤判定しない。

## 保存する機械証跡

最低限、同じworktreeとbinaryで次を実行する。

```sh
swift build --scratch-path .build
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture-product-output-tests
.build/debug/nape-gesture benchmark --events 200000 --json --assert-baseline
.build/debug/nape-gesture doctor --benchmark-events 50000 --json
```

採用するreportは各GestureClassと未押下passthroughについて、少なくとも次を返す。

- source sample countとfixed command count
- duplicate、drop、coalesce、reorder count
- source identity照合結果
- ProductOutput family、batch count、event count
- class contract mismatch count
- session count、terminal count、stuck count、retry count
- passthrough mutation / suppression / generation count
- fail-closed scenario countと誤出力count
- 各区間のp50 / p95 / p99 / max
- wall time、CPU time、1 core換算CPU
- measurement kindとevent tap / system-wide postingの包含有無

pure logicとruntime実測を同じ`measurementKind`へ混ぜない。

## pure logic基準

pure logicはevent tap、CGEvent作成、system-wide投稿、AppKit受信、画面反映を含まない。`includesEventTapAndPosting`は`false`とする。

| 区間 | 平均 / CPU基準 | sample基準 |
| --- | --- | --- |
| source記録とbutton-to-GestureClass判定 | 2,000 ns/event以下 | p95 50,000 ns、p99 250,000 ns以下 |
| source command構築とsession validation | 2,000 ns/event以下 | p95 50,000 ns、p99 250,000 ns以下 |
| class payload planning | 2,000 ns/event以下 | p95 50,000 ns、p99 250,000 ns以下 |
| terminal state更新 | 2,000 ns/event以下 | p95 50,000 ns、p99 250,000 ns以下 |

test dataはbutton 3 / 4 / 5を同数含み、正負X/Y、斜め、停止、方向反転、異なるtimestamp間隔、move / wheel混在、正常terminal、cancelを含める。未押下passthroughは別bucketで同数以上測る。

## runtime遅延基準

runtime JSON Linesはevent tap受理、fixed command生成、最初のProductOutput event投稿、同batch投稿完了、terminal投稿完了を同じsessionとsource sequenceへ結び付ける。

| 区間 | 基準 |
| --- | --- |
| tap callbackからfixed command受理まで | p95 1 ms以下、p99 2 ms以下 |
| tap callbackから最初のProductOutput event投稿まで | p95 8 ms以下、p99 16 ms以下 |
| tap callbackから同じsource commandのbatch投稿完了まで | p95 8 ms以下、p99 16 ms以下 |
| terminal原因受理からterminal batch完了まで | p95 8 ms以下、p99 16 ms以下 |
| 未押下passthroughの追加処理時間 | p95 1 ms以下、p99 2 ms以下 |

投稿なしrecord、予定数と実投稿数の不一致、event作成失敗、class mismatch、terminal欠落をpercentileから除外して成功扱いにしない。正確性gateを先に判定し、その後で成功recordのlatencyを集計する。

## CPU基準

日常利用する`.app`を30秒以上実行して測る。

| 状態 | 平均CPU基準 |
| --- | --- |
| idle | 1%以下 |
| 未押下passthrough連続入力 | 10%以下 |
| 2本指scroll / swipe class | 15%以下 |
| 3本指system swipe class | 15%以下 |
| 4本指system pinch class | 15%以下 |
| terminal後5秒 | 1%以下へ戻る |
| fail closed待機 | 1%以下 |

loggerを同時実行する場合は製品processとlogger processを分け、queue depth、drop count、flush時間を記録する。

```sh
pid=$(pgrep -x nape-gesture | head -n 1)
top -l 30 -s 1 -pid "$pid" -stats pid,cpu,time,command
```

## 実機測定

pure logicとdirect ProductOutput smokeだけでは次を完了扱いにしない。

- Nape Pro source eventがtarget-device gateとevent tapへ届くまで
- button 3 / 4 / 5から固定GestureClass commandが生成されるまで
- 2本指のscroll + companion、3本指のDockSwipe motion 1 / 2、4本指のDockSwipe motion 4というclass固有event batchのsystem-wide実投稿
- 正常解放と異常終了のsingle terminal
- 未押下とterminal後passthrough
- TCC、device、contract不一致時のfail closed
- AppKit受信とOS / App画面結果

Nape Pro button 3 / 4 / 5と、対応する純正trackpad gestureを同じOS buildで測る。各classで短い列、長い列、高頻度列、方向反転、正常terminal、cancelを含める。

## OS / App結果時間

低レベル投稿時間と画面結果時間を分ける。

| 区間 | 扱い |
| --- | --- |
| post完了からAppKit受信まで | target logで測り、p95 16 ms以下を初期基準とする |
| AppKit受信から画面反映まで | applicationごとの観測値として保存する |
| system gestureの画面完了まで | OS buildと設定ごとの観測値として保存する |

OS / App結果のlatencyが大きくても、application別mode、AX、対象PID、keyboard shortcut fallbackを追加しない。

## fail closed性能

unsupported OS/build、scroll contract / model / DockSwipe templateの欠落または改変、device不一致、TCC不足、現在boot外timestamp、session不整合、partial batch失敗をfailure injectionと実利用binaryで測る。

合格条件:

- readiness確定前にevent tapと抑制を開始しない
- rejection後のgenerated eventが0件
- active sessionがsingle terminalまたは構造化された安全停止へ収束する
- 物理解放後にpassthroughへ戻る
- retry loopがCPU基準を超えない
- AX、PID、shortcut、別class fallbackが0件

## 採用条件

- 日常利用する`.app`と`doctor.runtimeIdentity`が一致する
- repo SHA、binary SHA-256、OS build、fixture identityがmanifestと一致する。25F80の正負方向別DockSwipe templateはID `recognized-dockswipe-templates-25F80-v2`、SHA-256 `852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6`を要求する
- 3 GestureClassと未押下passthroughを同じ基準で測定している
- 正確性gateが全て合格する
- runtime latencyとCPUが基準内にある
- 純正trackpadとNape Proの物理証跡がある
- fail-closed scenarioに誤出力がない
- OS / App結果時間を低レベル投稿時間へ混ぜていない

閾値超過または正確性違反があれば根本原因を修正し、pure logic、runtime、実機、fail closedのrunを取り直す。
