# Trackpad event logger local smoke

- 日付: 2026-07-11
- branch: `codex/trackpad-driver-events`
- 実行時HEAD: `e153f3cc6d71a7b7882bc7faff3db28ab2bc00b2`
- macOS: `26.5.1` / build `25F80`
- 対象: dirty worktree上の実装。commit後CIの代替ではない

## 機械検証

debug buildとcore tests:

```sh
swift build --scratch-path .build-trackpad-events
.build-trackpad-events/debug/nape-gesture-core-tests
```

結果:

```text
Build complete!
すべてのコアテストに成功しました。
```

repo標準の機械証跡も次で再実行した。

```sh
NAPE_COMPLETION_ARTIFACT_ROOT=/tmp/nape-trackpad-events-completion-evidence \
  sh scripts/collect-completion-evidence.sh
```

由来guard、product output boundary guard、debug / release build、core tests、app bundle、GUI smoke、doctor `outputContract` field、legacy diagnostic dry-run、fixturesのpositive / expected-failureを含む全項目が成功し、summaryは`機械証跡の収集は成功しました。`となった。

合成scrollを使ったlogger経路のpositive smoke:

```sh
.build-trackpad-events/debug/nape-gesture trackpad-event-log \
  --duration 5 \
  --out /tmp/nape-trackpad-logger-schema2.jsonl \
  --scenario-id schema2-smoke \
  --device-label diagnostic-generated-scroll \
  --repo-head-sha e153f3cc6d71a7b7882bc7faff3db28ab2bc00b2 &
logger_pid=$!
sleep 1
.build-trackpad-events/debug/nape-gesture generate-scroll \
  --x 0 --y -24 --steps 2 --interval 0.01
wait "$logger_pid"
```

結果はexit code 0、2 eventだった。次のassertionもexit code 0になった。

```sh
jq -e -s '
  length > 0
  and (all(.schemaVersion == 2))
  and (all(.rawFields | length == 256))
  and (all(.rawFields | map(.fieldNumber) == [range(0;256)]))
  and (all(.scrollFixedDeltaXBitPattern != null))
  and (all(.serializedEventBase64 | length > 0))
' /tmp/nape-trackpad-logger-schema2.jsonl
```

最初の`serializedEventBase64`はCoreGraphicsの`CGEventCreateFromData`相当で再構築でき、`typeRaw=22`、serialized data 260 bytesを確認した。

## SIGINT drain

`--duration`なしでloggerを開始し、合成scroll後に`SIGINT`を送った。

結果:

```text
SIGINTを受信したため、診断eventの受付を停止してqueueをdrainします。
トラックパッド診断イベントログを終了しました。events=3
```

exit codeは0で、保存JSON Linesは3行、`captureIndex == [0, 1, 2]`、各`rawFields`は256件だった。0 event captureは成功にせず非ゼロ終了する。

## 出力境界

```sh
sh scripts/check-product-output-boundary.sh
```

結果:

```text
product output boundary check passed
```

`doctor --probe-hid --json --assert-runtime-ready`はTCC / HID probe成功後も`outputContract.unsupported`だけを残して非ゼロ終了した。`run`も同じ理由でevent tap開始前に終了し、入力抑制を開始しなかった。

## 証跡境界

このsmokeはlogger、ordered schema、queue drain、serialized event復元、product fail-closedの機械検証である。合成scrollは純正trackpad driver上位出力contractではないため、Issue #125、trackpad scroll、DockSwipe、NavigationSwipe、magnificationの完成証跡には使わない。

純正trackpad物理操作、専用analyzer、commit後CI、PR reviewは未完了である。
