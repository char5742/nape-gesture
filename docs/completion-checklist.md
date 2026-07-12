# 完成判定チェックリスト

この文書は、Nape Gestureの製品完成を実測証跡で判定する正本である。
build、単体test、GUI起動、個別の低レベルevent生成が成功しても、ここで定義する必須ゲートが1つでも未達なら製品完成とは扱わない。
製品モデルの設計判断は[ADR-0049](adr/0049-fixed-button-to-finger-count-trackpad-input.md)を正とする。

## 固定する製品モデル

製品モデルは次の1つだけである。

| mouse入力 | 生成するtrackpad入力 |
| --- | --- |
| button 3押下中の連続mouse event量 | 2本指 |
| button 4押下中の連続mouse event量 | 3本指 |
| button 5押下中の連続mouse event量 | 4本指 |
| button 3 / 4 / 5のいずれも未押下 | 元のmouse入力をそのまま通す |

- buttonごとに結果を選ぶユーザーmodeは設けない。
- 方向ごとのaction、OS/App結果ごとのaction、application別設定は設けない。
- AX scrollbar、対象PID配送、frontmost application分岐、keyboard shortcutを製品fallbackにしない。
- `scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`は低レベルevent familyまたは観測語彙であり、ユーザーmodeや独立した製品機能ではない。
- 低レベル入力を受けて何が起きるかはOS/Appが解釈する。OS/App結果を先に選び、それに合わせて配送方式やevent familyを切り替えない。
- 同じsource event列をbutton 3 / 4 / 5へ与えた場合、生成列は同じ正規化入力の量、順序、時間間隔を使う。finger count固有の物理encoding差だけを登録contractで許容し、結果別またはfinger count別の変換係数は持たない。

## 現行実装の状態

この文書の改訂基準commitは`55eb991`である。このcommitには`TrackpadGestureMode`、buttonごとのmode選択UI、`supportedFamilies` / `confirmedFamilies` / `trialFamilies`、modeから`scroll` / `DockSwipe` / `magnification`へ分岐する製品経路が残っている。
したがって、基準commitの現行実装は上記の固定製品モデルに**未達**であり、リリース可能または製品完成とは判定しない。

並行実装中の未commit差分や、旧modelのtestが成功しただけではこの状態を更新しない。次の全ゲートについて、変更後binaryと同じrepo SHAを持つ証跡がそろった時だけ状態を更新する。

## 状態

| 状態 | 意味 |
| --- | --- |
| `未達` | 固定製品モデルを満たす実装または証跡がない |
| `基盤のみ` | logger、analyzer、fixtureなどを再利用できるが、必須ゲートの合格証跡ではない |
| `実機待ち` | 機械testを完了し、純正trackpadまたはNape Proの物理操作だけが残る |
| `完了` | 現行binaryについて必要な機械証跡と実機証跡がそろい、未検証事項がない |

`完了`は行ごとの局所的な実装完了を表さない。6つの必須ゲートは相互に代用できず、全て`完了`でなければ製品完成にしない。

## 証跡の共通要件

証跡は次の形式でrunごとに分離する。

~~~text
artifacts/completion/YYYY-MM-DD/<repo-sha>/<scenario-id>/
~~~

各runには最低限、次を保存する。

- 実行コマンドと終了コード
- repo SHA、binary SHA-256、macOS version / build、実行主体、TCC状態
- run UUID、scenario ID、開始・終了時刻
- 入力元、button番号、期待finger count
- source eventのkind、単位、phase、capture order、timestamp、delta、件数、累積event量
- 生成したtrackpad eventの順序、timestamp、finger count、低レベルfield、session ID
- terminal種別と理由
- passthrough、抑制、生成、破棄の各件数
- 使用したfixtureのschema、ID、SHA-256
- manifestと各logのSHA-256
- analyzer report、未検証事項、失敗時のfailure code

目視メモやscreen recordingは補助証跡であり、manifest、raw log、analyzerの終了コードを代用しない。
異なるrepo SHA、binary、OS build、scenarioのlogを1つの成功runとして継ぎ合わせない。

## 必須完成ゲート

| ゲート | 完成条件 | 必要な機械証跡 | 必要な実機証跡 | 現在状態 |
| --- | --- | --- | --- | --- |
| event量保存 | 押下中に受理した各source eventを欠落・重複・coalescing・順序変更なく1回だけ変換する。変換前の各sampleと累積量はbit単位で一致し、trackpad量は登録済みの単一versioned単位変換contractの許容差内に入る。同一fixtureでは正規化入力の量、順序、時間間隔を変えない | 正負、斜め、停止、方向反転、異なるevent間隔、長時間列、queue圧迫、部分投稿失敗のpure testとproperty test。3 button同一fixture比較とsource-to-output対応report | button 3 / 4 / 5それぞれのNape Pro連続操作logと、同じfinger countの純正trackpad比較 | `未達` |
| finger count | button 3 / 4 / 5を2 / 3 / 4本指へ固定対応し、session途中で変化させない。進行中の追加buttonでもfinger countとsession IDを切り替えず、開始時に一意化できない入力から推測しない | 全button、全方向、方向反転、session中追加button、開始時の曖昧同時押下拒否、未知button拒否、設定migrationのtest。全出力frameのfinger count検証 | 純正2 / 3 / 4本指captureと、対応するNape Pro生成captureの比較 | `未達` |
| session terminal | button押下から解放までを1 sessionとし、正常終了、cancel、kill switch、runtime stop、sleep、device切断、権限喪失、output failureの全経路が重複なしのterminalへ収束する。terminal後に同sessionの出力を続けない | session ID、順序、単調timestamp、terminal 1回、stuck 0件、部分投稿の収束、再入拒否のtest | 各buttonの正常解放と、少なくともkill switch、device切断、sleepまたは権限喪失の実測 | `未達` |
| passthrough | button 3 / 4 / 5未押下時はclick、drag、move、wheelを抑制・変更・再生成しない。対象外deviceも常にそのまま通す。session終了後は物理解放を境に通常mouseへ戻る | event種別ごとのidentity、生成0件、抑制0件、変更0件、解放境界、対象外device、失敗後復帰のtest | Nape Proと通常mouseで未押下、各session直後、kill switch直後の前面App target log | `未達` |
| 実機証跡 | 純正trackpad 2 / 3 / 4本指と、Nape Pro button 3 / 4 / 5のsource / generated logを同一schema、同一OS build、登録manifestで比較できる。fixtureの由来と公開範囲が追跡できる | logger readiness、strict parser、manifest、provenance、fixture登録、hash不一致のexpected failure | 純正trackpadとNape Proの物理capture。合成input、dry-run、画面移動だけでは代用不可 | `未達` |
| fail closed | unsupported OS/build、fixture/hash/schema不一致、finger count不明、device不一致、TCC不足、現在boot外timestamp、source / contractにないtimestamp変換、session不整合、event作成・投稿失敗では新規抑制・生成を開始しない。active sessionは安全なterminalへ収束し、AX/PID/shortcutや別familyへfallbackしない | failure injection、未知build、明示path不正、fixture改変、開始時の曖昧同時button、部分投稿、terminal生成失敗、readiness gateのtest | unsupported条件またはTCC喪失を含む実利用binaryで、誤出力0件と通常入力復帰を確認 | `未達` |

## 低レベルcontract判定

低レベルcontractは、上記6ゲートを支える証跡としてfinger countごとに判定する。

| 判定対象 | 合格条件 |
| --- | --- |
| fixture登録 | schema、fixture ID、SHA-256、OS version / build、source identity、capture範囲が完全一致する |
| event量 | source event件数、delta合計、順序、timestampと、変換modelへの入力が一致する |
| finger count | 2 / 3 / 4の期待値が全frameとterminalで一貫する |
| lifecycle | began / changed / terminalなど、実測contractが要求する系列が完結する |
| provenance | source、generated capture、post trace、manifest、binaryが同じrun UUIDで結合する |
| 配送境界 | system-wide streamだけを使用し、AX、対象PID、shortcut、application分岐がない |

`scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`という分類はreportの観測列として保持してよい。ただし、familyごとの`supported`、`confirmed`、`trial`を製品完成度として集計せず、family単体の成功をbutton 3 / 4 / 5の完成へ読み替えない。

## OS/App結果の別判定

OS/App結果は低レベルcontractと別のmatrixへ記録する。

| 記録項目 | 判定方法 |
| --- | --- |
| 入力条件 | button、期待finger count、event量、方向、速度、session IDを記録する |
| 低レベル成立 | contract analyzerの結果とfixture identityを参照する |
| OS/App結果 | 前面App、OS設定、画面結果、AppKit target logをscenario単位で記録する |
| terminal | 結果の有無にかかわらずsessionがterminalへ収束し、stuckしないことを確認する |
| 主張範囲 | 実測したOS buildとApp versionだけを記載し、未測定結果を製品機能として主張しない |

縦横scroll、application navigation、Space切替、Mission Control、App Exposé、Zoomなどは結果例である。特定結果を得るためのmode、方向別action、application別設定、別配送fallbackを追加しない。
低レベルcontractが合格してOS/App結果が不成立の場合は、contract合格と結果不成立を別々に記録する。画面が動いてもcontract不合格なら製品合格にしない。

## 補助ゲート

次は配布に必要だが、6つの必須ゲートを代用しない。

- debug / release buildと全test targetが成功する
- product / diagnostic module境界guardが成功する
- `.app`のbundle identity、同梱文書、署名、公証、stapler、Gatekeeper評価が成功する
- `doctor`が実行主体、TCC、対象device、contract provenance、fail-closed理由を構造化して返す
- 常駐CPU、tap-to-terminal遅延、logger drop countが性能基準内にある
- READMEと配布文書が固定製品モデル、未達事項、実測済みOS/App結果と矛盾しない

## 履歴証跡の扱い

2026-07-11以前および基準commit`55eb991`までの次の証跡は、移行前実装の履歴またはlogger基盤としてのみ保持する。

- buttonごとの`通常` / `2本指スクロール / スワイプ` / `システムスワイプ` / `ピンチ`選択
- `scroll`をconfirmed、`DockSwipe` / `magnification`をtrialとする3 family状態
- `NavigationSwipe`を候補familyとして製品routingと別管理した結果
- forced horizontal scroll、単純pixel scroll、keyboard shortcutによる結果
- AX、対象PID、frontmost application分岐を使った配送結果
- 旧`gesture-*` scenario、旧mode別performance count、旧family別completion表

これらのbuild、test、runtime、画面結果が成功していても、event量保存、2 / 3 / 4 finger count、session terminal、passthrough、現行実機証跡、fail closedの合格には使わない。
既存のtrackpad event logger、strict analyzer、manifest、scroll fixtureは再利用可能な`基盤のみ`とし、新modelのrun UUIDと登録fixtureで再取得・再判定する。

## 自動検証と実機作業

自動化は先に実行し、失敗を残したまま実機作業へ進まない。

~~~sh
ruby scripts/check-product-model-documentation.rb
ruby scripts/check-finger-count-product-model.rb
swift build --scratch-path .build
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture-product-output-tests
sh scripts/check-product-output-boundary.sh
~~~

基準commitでは`check-finger-count-product-model.rb`が廃止対象sourceを列挙して非ゼロ終了するため、`collect-completion-evidence.sh`も成功を返さない。core / product testは移行前契約を含み、成功しても新modelの完成証跡ではない。source、test、fixture、doctor、収集scriptを固定製品モデルへ更新し、両guardと変更後testが同じbinaryに対して成功して初めて採用する。

最後に必要な物理作業は次のとおりである。

1. 純正trackpadで2 / 3 / 4本指の連続入力、方向反転、正常terminal、cancelを取得する。
2. Nape Proでbutton 3 / 4 / 5を個別に押し、同じevent量系列を取得する。
3. 未押下時、各button解放直後、異常終了直後のpassthroughを前面Appで取得する。
4. kill switch、sleep、device切断、TCC喪失のterminalとfail closedを取得する。
5. OS/App結果を低レベルcontractとは別scenarioで取得する。
6. 公開配布時だけDeveloper ID署名、公証、stapler、Gatekeeper評価を取得する。

人間が観察した内容は必ず同じscenarioのraw log、manifest、analyzer reportへ結び付ける。目視だけの「動いた」は完成証跡にしない。
