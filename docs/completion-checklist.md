# 完成判定チェックリスト

この文書は、Nape Gestureの製品完成を実測証跡で判定する正本である。build、test、GUI起動、`.app`生成、個別event投稿のどれか一つだけでは完成としない。製品モデルは[ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md)を正とする。

## button割り当て製品モデル

| 対象 | 選択または処理 | ProductOutput |
| --- | --- | --- |
| button 3 / 4 / 5 | 各buttonで2本指、3本指、4本指GestureClassから1つを選択 | 選択class固有contract |
| button 3 / 4 / 5未押下 | 変換なし | 通常mouse入力をそのまま通す |

- 2 / 3 / 4本指はraw digitizer contact countやgeneric `fingerCount` fieldではなく上位GestureClassである。
- 3 buttonそれぞれで3 classを選択でき、同じclassの重複割り当てを許可する。無効または未割り当ては設けない。
- classごとにevent family、event type、field、phase、companion、motion、axis、符号規則を含むencodingを検査する。3本指と4本指ではencodingの違いを維持し、100%時の`/ 600`基準へ共通の`systemGestureSensitivity`を適用する。
- button別・方向別・application別の感度設定を持たない。GUIで編集できる「システムジェスチャー感度」は25%から200%、既定100%とし、物理button番号ではなく選択された3本指・4本指classへ適用して2本指classには適用しない。
- system-wide投稿だけを使い、AX、対象PID、keyboard shortcut、DriverKit、virtual HID、raw digitizerを使わない。
- 複合HID deviceは`Generic Desktop / Mouse`インターフェースだけを入力監視で開き、同一物理deviceのkeyboard、consumer control、vendor-definedインターフェースを除外する。
- accepted source sampleは1 sampleから1 commandへ変換し、欠落、重複、coalescing、並べ替えを行わない。
- 1 commandから生成する低レベルevent数はclass contractに従う。scroll companion batchをsample重複とは数えない。
- 対象button downで絶対cursor anchorを1回だけ保存し、開始時と各move取得後に同じanchorへwarpする。wheelではwarpせず、全terminalとruntime異常終了でanchorを破棄する。

## 現在位置

button割り当てのCore、runtime、GUI、canonical migrationは同じ署名済みRelease候補へ接続済みである。全9 button-class対応、全27割り当てのcanonical round-trip、重複割り当て、session固定、class基準感度、GUI保存・再起動後復元を機械検証した。固定された既定割り当ての旧binaryでは、Nape Pro実機の3 class合計23 session、generated event 5473件、作成失敗0件、欠落投稿0件、全sessionのsingle terminalを確認し、DockはSpace切替、Mission Control、motion 4のsystem control遷移を受理した。ただし、既定button以外からのNape Pro物理受入は残る。

完成を妨げている最優先課題は、既定button以外から各classを起動するNape Pro物理受入である。その後、background時の実cursor座標、全terminal後の通常mouse復帰、純正trackpad fixtureとの最終比較、異常終了後passthrough、Developer ID署名と公証を完結する。App ExposéはOS設定がオフのため、設定依存の画面結果として未確認である。

## 状態

| 状態 | 意味 |
| --- | --- |
| `未達` | 必須実装または採用可能な証跡がない |
| `統合検証中` | 製品経路はあるが同じbinaryでの機械gateが完結していない |
| `実機待ち` | 機械gateを通過し、物理device操作だけが残る |
| `完了` | 現行配布binaryについて機械証跡と実機証跡がそろった |

## 証跡の共通要件

各runを次の単位で分離する。

```text
artifacts/completion/YYYY-MM-DD/<repo-sha>/<scenario-id>/
```

最低限、次を保存する。

- 実行commandとexit code
- repo SHA、binary SHA-256、bundle identity、macOS version / build
- run UUID、scenario ID、開始・終了時刻、実行主体、TCC状態
- source device、button、保存済み割り当て、期待GestureClass
- source kind、X/Y量、符号、capture order、source timestamp
- generated event type、subtype、field、phase、timestamp、family、session ID
- source commandとgenerated batchの対応
- terminal種別と理由
- passthrough、抑制、生成、drop、retry件数
- fixture schema、ID、SHA-256、contract ID、収録元OS version / build。収録元情報は同梱asset間のprovenanceであり、host OSの許可listには使わない。25F80の正負方向別DockSwipe templateはID `recognized-dockswipe-templates-25F80-v2`、SHA-256 `852c7d0b6e32ced7082ea5c06a65d05971d3868e6a36aaccfd6f422871bc32a6`
- direct post trace、capture、manifest、analyzer reportのidentityとSHA-256

異なるrepo SHA、binary、OS build、scenarioのlogを一つの成功runとして継ぎ合わせない。目視やscreen recordingは補助証跡であり、raw log、manifest、analyzerを代用しない。

## 必須完成ゲート

| ゲート | 完成条件 | 機械証跡 | 物理証跡 | 現在 |
| --- | --- | --- | --- | --- |
| button割り当て | 3 buttonそれぞれで3 classを選択・保存・復元でき、重複を許可し、無効値を持たず、session途中でclassが変わらない | 9通りのbutton-class対応、27通りのcanonical round-trip、既定値、migration、設定変更中session、追加button、GUI selector / dirty / revert / 保存・再起動後復元に合格 | 全classを既定button以外から起動し、重複割り当てを含めNape Proで確認する | `実機待ち` |
| source sample保存 | 各accepted move / wheel sampleがexact timestampとcapture orderを保つ1 commandになり、drop、duplicate、coalesce、reorderがない | 正負、斜め、停止、反転、異間隔、長時間、move / wheel混在、queue圧迫のtest | Nape Pro runtime log 3678 command、欠落投稿0件 | `完了` |
| ProductOutput | 2本指はtype 22 scroll + type 29 companion、3本指はtype 30 DockSwipe motion 1 / 2、4本指はtype 30 DockSwipe motion 4をclass固有contractでsystem-wide投稿し、3本指 / 4本指classだけを`(source / 600) * systemGestureSensitivity`で変換する | 全buttonから各classを選んだfamily mapping、field、phase、単位、共通感度0.25 / 1.0 / 2.0、2本指class非適用、batch、system-wide direct post smoke | 旧固定mappingでNape Proから5473 eventを生成し、DockがSpace、Mission Control、motion 4を受理。任意割り当てと純正trackpadの最終比較は残る | `統合検証中` |
| session terminal | 正常終了と全cancel原因がsingle terminalへ収束し、部分投稿後も順序を保って閉じる | release、cancel、kill switch、runtime stop、sleep、disconnect、TCC喪失、作成 / 投稿失敗、partial batch retry | 正常解放と少なくともkill switch、disconnect、sleepまたはTCC喪失 | `統合検証中` |
| passthrough | 未押下、対象外button、対象外device、session終了後に通常click、move、drag、wheelを変更・抑制・再生成しない | event種別identity、生成0、抑制0、解放境界、failure後復帰 | 23 session後の通常操作復帰を確認。異常終了後の実機復帰は残る | `統合検証中` |
| cursor固定 | button downの絶対座標をsession anchorとして1回だけ保存し、開始時と各move取得後に同じ座標へwarpする。wheelではwarpせず、全terminalでanchorを破棄する | 3 buttonのanchor所有権、正負・斜めmove、wheel非warp、warp失敗、ended / cancelled / timeout / tap中断 / kill switch / stop / 出力失敗のstate testと実座標runner | Nape Gesture以外をforegroundにした署名済みRelease `.app`で高頻度move中の実座標、ちらつき、session後の通常移動復帰を確認する | `統合検証中` |
| fail closed | unsupported build、scroll contract / model / DockSwipe templateのfixture / hash / schema不一致、device不一致、TCC不足、session不整合、event失敗でruntime全体の新規抑制を開始せず、別経路へfallbackしない | failure injection、readiness、明示path不正、partial post、terminal retry、product boundary guard | 現行`.app`の正常経路は誤出力0。異常条件の実機復旧は残る | `統合検証中` |
| 配布 | 日常利用するbinaryの署名、公証、stapler、Gatekeeper、performance、recoveryが合格する | release build、bundle identity、doctor identity、性能report | 配布物の初回起動、TCC導線、再起動、sleep、device抜き差し | `未達` |

全行が`完了`になるまで製品完成としない。`実機待ち`は機能不足を隠す状態ではなく、人間にしか行えない物理操作が残っていることを示す。

## class別低レベル判定

| GestureClass | 合格条件 |
| --- | --- |
| 2本指scroll / swipe | type 22 scrollと必要なtype 29 envelope / companionが、別々のphase fieldとline / fixed / point / gesture motion単位を登録contractの順序、field、timestamp関係で完結する |
| 3本指system swipe | type 30 / classifier 23のDockSwipeがphase fields 132 / 134の1 / 2 / 4 / 8、IOHID motion 1 / 2、`(source delta / 600) * systemGestureSensitivity`の累積progressとXY position、同じ式によるsource velocityの終端XY velocityで完結する |
| 4本指system pinch | type 30 / classifier 23のDockSwipeがphase fields 132 / 134の1 / 2 / 4 / 8、IOHID motion 4、Y優先の`(signed source delta / 600) * systemGestureSensitivity`の累積pinch progress、同じ符号規則と倍率によるsource velocityの終端Z velocityで完結する。application magnification eventを使わない |

共通して、fixture identity、source-to-command 1対1、capture order、exact timestamp、session ID、single terminal、system-wide配送を検査する。class間でevent count、field、単位変換が同一であることは要求しない。

`NavigationSwipe`は物理captureまたはanalyzer上の観測語彙として保持できるが、独立button class、製品capability、ページ移動専用routingの完成根拠にはしない。

## OS / App結果の別判定

| 記録対象 | 判定 |
| --- | --- |
| 入力条件 | button、保存済み割り当て、sessionで選択したGestureClass、source量、方向、速度、session ID |
| 低レベル成立 | class固有contract analyzerとfixture identity |
| OS / App結果 | 前面App、OS設定、画面結果、system-wide受信log |
| terminal | 結果の有無にかかわらずsingle terminalへ収束したか |
| 体感 | 純正trackpadとNape Proの差を同じscenarioで記録 |

縦横scroll、ページ戻る・進む、Spaces、Mission Control、App Expose、DockSwipe motion 4のsystem pinch解釈は受入scenarioである。結果を成立させるため、application別routing、AX、対象PID、keyboard shortcutを追加しない。

## 自動検証

同じworktreeとbinaryに対して最低限、次を成功させる。

```sh
ruby scripts/check-product-model-documentation.rb
ruby scripts/check-fixed-gesture-class-product-model.rb
swift build --scratch-path .build
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture-product-output-tests
sh scripts/check-product-output-boundary.sh
.build/debug/nape-gesture gui-smoke --json --assert
.build/debug/nape-gesture doctor --probe-hid --json --assert-runtime-ready
```

guardはbutton割り当て、重複許可、無効値なし、class基準の共通感度、class固有ProductOutputを検査し、固定button mappingまたは廃止済みgeneric finger-count-onlyモデルを正本へ戻さない。

## 最後の物理作業

1. 27通りの割り当て組み合わせを保存・再起動後復元し、9通りのbutton-class対応をNape Proで開始・終了できることを確認する。
2. 旧Nape Pro 23 sessionと、純正trackpadのscroll、system swipe、pinch fixtureを同じclass別contract reportで最終比較する。
3. kill switch、device切断、sleepまたはTCC喪失後のpassthroughを現行release候補で取得する。
4. App Exposéを有効にする場合だけ、その設定依存の画面結果を低レベルcontractとは別scenarioで記録する。
5. 公開配布物でDeveloper ID署名、公証、stapler、Gatekeeper、初回起動を確認する。

computer-useで代替できない物理device操作だけを人間へ依頼し、それ以外は自動化する。
