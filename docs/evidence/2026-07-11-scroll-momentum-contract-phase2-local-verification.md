# Scroll / momentum contract Phase 2 ローカル検証

> 非規範証跡: この文書が確認したのは2本指scroll / momentum内部contractの一部であり、scrollという製品mode、button assignment、2 / 3 / 4本指変換、製品完成を示さない。現在の採用条件は[証跡文書の扱い](README.md)を正とする。

## 対象

Issue #129 Phase 2のうち、macOS 26.5.1（build 25F80）で物理実測から確定したscroll、momentum、scroll companionだけを検証した。
NavigationSwipe、magnification、DockSwipe、Mission Control / App Exposeは対象外であり、この検証をIssue #125 / #129全体または製品完成の証跡にはしない。

## Fixture identity

- fixture: `Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json`
- fixture ID: `trackpad-scroll-momentum-25F80-v1`
- contract ID: `trackpad-scroll-momentum-v1`
- schema: `1`
- SHA-256: `8e2a1841ef23a47fcb274c1c8e7c7c39be43e8ab7c8792caf2cd874242a61294`
- OS: `26.5.1` / `25F80`

`physical-observations.json`は8 captureと未取得境界を持つ更新可能な観測台帳、`scroll-momentum-contract.json`は確定済みscrollだけをSHA固定する実行contractとして分離した。
Core readerはfixture ID、contract ID、schema、SHA-256、OS version / buildの完全一致だけを受理する。公開contract documentは外部moduleから生成・変更できない値型にし、analyzer入口でもregistryを再検証する。

`--fixtures-only`検証は専用fixture SHA、観測台帳のcontract ID / OS / device / logger /観測規則、採用4 sourceのfile名 / SHA / event数 / prefix / `analysisStartCaptureIndex` / wall-clockを完全一致で結ぶ。full原本検証はさらに同じsource bytesとmanifestを再読込するため、専用contract、公開台帳、186 MBのlocal原本を別々に差し替えて通すことはできない。

## 原本再導出

実行:

```sh
ruby -c scripts/verify-trackpad-physical-observations.rb
ruby scripts/verify-trackpad-physical-observations.rb --json
```

結果:

| Scenario | Scroll lifecycle | Momentum lifecycle | Companion / pairable scroll | 未対応phase |
| --- | ---: | ---: | ---: | --- |
| vertical scroll | 3 | 3 | 250 / 252 | 2 |
| horizontal scroll | 3 | 4 | 390 / 392 | 2 |
| momentum stop | 5 | 5 | 29 / 30 | 2 |
| cancel / reverse | 8 | 2 | 496 / 498 | 2 |

合計はcompanion `1,165 / 1,172`、captureIndex差は`-1 / +2 / +3 / +4`、scrollとのtimestamp同値は0組だった。
全4 scenarioでphase相互排他、scroll / momentum terminalのnamed delta 9種とdoubleの`+0.0` bit pattern、momentum開始直前のscroll ended、lifecycle内type 22 timestamp非減少、companion motion alias、constant field、必須phase対応、最低coverage `29 / 30`を再導出した。

horizontal原本の先頭はcapture開始前から続くpartial scroll系列である。原本verifierは最初のcomplete began以降をlifecycleとして数え、専用fixtureは`analysisStartCaptureIndex=622`を持つ。generated candidateにはこの例外を適用しない。

## 物理原本CLI

4つの採用sourceへ次の形式で実行した。

```sh
.build/debug/nape-gesture analyze-trackpad-event-log \
  <physical.jsonl> \
  --manifest <physical.jsonl.manifest.json> \
  --contract Fixtures/trackpad-contract/25F80/scroll-momentum-contract.json \
  --json
```

結果:

| Scenario | Exit | Scroll lifecycle | Momentum lifecycle | Paired companion | Issues |
| --- | ---: | ---: | ---: | ---: | ---: |
| vertical scroll | 0 | 3 | 3 | 250 | 0 |
| horizontal scroll | 0 | 3 | 3 | 211 | 0 |
| momentum stop | 0 | 5 | 5 | 29 | 0 |
| cancel / reverse | 0 | 8 | 2 | 496 | 0 |

horizontal CLIは登録済み`analysisStartCaptureIndex`より前のpartial scrollと、それに続くmomentumを比較対象から除外するため、原本全体の再導出値とはmomentum / companion件数が異なる。
各manifestはsource SHA、件数、device、logger repo / executable SHA、capture wall-clockまで専用fixtureと一致した。

## Generated candidate CLI

`nape-gesture-diagnostic-output-tests --write-trackpad-analyzer-fixtures`で、実CGEvent snapshot由来の次の3列を生成した。

- 正常列: scroll `1 -> 2 -> 4`、各phaseのtype 29 envelope / companion、momentum `1 -> 2 -> 3`の12 event
- terminal欠落列: 正常列からmomentum terminalだけを除いた11 event
- 未確定gesture列: 正常列のenvelope 1件をraw 110=`7`へ置換した12 event

全eventへgenerated marker、全provenanceへsystem-wide deliveryと同じscroll session IDを設定した。type 22はprovenance kind `scroll`、type 29 envelope / companionは同じscroll familyの`gesture`としてactual typeと照合した。

正常列:

- exit `0`
- structure / manifest / host reconstruction / provenance / contract comparisonがすべて成功
- scroll lifecycle `1`、momentum lifecycle `1`、companion `3 / 3`

terminal欠落列:

- exit `1`
- structure / manifest / host reconstruction / provenanceは成功
- contract comparisonだけが失敗
- issue codeは`missing_momentum_terminal`と`missing_momentum_lifecycle`

これにより、Phase 1の別section失敗へ隠さず、Phase 2 contractだけで欠落terminalを終了codeへ反映できることを確認した。

未確定gesture列:

- exit `1`
- structure / manifest / host reconstruction / provenanceは成功
- contract comparisonだけが`unconfirmed_gesture_event`で失敗

generated scroll familyのtype 29は、確定済みenvelope raw 110=`0`とcompanion raw 110=`6`だけを許可する。magnificationやDockSwipeなど別candidate familyをscroll contractへ混入して合格させない。

Core mutation testでは、manifest SHAを別値へ変えた入力を`manifest_document_mismatch`、重複capture indexをtrapではなく`capture_index_mismatch`、terminalの`-0.0`を`terminal_delta_mismatch`として拒否した。Ruby verifierも起動時のdetector自己検証で`+0.0`受理と`-0.0`拒否を確認する。analyzerはdocumentのraw line bytesをLF付きで再構成してmanifestへ照合し、そのbytesをstrict parserで再解析してから意味比較する。
テスト用CGEventはsystem-wideへ投稿していない。

## 全機械証跡

実行:

```sh
NAPE_COMPLETION_ARTIFACT_ROOT=artifacts/completion/2026-07-12/trackpad-contract-phase2-final \
  sh scripts/collect-completion-evidence.sh
```

結果は`artifacts/completion/2026-07-12/trackpad-contract-phase2-final/summary.md`の`機械証跡の収集は成功しました`である。
由来guard、product output境界guard、時刻guard、debug / release build、core tests、diagnostic output tests、Phase 1 schema 1互換CLI、Phase 2正常 / terminal欠落 /未確定gesture CLI、専用fixtureと公開台帳のidentity照合、local物理原本照合、app bundle、codesign構造、GUI smoke、doctor、benchmark、既存system / fixture回帰が成功した。

## 未完了境界

- Issue #125の残るNavigationSwipe左右、pinch方向、DockSwipe反対方向 / cancel、Mission Control / App Expose物理capture
- Issue #129のNavigationSwipe / magnification / DockSwipe contract比較
- Issue #119の製品scroll / companion / momentum adapter
- product output registry、daemon統合、system-wide実投稿とReference Target / Finder / Safari受信
- Nape Pro実機比較、常駐性能、署名 / 公証

専用analyzer合格だけでは`ProductGestureOutputContractRegistry`をsupportedにしない。
