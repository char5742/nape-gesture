# ADR-0042: 25F80 scroll / momentum契約を独立fixtureで比較する

> 本ADRはscroll / momentum fixture identityとstrict比較規則を、2本指scroll / swipe classの内部contractとして定義する。scrollはユーザーが選ぶ製品modeではない。button 3 / 4 / 5の固定変換を判定するには、[ADR-0049](0049-fixed-button-to-gesture-class-input.md)に従い3つのclass固有event contractと変換前後の量を別途比較する。

- 状態: 採択
- 日付: 2026-07-11
- 更新日: 2026-07-14

## 背景

`physical-observations.json`は、純正trackpadの8 captureと未取得境界をまとめた観測台帳である。
3つの物理GestureClassの追加captureにより今後も更新されるため、この台帳全体のSHA-256を確定済みscroll / momentum内部契約として使うと、無関係な観測追加でもcontract identityが変わる。

また、`TrackpadDriverEventLog`のtyped decoderはlegacy schemaへ既定値を補い、raw fieldを数値順へ正規化する。
意味解析をtyped modelだけへ直接適用すると、欠落や並べ替えを補完後の値で見落とす可能性がある。

## 決定

- 確定済みscroll / momentumだけを`Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json`へ分離する。
- fixture ID、contract ID、schema、bytesのSHA-256、収録元OS version / buildをCore registryへ固定し、完全一致しないfixtureをfail closedにする。このOS情報はcapture fixtureの由来であり、製品runtimeのhost許可listではない。
- fixtureはreference device、logger repo SHA、logger executable SHA、採用した4 captureのsource log SHA、件数、contract prefix、解析開始capture index、capture wall-clockを保持する。
- 観測台帳の`partial`状態は維持する。専用fixtureの`confirmed`は2本指scroll / momentum内部contractだけを指し、ほかのGestureClass、OS/App結果、製品完成を意味しない。
- 専用fixtureと公開観測台帳は、contract ID、OS、device、logger、4 sourceのfile名 / SHA / 件数 / prefix / 解析開始index / wall-clock、観測規則を機械照合する。local原本検証では同じsource SHAとmanifestを再読込し、公開contractまで一続きに結合する。
- contract解析はPhase 1のstrict JSON Lines解析とmanifest検証が成功した`TrackpadDriverEventDocument`だけを受け取る。Core API内でもfixture登録を再検証し、全documentのraw line bytesをLF付きで再構成してmanifestへ照合した後、strict parserを再実行する。外部から渡されたtyped値やcapture indexをそのまま信用しない。
- `analyze-trackpad-event-log --contract <path>`を明示した場合だけcontract比較を終了code gateへ加え、report schemaを2にする。未指定のPhase 1呼び出しはschema 1と既存JSON shapeを維持し、`contractPath` / `contractComparison`を出力しない。
- fixture読込失敗、未登録SHA、strict解析またはmanifest失敗、収録元OS build不一致、未確定scenarioは、理由を`contractComparison.issues`へ残して非ゼロ終了する。この比較はcapture provenance用であり、製品runtimeのhost OS判定には使わない。
- `synthetic`は純正contract合格証跡にしない。`physicalTrackpad`は登録source identityとの完全一致、`generatedProduct`は同じOS build / scenario上の候補列として比較する。
- generated provenanceでは同じscroll family内のtype 22を`scroll`、type 29 companion / envelopeを`gesture`として記録し、actual event typeとの一致を検証する。contract比較中のgenerated eventはtype 22 / 29だけ、type 29はraw 110=`0`または`6`だけを許可し、それ以外やclassifier欠落を未確定gesture混入としてfail closedにする。

## Scroll / momentum規則

- type 22、raw 55のtype、raw 58のtimestamp、raw 88=`1`をtop-level named fieldと照合する。
- scrollはraw 99の`1 -> 2* -> 4`とし、raw 128はsessionを開始しないmayBeginとして扱う。未観測のcancel値を推測しない。
- momentumはraw 123の`1 -> 2* -> 3`とし、scroll ended後にだけ開始する。
- 同じtype 22 eventでscroll / momentum phaseを同時にactiveにしない。同一lifecycle内のtype 22 timestampは非減少とする。
- scroll endedとmomentum terminalはinteger / fixed / pointのXYZ全9 named deltaを正のzeroにする。Swift analyzerとRuby原本verifierの両方でdouble bit patternが`+0.0`であることを検査し、`-0.0`を受理しない。
- began前changed、二重began、未知phase、terminal欠落・重複、terminal後の継続を失敗にする。

## Companion規則

- type 29全体ではなくraw 110=`6`だけをscroll companion、raw 110=`0`だけをenvelopeとする。generated scroll familyへそれ以外のtype 29 classifierを混在させない。type 29のraw 123はY motionのFloat32 bit aliasであり、momentumとして解釈しない。
- companion直前のcaptureIndexにtype 29 / raw 110=`0`のenvelopeがあり、同じtimestampを持つことを必須にする。
- raw 132のphase、motion double field群、Float32 bit alias、constant fieldをfixtureと照合する。
- scrollとの対応は1対1、順序保存、phase一致、captureIndex距離8以内とする。候補はtimestamp絶対差、次にcaptureIndex距離で選ぶ。
- timestamp同値や固定captureIndex差を要求しない。余分なstandalone envelopeは許可する。
- mayBegin / began / endedのcompanion欠落は許可しない。changedの未対応だけを許可し、全体対応率は物理4 captureでの下限`29 / 30`以上を必須にする。

## 影響

- 3つの物理GestureClassの追加観測と、確定済み2本指scroll内部contractのidentityを独立して更新できる。
- 生成候補のmissing terminal、missing companion、未確定type 29、envelope、phase、field alias、OS build差分を同じCLI reportと終了codeで判定できる。
- analyzer合格だけでは製品runtimeをsupportedにしない。button 3 / 4 / 5の固定GestureClass対応、class固有単位変換、session、suppressionを製品runtimeの別gateで検証する。
- horizontal source先頭のcapture開始前から続くpartial系列は、登録sourceの`analysisStartCaptureIndex`より前として物理原本比較から除外する。generated candidateの途中開始は許可しない。

## 関連

- [ADR-0036: trackpad driver上位出力eventを再現する](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0039: trackpad eventログを厳格解析しcapture manifestへ固定する](0039-strict-trackpad-event-analysis-and-capture-manifest.md)
- [ADR-0040: capture順とevent timestampを分離する](0040-capture-order-and-event-timestamp.md)
- [ADR-0041: 物理captureのready同期と公開fixture境界を固定する](0041-physical-capture-readiness-and-fixture-privacy.md)
- [物理capture証跡](../evidence/2026-07-11-physical-trackpad-contract-capture.md)
- [ADR-0049: buttonを固定GestureClassへ接続する](0049-fixed-button-to-gesture-class-input.md)
