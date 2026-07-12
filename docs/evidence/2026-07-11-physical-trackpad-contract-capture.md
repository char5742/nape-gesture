# 純正トラックパッド物理captureとcontract再導出

> 非規範証跡: この文書は物理captureのraw観測記録である。event family候補と画面scenarioはbutton assignmentまたは製品機能を意味せず、2 / 3 / 4本指とmouse event量の対応も未確定である。現在の採用条件は[証跡文書の扱い](README.md)を正とする。

## 目的

Issue #125として、macOS 26.5.1（build 25F80）の純正トラックパッドから、scroll、momentum、page swipe、pinch、Spaces、Mission Control / App Exposé、途中反転の同一raw schema収録を試行した。Mission Control / App Exposéだけは取得窓不成立で識別payloadを得ていない。

本証跡では、`physicalTrackpad` captureを正本としてfieldと順序を再導出する。

## Logger

- repo HEAD: `b50e607ddde8e23b5467f4997bb3e1f3ee0c139e`
- executable SHA-256: `00c4cbbc83bbc7c2568eae99cfd63edbb405c44c80294672e93416153a577fa3`
- manifest schema: 2
- device label: `built-in-trackpad`
- OS: macOS 26.5.1
- OS build: 25F80

## Capture結果

| Scenario | Events | Structure | Manifest | Host | 生成marker | 判定 |
| --- | ---: | --- | --- | --- | ---: | --- |
| vertical scroll | 1,228 | pass | pass | pass | 0 | scroll contractへ採用 |
| horizontal scroll | 1,565 | pass | pass | pass | 0 | scroll contractへ採用 |
| momentum stop | 440 | pass | pass | pass | 0 | momentum contractへ採用 |
| page swipe left / right | 812 | pass | pass | pass | 0 | candidate。完結したtype 31系列なし |
| pinch in / out | 1,278 | pass | pass | pass | 0 | candidate。正負と物理ラベル未対応 |
| Spaces left / right | 409 | pass | pass | pass | 0 | candidate。DockSwipe 1方向だけ |
| Mission Control / App Exposé | 109 | pass | pass | pass | 0 | 取得窓不成立。識別payload 0件 |
| cancel / reverse | 3,143 | pass | pass | pass | 0 | cancel / reverse contractへ採用 |

manifestの開始・終了wall-clock、source log SHA-256、prefix件数、target件数は[観測台帳](../../Fixtures/trackpad-contract/25F80/physical-observations.json)へ保存した。確定済みscroll / momentumだけの実行契約は、candidate family追加時にidentityを変えない[versioned fixture](../../Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json)へ分離した。

## 収録中に修正した問題

### 配送順とtimestamp

`scrollWheel`の後に配送されるcompanion eventが、より小さいtimestampを持つ系列を観測した。
配送順は`captureIndex`、timestampは取得値として別々に保持する。timestampでsortせず、局所逆行だけでは失敗にしない。

この決定は[ADR-0040](../adr/0040-capture-order-and-event-timestamp.md)へ保存した。

### subtype取得時のprocess crash

旧loggerは全CGEventへ無条件に`NSEvent.subtype`を要求し、`flagsChanged`で`NSInternalInconsistencyException`終了した。
AppKitがsubtypeを公開するevent typeだけを変換し、private eventと通常入力では`eventSubtype`を`nil`にしてraw fieldとserialized eventを保持するよう修正した。

### capture開始同期

短いdurationでは、操作指示を読んでから物理操作を始める前に取得窓が閉じることがあった。
`--ready-file`はcaptureごとの`--ready-token`を必須とし、tokenをfile名に含む未使用pathを使う。loggerは権限確認前に`ready: false`の排他的leaseを作り、event受付開始時だけtoken、PID、開始wall-clock、有限durationのdeadline、scenario ID、repo HEAD SHAを持つ`ready: true`へatomic更新する。起動側は全fieldとPID生存を確認してから操作する。duration満了、SIGINT、内部errorではevent受付停止前に`ready: false`へ戻して`unlink`する。

ready lifecycleのlocal smokeでは、2秒・0 eventの失敗経路とSIGINT経路が終了コード1、manifestなし、ready撤回となった。3秒のsynthetic 384 event経路は、processがmanifest後処理中で生存している時点ですでにreadyが消え、終了コード0、manifest / analyzer passとなった。同じpathの2本目は排他的lease取得前に失敗した。manifest予定fileとready親pathのcase違い、Unicode正規化違いもdirectory作成前に拒否した。

専用waiterの回帰では、正常recordだけが操作案内を出し、SIGKILL後に残った`ready:true`、deadline余裕不足、process生存中でもready撤回済みのmanifest後処理窓、安定化待機中の`ready:false`更新はいずれも非ゼロ終了し、操作案内を出さなかった。

### 生成event混入

調査用の旧captureに生成markerが混入した事例があった。
manifest検証は`physicalTrackpad` logに`NapeGestureGeneratedEventMarker`が1件でもあれば、最初の`captureIndex`を報告して失敗する。

## Scroll contract

- scroll eventはtype 22。
- raw 55はtype、raw 58はtimestamp、raw 88はcontinuous `1`。
- scroll phaseはraw 99で、`1 → 2* → 4`。raw 128はpreflight / mayBegin候補で、terminalとして扱わない。
- momentum phaseはraw 123で、type 22だけに`1 → 2* → 3`が現れる。
- momentum terminal `3`はnamed deltaがすべて0。tap停止もcancel値ではなくterminal `3`だった。

## Scroll companion contract

- type 29全体ではなく、raw 110=`6`だけをscroll companion候補とする。
- 直前にtype 29 / raw 110=`0`のenvelopeがあり、同じtimestampを持つ。
- companion phaseはraw 132。
- X motionはraw 113 / 114 / 116 / 118、Float32 bit pattern aliasはraw 115 / 117 / 164。
- Y motionはraw 119 / 139、Float32 bit pattern aliasはraw 123 / 165。
- 1,165組でcompanion timestampは対応scroll timestampと同値ではなく、captureIndex差は`-1 / +2 / +3 / +4`だった。
- 対応はscroll raw 99とcompanion raw 132のphase一致、capture順保存、captureIndex距離8以内を必須とし、未対応の余分なscroll sampleを許可する。候補はtimestamp絶対差、次にcaptureIndex距離が小さい順で選ぶ。この規則と直前envelopeの同一timestampを原本照合scriptで再計算する。
- scrollとcompanionをarray位置でzipせず、timestamp同値や固定captureIndex差も要求しない。
- type 29でraw 123をtop-level momentumとして読まない。subtype 6ではY motionのFloat32 bit patternである。

## NavigationSwipe候補

- page captureのtype 30 / raw 110=`23`に4つの`1 → 2* → 4`系列がある。
- phaseはraw 132と134が一致する。
- signed progressはraw 124、Float32 bit pattern aliasはraw 135。
- 同方向motion候補はraw 125、直交motion候補はraw 126。
- terminalだけraw 129と130に同じ非0速度候補が現れ、符号はprogressと一致する。

ただしtype 30 / raw 110=`23`はpinchとSpacesにも存在し、この分類だけでNavigationSwipeと確定しない。
schema 1の旧captureにはtype 31 / raw 110=`27`が21件あるが、`began`後に`changed`だけで取得窓が終わり、開始wall-clockとterminalを欠くため正本にしない。

## Magnification候補

- pinch captureのtype 29 / raw 110=`8`に6つの`1 → 2* → 4`系列がある。
- 各magnification候補の直前にはtype 29 / raw 110=`4`のenvelopeがあり、pinch captureで179件観測した。scroll companionのenvelope値`0`とは別分類である。
- signed scale delta候補はraw 113 / 114 / 116 / 118。
- Float32 bit pattern aliasはraw 115 / 117 / 164。
- 観測範囲は`-0.1626434326171875...+0.1302947998046875`。
- phase 2のまま正負反転する系列があり、途中反転を保持する。
- terminalでもscale deltaは0必須ではない。

物理pinch-in / pinch-outと符号のaction markerがないため、方向名はまだ固定しない。

## DockSwipe候補

- Spaces captureのtype 29 / raw 110=`32`に1つの`1 → 2* → 4`系列がある。
- progressはraw 119 / 139 / 148、Float32 bit pattern aliasはraw 123 / 165。
- active候補raw 143はbegan / changedで`1`、endedで`0`。
- direction / motion code候補raw 144は全件`5`。
- terminalはphase `4`、progress `0`、active `0`。

1方向だけなのでraw 144の意味、反対方向、独立した終了速度、cancel terminalは未確定である。

## Privacyとfixture境界

raw logは合計186 MBで、操作完了後のキー入力やpointer座標を含むためgitへ追加しない。
原本は`artifacts/trackpad-contract/2026-07-11-b50e607/`へ保持し、各manifestのSHA-256で固定する。
`ruby scripts/verify-trackpad-physical-observations.rb --fixtures-only --json`はraw原本なしでも、専用contractの固定SHAと観測台帳のcontract ID / OS / device / logger /観測規則、採用4 sourceのfile名 / SHA / event数 / prefix /解析開始index / wall-clockを照合する。`--fixtures-only`を外すと8本とlegacy 1本を再読込し、同じsource SHAとmanifestへ結合した上で、keyboard境界prefix、target件数、生成marker 0件、scroll / momentum lifecycle、terminal deltaの`+0.0` bit pattern、companion field alias、1,165組とcaptureIndex差`-1 / +2 / +3 / +4`、timestamp非同値を再導出する。

公開fixtureには次だけを保存する。

- source log SHA-256、event数、capture wall-clock
- contract対象prefix件数
- event type、raw classifier、phase、field番号、件数、観測範囲
- 確定 / candidate / 未取得の状態

serialized event、keycode、pointer座標、raw device identifierは公開fixtureへ含めない。

## 残る物理capture

次の4点は値を推測せず、`--ready-file`同期後に追加captureする。

1. terminalを含むNavigationSwipe left / rightとaction marker
2. pinch-in / pinch-outのaction markerと符号対応
3. DockSwipe反対方向とcancel
4. Mission Control / App Exposé

これらが揃うまでIssue #125全体を完了扱いにせず、fixture statusは`partial`を維持する。

## 検証コマンド

```sh
swift build --scratch-path .build
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture-diagnostic-output-tests
ruby scripts/verify-trackpad-physical-observations.rb --json
ruby scripts/test-wait-for-trackpad-capture-ready.rb

jq -e '.schemaVersion == 1 and .status == "partial"' \
  Fixtures/trackpad-contract/25F80/physical-observations.json
jq -e '.schemaVersion == 1 and .status == "confirmed" and .osBuild == "25F80"' \
  Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json

.build/debug/nape-gesture analyze-trackpad-event-log \
  artifacts/trackpad-contract/2026-07-11-b50e607/vertical-scroll.jsonl \
  --manifest artifacts/trackpad-contract/2026-07-11-b50e607/vertical-scroll.jsonl.manifest.json \
  --contract Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json \
  --json
```
