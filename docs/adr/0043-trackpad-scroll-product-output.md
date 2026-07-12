# ADR-0043: 25F80 trackpad scrollを製品出力として構成する

- 状態: 採択
- 日付: 2026-07-12

## 背景

[ADR-0042](0042-versioned-scroll-momentum-contract-comparison.md)では、macOS 26.5.1（25F80）で自前計測した純正trackpadのscroll / momentum / companion系列を、登録済みSHA-256とOS identityを持つ比較contractへ固定した。しかし、比較contractだけでは、gesture deltaからline / fixed-point / point deltaを生成する変換、製品runtimeのsession管理、system-wide投稿、投稿経路の証跡を決められない。

Issue #119では、縦横scrollを同じadapterで扱い、scroll inputとmomentumを最後まで閉じる製品出力が必要である。一方、未計測の値や別OS buildへの推測、対象PID配送、AX、application別分岐、keyboard shortcutへのfallbackは許容できない。

また、[ADR-0039](0039-strict-trackpad-event-analysis-and-capture-manifest.md)は、capture logのraw target process fieldが非0なら対象PID投稿と判定する方針を記載していた。その後の実測と回帰テストにより、system-wide投稿後のeventではWindowServerが前面の実配送先をraw field 39 / 40へ付与することを確認した。投稿後captureのfield値だけから、投稿APIがPIDを明示したかどうかは逆算できない。

## 決定

### 25F80 output model

- 自前計測した4系列のanalyzer windowでは、scrollとcompanionを986 pair対応付けた。そのうちterminal 19 pairを係数fitから除外し、残る967 pairをX軸・Y軸それぞれのmodel sampleとする。
- gesture deltaを`g`、生成する連続値を`d`として、line / fixed-point / pointごと、かつX / Y軸ごとに、切片0のodd quadratic `d = a*g + b*g*abs(g)`を最小二乗で導出する。軸差を平均化せず、次の25F80係数をmodel fixtureへ固定する。

| 軸 | 出力 | `a` | `b` |
| --- | --- | ---: | ---: |
| X | line | 0.027153379676470378 | 0.0005139088775698634 |
| X | fixed-point | 0.027354705543959693 | 0.0005445077231600865 |
| X | point | 0.3029054468831232 | 0.0052276557862058984 |
| Y | line | 0.022231527900124576 | 0.0004970101926676257 |
| Y | fixed-point | 0.027469676804179777 | 0.0004945992512013199 |
| Y | point | 0.2912417154163434 | 0.004863123350457081 |

- tracked sample fixture `scroll-output-model-samples.json`の967 pairから、`derive-trackpad-scroll-output-model.rb`でmodelを再導出する。CIは生成bytesをtracked `scroll-output-model.json`と`cmp`し、係数の手編集や導出driftを拒否する。
- runtimeはsample fixtureを読まない。登録済みscroll contractと導出済みmodelだけを読み、contract fixture ID / SHA-256 / schema / contract ID / OS version / build、model fixture ID / SHA-256 / schema / model ID / status / source contract identity / 軸別sample countがすべて一致した場合だけ`scroll`をsupportedにする。
- `NAPE_GESTURE_TRACKPAD_CONTRACT`または`NAPE_GESTURE_TRACKPAD_OUTPUT_MODEL`が存在する場合は、指定pathだけを読む。空、読取不能、空file、不正bytesの明示pathでは起動不可とし、bundle resourceやrepository fixtureへ黙ってfallbackしない。環境変数が未指定の場合だけ、bundle、repositoryの順に探索する。
- 25F80の登録SHA-256は、contractが`8e2a1841ef23a47fcb274c1c8e7c7c39be43e8ab7c8792caf2cd874242a61294`、tracked sampleが`d88d513c01e0f0360716d697fc41bb7c7913b5f2dc45825fb817713000da1381`、output modelが`c947b3adfa68927b514f7af65464a2ba79100815cf21d471018dbafc2e8beef4`である。bytes、version、OS identity、source identityのどれかが違う場合はeventを投稿せずfail closedにする。

### Event系列

- inputの`began` / `changed` / `ended`は、同一timestampの`type 22 scroll -> type 29 envelope -> type 29 companion`を1 batchとして生成する。envelopeはraw 110=`0`、companionはraw 110=`6`とし、scrollとcompanionのphaseを一致させる。
- input中はscroll phaseをraw 99の`1 / 2 / 4`、momentum phaseを`0`とする。実機contractで独立したcancel raw値を確認していないため、`cancelled`と明示cancellationは確認済みのscroll endedへ収束させ、未観測値を作らない。
- momentumは`type 22`だけを生成し、scroll phaseを`0`、momentum phaseをraw 123の`1 / 2 / 3`とする。scroll ended後にだけmomentumを開始する。
- scroll ended、input active中のcancel、momentum ended、momentum active中のcancelでは、line XYZを整数`0`、fixed-point / point XYZをbit patternも含む`+0.0`にする。terminalへ入力payloadの残存deltaを流用しない。
- 縦scrollと横scrollは同じmodel、builder、session adapterを通す。横scrollはcoordinatorでX payloadへ正規化し、momentum中もactive actionと軸を維持する。
- eventは`.cghidEventTap`へsystem-wide投稿する。製品adapterは対象PID、AX element、application別配送、keyboard shortcutを選ばない。

### Session、慣性、明示cancel

- daemonは`MomentumEngine`とtimerを所有し、input ended時にmomentumを開始するか`complete`にするかを明示する。新しいactivation button入力、kill switch、runtime stop、出力失敗ではtimerを停止し、coordinatorへ理由付きcancelを渡す。
- coordinatorはactive action、session ID、0始まりで欠落のないcapture order、起動後timestamp、input / momentum continuationを管理する。momentum commandはactive sessionのactionを引き継ぎ、別actionや順序不正を`invalidSession`として拒否する。
- adapterも同じsession state machineで受信eventを再検証する。input batchは3 eventを全件作成・検証してから投稿を始め、一部を作れないbatchを1件も投稿しない。
- 既存session中の不正frame、event作成失敗、投稿失敗では、未完了sessionを破棄せず同じcapture orderの明示cancelを受け付ける。cancel batch自体が失敗した場合も、terminal投稿へ成功するまではcoordinatorとadapterのsessionを保持し、安全停止処理から再試行できるようにする。
- batchの一部だけが投稿済みの場合は、未投稿offsetと予約済み`postIndex`を保持する。同じsource eventの再送または明示cancelだけを受け付け、解消前の別sessionを拒否することで、direct post traceの番号と実投稿順を逆転させない。
- input activeのcancelはscroll ended + envelope + companion、momentum activeのcancelはmomentum endedを生成する。scroll ended後の`awaitingMomentum`をcancelした場合は、重複terminalを生成しない。
- runtimeはdaemon起動ごとのgenerationをterminal callbackへ固定する。正常停止でgenerationを無効化し、旧daemonから遅延到着したcallbackが再起動後のdaemonを停止することを防ぐ。停止失敗時はdaemonとgenerationを保持して同じsessionのcancelを再試行する。

### 投稿経路の証跡とfield 39 / 40の訂正

- adapterはevent構築時にraw field 39 / 40を`0`へ設定し、post operationへ渡す直前のvalidationでも両方が`0`であることを必須にする。これは「製品側がraw配送先を埋めていない」ことの投稿前検査である。
- post operation成功直後に、adapter自身がschema 2 direct post traceへ、連続`postIndex`、session、family、timestamp、event type、event kind、`delivery: systemWide`、投稿前field 39 / 40、captureと共通のrun UUID / scenario / repo SHA、実行binary SHAを記録する。traceへdestination PID、AX role、key codeを持ち込まない。
- `finalize-product-output-provenance.rb`はdirect post traceをcapture log / manifestと、run UUID、scenario、repo / binary identity、log / trace SHA-256、件数、capture index、timestamp、event type、session、familyで照合してprovenanceを確定する。analyzerはcapture時の生成marker、actual event type、provenanceのsystem-wide配送と禁止metadataを検査する。
- `check-product-output-boundary.sh`は製品targetとdaemon / executorを走査し、PID投稿、AX、shortcut、診断posterの逆流を拒否する。配送経路の判定は、投稿前field検査、direct post trace、captureとのprovenance照合、source boundary guardを組み合わせる。
- system-wide投稿後のcaptureでraw field 39 / 40が非0でも、WindowServerが前面配送先を付与した結果として受理する。この非0だけを明示的PID投稿の証拠にしない。この点について、ADR-0039の「raw target process fieldが非0なら失敗」という記述を本ADRで置き換える。

### 対応範囲

- 現在のproduct capabilityがsupportedにできるevent familyは`scroll`だけである。
- `dockSwipe`、`navigationSwipe`、`magnification`は未実装であり、placeholderや別経路へfallbackしない。bindingが未対応familyを要求する場合、doctorは`outputContract.missingFamilies`を返し、daemonはevent tapと入力抑制を開始しない。
- したがって、Issue #119のscroll adapter実装を、Nape Gesture全体、Spaces / Mission Control、page navigation、zoom、配布の完成とは表現しない。

## 理由

- 967 pairの自前計測から軸別に導出すれば、単一倍率では失われる軸差、低速域、高速域の非線形性を、由来を追跡できる形で保持できる。
- odd quadraticは符号反転時の対称性と切片0を構造として持ち、ゼロ入力を意図しない非ゼロ出力へ変換しない。
- sessionとmomentumをdaemon / coordinator / adapterの責務として分離すると、入力停止理由にかかわらず同じterminal規則へ収束できる。
- system-wide投稿を唯一の製品経路にすると、前面applicationやnested scroll targetの選択をmacOSへ委ね、application固有分岐を製品へ持ち込まずに済む。
- field 39 / 40の投稿前値と投稿後値を分けることで、OSが解決した実配送先を、製品が明示した宛先と誤認しない。

## 代替案

- gesture deltaへ固定倍率を掛けてpixel scrollだけを送る案は、line / fixed-point / point / gesture deltaの関係とcompanion系列を再現できないため採用しない。
- X / Yを同一係数へ平均化する案は、自前計測で確認した軸差を消すため採用しない。
- 対象PID投稿、AX scrollbar、application別分岐、keyboard shortcutで配送やgestureを補う案は、製品意味論と証跡経路が分岐するため採用しない。
- capture後のraw field 39 / 40を常に投稿APIの宛先指定とみなす案は、WindowServerによる配送先付与を誤検出するため採用しない。
- 未実装familyを空event、診断event、推測したprivate fieldでsupportedに見せる案は、未知contractで誤動作するため採用しない。

## 検証

次をローカルとCIの機械gateにする。

```sh
swift build --scratch-path .build
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture-product-output-tests
ruby scripts/derive-trackpad-scroll-output-model.rb | cmp - Fixtures/trackpad-contract/25F80/scroll-output-model.json
ruby scripts/test-finalize-product-output-provenance.rb
sh scripts/check-product-output-boundary.sh
```

product output testsは、縦横delta、type 22 / 29順序、began / changed / ended、momentum began / continued / ended、`+0` terminal、cancel stateと失敗後の再試行、投稿前raw field 39 / 40=`0`、direct post traceの`systemWide`、fixture / model改変時のfail closed、不正な明示環境変数pathからbundle / repositoryへfallbackしないこと、session不正、batch作成・投稿失敗を検査する。

core testsとprovenance finalizer testsは、system-wide投稿後のcaptureでWindowServer解決済みraw field 39 / 40が非0でも受理し、trace側の`targetPID`、destination PID、AX、shortcut metadata、生成marker欠落、log / trace不一致を拒否する。

runtime evidenceでは、`trackpad-event-log --evidence-kind generatedProduct --only-generated`、`system-test run --scenario vertical-scroll|horizontal-scroll --product-trace-out`、provenance finalizer、`analyze-trackpad-event-log --contract`を一続きに実行する。System Behavior Testも製品runtimeと同じsession coordinatorを通し、途中失敗時はtraceを書き出さず、active sessionのterminal cancellationを再試行する。Safari、Finder、Web content、nested scroll targetで同じbinaryとsystem-wide系列を使い、前面配送、phase完結、stuckなしを別々に保存する。

## 限界

- 登録済み実行contractはmacOS 26.5.1（25F80）だけである。OS version / buildが変わった場合は、同じmodelを推測適用せず、新しい自前capture、fixture、SHA登録、差分検証が必要である。
- 967 pairの係数は観測範囲内の近似modelであり、純正driver内部実装の同定ではない。model誤差と実機の体感差分は別に評価する。
- serialized eventを含むraw capture原本は、privacyと容量の境界により公開Gitへ入れない。公開fresh checkoutで再現できる範囲は、source log SHAと抽出条件を持つtracked 967 pairからmodel bytesを再導出するところまでとする。raw原本からtracked sampleを再抽出する検証は、[ADR-0041](0041-physical-capture-readiness-and-fixture-privacy.md)に従うlocal completion evidenceとして別に保持する。
- scroll inputの独立cancel raw値は未確認である。現在は明示cancelを確認済みended系列へ収束させる。
- direct post traceとprovenanceは投稿経路を再現可能に照合する証跡であり、暗号学的な実行証明ではない。source boundary guardとcapture evidenceを省略しない。
- `dockSwipe`、`navigationSwipe`、`magnification`、Nape Pro実機比較、全applicationの画面挙動、署名・公証は本ADRの完成範囲外である。

## 影響

- 25F80では、scrollだけを独立したproduct familyとして実装・検証できる。
- 未対応familyを含むbindingは起動前に可視化され、安全に停止する。
- generatedProduct captureでraw field 39 / 40が非0でも誤拒否せず、投稿前検査とprovenanceで明示配送経路を判定できる。
- tracked sample、導出script、model fixture、runtime registry、bundle resourceのidentityを一続きにレビューできる。

## 関連

- [ADR-0036: trackpad driver上位出力eventを再現する](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0037: 製品gesture出力と診断event出力を分離する](0037-separate-product-and-diagnostic-event-output.md)
- [ADR-0038: trackpad出力sessionとmonotonic clockを共通化する](0038-trackpad-output-session-and-monotonic-clock.md)
- [ADR-0039: trackpad eventログを厳格解析しcapture manifestへ固定する](0039-strict-trackpad-event-analysis-and-capture-manifest.md)
- [ADR-0042: 25F80 scroll / momentum契約を独立fixtureで比較する](0042-versioned-scroll-momentum-contract-comparison.md)
- [検証手順](../verification.md)
- [PRレビューチェックリスト](../pr-review-checklist.md)
