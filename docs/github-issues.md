# nape-gesture Issue 管理一覧

この文書は`char5742/nape-gesture`に作成した初期Issueと、その後の分割履歴を保存する非規範の台帳である。現在のIssue状態、依存関係、close判定はGitHub上のIssueと証跡コメントを正とし、製品要件は[ゴール要件](requirements.md)と[ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md)を正とする。
メインスレッドはIssue整理、PRレビュー、マージ判断を担当し、競合しない実装範囲だけをサブエージェントに分割する。

## button割り当て製品モデルと現状

製品の入力モデルは次の3 GestureClassだけを持つ。

| GestureClass | ProductOutput |
| --- | --- |
| `twoFingerScrollSwipe` | type 22 scroll + 必要なtype 29 companion |
| `threeFingerSystemSwipe` | type 30 `DockSwipe` motion 1 / 2 |
| `pinch`（4本指system pinch相当） | type 30 `DockSwipe` motion 4 |
| button 3 / 4 / 5未押下 | 通常mouse入力を変更せず通過 |

button 3 / 4 / 5は各classから1つを選択でき、既定値は順に2 / 3 / 4本指classとする。重複を許可し、無効・未割り当ては設けない。結果別mode、方向別action、application別の有効・無効、感度、割り当て、AX、対象PID配送、keyboard shortcutによる代替経路を製品surfaceまたは製品runtimeへ追加しない。`systemGestureSensitivity`は25%から200%、既定100%で、物理buttonではなく選択された3本指 / 4本指classへ適用する。
「2 / 3 / 4本指」はraw contact数やgeneric `fingerCount` transportではない。各GestureClassが異なるevent type、field、phase、companion、単位変換を使い、最終結果はmacOSまたは前面applicationが解釈する。`NavigationSwipe`と`magnification`を独立class、独立button、製品fallbackとして追加しない。

2026-07-12のbaseline `55eb991` は、結果別の旧mode選択を残していた移行前履歴であり、現在の実装状態を示さない。build成功、`.app`生成、`doctor`、個別event投稿、旧mode単位のtestだけでは製品完成とせず、button割り当て→GestureClass→class固有ProductOutputのend-to-end経路で判定する。

以下の旧Issue名、旧action名、旧mode / family分割、open / close記述は作成時点の履歴としてだけ参照できる。現在の再投入、PR要件、close判定へ流用しない。

## ラベル

- `area:core`
- `area:runtime`
- `area:hid`
- `area:verification`
- `area:ui`
- `area:release`
- `area:docs`
- `type:feature`
- `type:bug`
- `type:research`
- `type:qa`
- `priority:p0`
- `priority:p1`
- `parallel:ready`
- `blocked:external`
- `need:human`

`need:human` は承認待ち、レビュー待ち、確認依頼、人間による判断待ちを表す label ではない。
computer-useでも代替できない純正トラックパッド操作、Nape Pro実機操作、デバイス抜き差し、ユーザー本人しか通せない認証、秘密情報入力などが最後の手段として必要な作業にだけ使う。Issue全体ではなく、代替不能な物理操作または本人操作の範囲を本文に明記する。TCC変更は直前確認を取ったcomputer-useで実行できず、OSが本人操作を要求する場合だけ対象にする。
自動化、computer-use、system-wide event投稿、dry-run、fixtures、ログ解析、Reference Target App、System Behavior Test、権限済み環境での実イベント投稿で代替できる作業は、人間へ依頼する前にそれらで潰し込む。純正trackpad driver output contractの正本取得は、生成eventで代替せず物理trackpad操作を使う。
人間作業が残る場合も、依頼前に手順を最小化し、取得すべきログ、期待値、失敗時の切り分けを Issue に明記する。

## Milestone 1: リポジトリ移行と品質ゲート

### Issue 1: リポジトリ名を nape-gesture として公開できる状態にする

Labels: `area:docs`, `area:release`, `priority:p0`

目的:
`nape-gesture` として始まったローカル成果を、`nape-gesture` リポジトリとして扱える状態にする。

完了条件:

- GitHub 上に `char5742/nape-gesture` が存在する
- 初回コミットが `main` に push 済み
- README の先頭でプロダクトの目的が Nape Pro 向けであることが分かる
- 旧 `Mac Gesture` / `mac-gesture` 系の名前が意図せずユーザー向け名称として残っていない箇所を棚卸し済み
- 旧名を残す箇所は互換性または後続 Issue として理由が明記されている

依存関係:
完了済み。

並列化:
完了済み。

### Issue 2: CI で debug / release build とコアテストを必須化する

Labels: `area:release`, `type:feature`, `priority:p0`, `parallel:ready`

目的:
PR レビューとマージ判断を人手のローカル実行に依存しない状態にする。

完了条件:

- GitHub Actions で `swift build` が成功する
- GitHub Actions で `swift build -c release` が成功する
- `nape-gesture-core-tests` が CI で実行される
- CI 失敗時に PR をマージしない運用が文書化されている
- macOS runner 上で権限依存テストを実行しない範囲が明確

依存関係:
完了済み。

並列化:
完了済み。

### Issue 3: PR レビュー用チェックリストを整備する

Labels: `area:docs`, `type:qa`, `priority:p0`, `parallel:ready`

目的:
メインスレッドがレビューとマージに集中できるよう、レビュー観点を固定する。

完了条件:

- 変更種別ごとの確認項目が `docs/pr-review-checklist.md` にある
- 入力抑制、通常入力通過、生成イベント再入力防止、権限導線、実機検証の観点が含まれる
- どの変更に実機検証が必須かが明記されている
- レビューで不足証跡を要求する基準が明記されている

依存関係:
なし。

並列化:
完了済み。

## Milestone 2: Nape Pro 識別と入力安全性

### Issue 4: Nape Pro の HID 識別ログを取得し、対象 matcher を確定する

Labels: `area:hid`, `type:research`, `priority:p0`, `blocked:external`, `need:human`

目的:
対象デバイスを推測ではなく実機ログで識別する。

完了条件:

- `devices --all --json` の Nape Pro 候補ログが保存されている
- `hid-log` で移動、ホイール、ジェスチャーボタンの usage と値域が分かる
- `analyze-hid-log` の出力から設定例を作成済み
- `requireMatchingTargetDevice: true` で `matchedTargetDeviceCount >= 1` になる
- Nape Pro 未接続時に安全停止することを確認済み

依存関係:
実機 Nape Pro と入力監視権限。

並列化:
logger起動、ready確認、保存、解析はエージェントが先に完了し、Nape Proの物理操作だけを人間作業として分離する。

### Issue 5: イベントタップ入力と HID 対象デバイスの紐づけを厳密化する

Labels: `area:runtime`, `area:hid`, `type:feature`, `priority:p0`

目的:
対象デバイスの直近入力だけをbutton割り当て→GestureClass変換へ渡し、他のマウスやトラックパッド入力を巻き込まない。

完了条件:

- 対象 HID 入力の直近時刻とイベントタップ入力の association window が設定可能
- button 3 / 4 / 5を区別し、押下時のcanonical割り当てをsession中保持する
- 同一押下中の連続mouse event量が同一GestureClassとsession IDへ順序を保って入る
- button解放で対応sessionを終端し、未押下時は遅延なく通常mouse入力へ戻る
- 対象外デバイスのクリック、ドラッグ、ホイールを改変しないテストがある
- Nape Pro 実機ログで association window の初期値が妥当化されている
- canonical button割り当て以外の結果別mode、方向別action、application別設定でGestureClassを変更できない

依存関係:
Issue 4。

並列化:
コア状態機械のテスト拡張は Issue 4 と一部並列可能。

### Issue 6: ジェスチャー成立後の元入力抑制を実機ログで検証する

Labels: `area:runtime`, `area:verification`, `type:qa`, `priority:p0`

目的:
button 3 / 4 / 5押下中に変換対象となる元入力だけを抑制し、未押下時の通常mouse入力を変更しないことを確認する。

完了条件:

- `Reference Target App` でbutton 3 / 4 / 5ごとの変換中の元入力漏れを記録できる
- 押下開始からrelease / cancelまで、変換対象の元イベントと生成trackpad入力を対応づけられる
- 変換中の元イベントはAppKitへ通常mouse入力として重複配送されない
- button 3 / 4 / 5未押下時は通常クリック、通常ドラッグ、通常移動、通常ホイールを変更せず通す
- button解放直後の次の通常mouse入力を欠落、遅延、再変換しない
- 失敗時のログ例と修正方針が文書化されている

依存関係:
Issue 4、Issue 5。

並列化:
検証手順の整備は実装と並列可能。

## Milestone 3: トラックパッド級ジェスチャー生成

### Issue 7: スクロールと慣性フェーズの生成ログを純正入力と比較可能にする

Labels: `area:core`, `area:verification`, `type:feature`, `priority:p0`

目的:
通常スクロールの `scrollPhase` と慣性の `momentumPhase` を混同せず、純正トラックパッドとの差分を説明できるようにする。

完了条件:

- 通常スクロールの `began` / `changed` / `ended` は `scrollPhase` にだけ出る
- 慣性中と慣性終了は `momentumPhase` に出る
- `generate-scroll --dry-run --log-json` が同じ規則で出力する
- `system-test run --dry-run --log-json` が同じ規則で出力する
- コアテストでフェーズ分離が検証されている

依存関係:
なし。

並列化:
移行前の公開scroll fieldと単一`momentum`表現という診断上の狭い範囲では完了済み。これは固定button→GestureClass変換または製品runtimeの完了証跡ではない。この依存関係と後続Issue番号は履歴であり、現行判定には使わない。

### Issue 8: 純正trackpadとNape Proからclass固有event contractを再導出する

Labels: `area:core`, `area:verification`, `type:research`, `priority:p1`

目的:
純正trackpadとNape Proの実機ログを正本として、共通source sample保存契約とGestureClassごとのversioned出力contractを再導出する。

完了条件:

- 純正trackpadの3 GestureClassによる連続入力ログと、Nape Proのsource mouse event logを同じrun identityで対応付けられる
- X/Y量、符号、sample順、timestamp間隔、単位を対応付けられる
- OS buildごとにclass固有のevent type、field、phase、companion、単位変換、許容誤差、fixture ID、SHA-256を固定している
- button 3 / 4 / 5へ同一source fixtureを与え、変換前の量、符号、順序、timestampを保持しながらclass固有encodingの差を検証する
- 3本指 / 4本指class共通の`systemGestureSensitivity`以外に、button別・方向別・application別の感度、加速度、dead zone、threshold、clamp、結果別係数を持たない
- 複数source sampleをcoalesceせず、各sampleと生成eventの対応を回帰testで固定している

依存関係:
Issue #4、#125、#129、#148。

並列化:
物理capture、単位推定、analyzer、property testは所有fileを分けて進められる。

### Issue 9: `threeFingerSystemSwipe` / `pinch`のmacOS受入結果を確認する

Labels: `area:verification`, `type:qa`, `priority:p0`, `blocked:external`, `need:human`

目的:
mouse button 4 / 5からsystem-wideに送った`threeFingerSystemSwipe` / `pinch`出力を、macOSが現在の設定でどの標準gesture結果として解釈するか確認する。class固有contractとOS結果は別に判定する。

完了条件:

- 同じsigned app / binaryで3本指と4本指を別々に確認している
- Space移動、Mission Control、App Exposeなど、同じOS設定で純正入力と生成入力から実際に起きた結果をscenario別に記録している
- X/Y入力、途中反転、release、cancel、kill switch、runtime stop、sleepへの画面transition追従とstuckの有無を記録している
- 前面applicationを変えても生成contractを変更していない
- runtime log、生成event log、画面capture、OS設定、Nape Pro物理受入を別証跡として保存している
- `DockSwipe`などの観測語彙や画面結果を、buttonのユーザーmodeまたは低レベルcontractの合格根拠にしていない
- 結果別mode、方向別action、application別分岐、AX、対象PID配送、keyboard shortcut fallbackがない

依存関係:
Issue 125、Issue 126、Issue 127、Issue 148。

並列化:
computer-useによる画面確認とruntime証跡を先行し、最後のNape Pro物理操作だけを人間作業にする。

### Issue 10: `twoFingerScrollSwipe`のOS / App受入結果を確認する

Labels: `area:verification`, `type:qa`, `priority:p0`, `blocked:external`, `need:human`

目的:
mouse button 3からsystem-wideに送った`twoFingerScrollSwipe`出力を、macOSと前面applicationがどの標準gesture結果として解釈するか確認する。class固有contractとOS/App結果は別に判定する。

完了条件:

- Finder、Safari、Web content、nested targetで縦、横、斜め、方向反転の結果を確認している
- ページ戻る/進むなど、2本指入力から実際に起きた結果をOS/App設定とともに記録している
- X/Y入力、release、cancel、momentumが同じ連続sessionとして完結している
- 前面applicationを変えても同じbinaryと入力contractを使っている
- `scroll`と`NavigationSwipe`は低レベルevent familyまたは観測語彙として追跡し、独立mode、button割り当て、製品runtime capability、ページ移動の合格条件にしていない
- runtime log、生成event log、画面capture、OS/App設定、Nape Pro物理受入を別証跡として保存している
- 画面結果の成功を低レベルcontractの合格に使わず、期待と異なる結果のために個別routingを追加していない
- 結果別mode、方向別action、application別分岐、shortcut、forced horizontal scroll、対象PID配送、AX fallbackがない

依存関係:
Issue 119、Issue 125、Issue 129、Issue 148。

並列化:
この並列化メモは作成時点の履歴である。撤回済みのIssue 146を現在の依存先または未完了作業にしない。

### Issue 146（非規範履歴）: generic finger-count前提でmagnificationを再評価する

Labels: `area:verification`, `type:qa`, `priority:p0`, `blocked:external`, `need:human`

このIssueの「一つのgeneric finger-count入力からmagnificationを導出する」という前提は撤回済みであり、現在の要件や未完了作業ではない。button 5は固定`pinch` classからtype 30 `DockSwipe` motion 4を生成する。application magnification event、raw digitizer contact、専用mode、application別routingへ置き換えない。

### Issue 148（移行履歴）: button 3 / 4 / 5を固定GestureClassへ直結する

Labels: `area:core`, `area:runtime`, `area:ui`, `area:docs`, `type:bug`, `priority:p0`, `parallel:ready`

目的:
結果別modeとユーザーroutingを製品経路から除去し、設定、GUI、recognizer、session coordinator、class固有adapter、migration、doctor、fixture、testを固定button→GestureClassモデルへ一貫して移行する。

完了条件:

- buttonごとの結果別mode selectorを設定schemaとGUIから削除している
- 旧mode、旧感度、加速度、dead zone、momentum tuningをcanonical configから原子的に除去し、旧感度を新しい共通感度へ移行せず、値がなければ1.0を補い、対象deviceと安全停止条件を保持している
- runtime commandがGestureClassと連続mouse event量のX/Y、符号、反転、順序、timestampを保持し、複数source sampleをcoalesceしていない
- 3つのclass固有versioned contractを使い、3本指 / 4本指class共通の`systemGestureSensitivity`以外にユーザー調整またはapplication別の係数を持たない
- 旧mode→family routing、優勢軸固定、直交成分破棄を削除し、class固有のprogress / velocity / phase変換だけを登録contractへ照合している
- 3 GestureClassの低レベルcontractを純正trackpad計測から導出している
- release、cancel、kill switch、sleep、runtime stop、投稿失敗で各sessionを一度だけterminalへ収束させている
- button未押下時と対象外buttonの通常mouse入力を変更、抑制、再配送していない
- OS/App結果と低レベルcontractを別gateで検証している
- Core / product / GUI / migration / boundary testとCIを更新している
- `check-product-model-documentation.rb`と`check-fixed-gesture-class-product-model.rb`が成功している
- signed appでNape Proのbutton 3 / 4 / 5物理受入を完了している

並列化:
所有ファイルを分離して移行した当時の記録である。現在のworkerはIssue #148の段階表ではなく、現行GestureClass contractと明示された所有範囲に従う。

### Issue 117（追跡履歴）: button別GestureClassの完成を層別に追跡する

Labels: `area:runtime`, `area:hid`, `area:verification`, `type:feature`, `priority:p0`

目的:
button 3 / 4 / 5押下中の連続mouse event量を、それぞれ`twoFingerScrollSwipe`、`threeFingerSystemSwipe`、`pinch`のclass固有ProductOutputへ変換し、未押下時は通常mouse入力を変更せず通す。Nape GestureはOS/App結果を選ばずsystem-wideへ投稿する。

完了条件:
- button 3 / 4 / 5のcanonical割り当てと3つのGestureClassが設定、UI、migration、runtime、出力、test、文書で一致する
- button 3 / 4 / 5未押下時の通常mouse入力が変更されない
- 結果別mode、方向別action、application別設定、AX、対象PID配送、shortcut fallbackが製品経路にない
- `scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`の観測または投稿だけを製品経路の完成と数えていない
- 入力取得、class固有contract、共通session、runtime統合、OS/App結果、物理受入、releaseの境界ごとに証跡がある
- Issue 117単体の集約記述、旧modeテスト、family capability、`.app`生成で子Issueの証跡を代替していない
- button割り当て→GestureClass→class固有ProductOutputのend-to-end経路と各受入境界が現行binaryで成立している

履歴上のSub-issues（状態と依存関係はGitHubを正とする）:

| Issue | 役割 | `need:human` |
| --- | --- | --- |
| #148 | 設定、GUI、recognizer、session、event builder、migration、doctor、fixture、testsの全面修正 | なし |
| #118 | 既存logger基盤。GestureClassとclass固有event contractを別項目として再検証 | なし |
| #125 | 純正trackpadの3 GestureClass物理操作によるevent contract取得 | 純正trackpad物理操作だけあり |
| #119 / #148 | `twoFingerScrollSwipe`経路 | なし |
| #126 | `threeFingerSystemSwipe`経路 | なし |
| #127 | `pinch`経路 | なし |
| #122 | macOS version compatibility adapter | なし |
| #124 / #148 | 結果別mode / 方向別action / application別設定 / AX / 対象PID配送 / shortcut fallback禁止guard | なし |
| #128 / #148 | 既存共通output session / monotonic clockへGestureClassを保持 | なし |
| #129 | raw event analyzer / 3 GestureClassのfixture比較 | なし |
| #130 / #131 / #148 | 固定mappingのdaemon統合、未押下pass-through、fail closed、診断分離 | なし |
| #132 | 3 GestureClassの性能schema / baseline | なし |
| #10 | `twoFingerScrollSwipe`のOS/App・物理受入 | Nape Pro /純正trackpad物理操作だけあり |
| #9 | `threeFingerSystemSwipe` / `pinch`のmacOS・物理受入 | Nape Pro /純正trackpad物理操作だけあり |
| #146 | generic finger-count前提を撤回済みの履歴 | なし |

#118、#119、#124、#128、#130、#131の既存closeは各Issueの旧スコープに対する履歴であり、固定GestureClass製品全体の完成を表さない。現在の完成判定には現行binaryとclass固有contractの証跡だけを使う。

設計正本:
[ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md)。旧adapter、診断分離、共通sessionの成果は、ADR-0049との適合と現行end-to-end到達性を再検証できた範囲だけを継承する。

## Milestone 4: 常駐アプリ品質

### Issue 11: 権限導線と runtimeIdentity 表示を `.app` 利用前提で固める

Labels: `area:runtime`, `area:ui`, `type:feature`, `priority:p0`

目的:
ユーザーがどの `.app` または実行ファイルに権限を付けるべきか迷わない状態にする。

完了条件:

- `doctor --json` に実利用対象の bundle path、bundle ID、executable path が出る
- `.app` が Dock に表示される通常 GUI アプリとして起動する
- `.app` 起動時に設定ウィンドウが前面に出る
- Dock から再度開いたとき、表示中ウィンドウがなければ設定ウィンドウが再表示される
- メニューバーのsystem symbolによる常駐 UI が維持される
- 設定UIでは3 buttonごとのGestureClassだけを選択でき、結果別mode、方向別action、application別設定を持たない
- 常駐 UI の権限確認に同じ情報が出る
- アクセシビリティ未許可、入力監視未許可の復旧導線が別々に出る
- 権限変更後の再起動または自動再試行が文書化されている
- `.app` での `doctor --probe-hid --json` 証跡がある

依存関係:
Issue 1。

並列化:
UI 表示と CLI doctor は分担可能。

### Issue 74: GUI から macOS の権限設定を直接開けるようにする

Labels: `area:runtime`, `area:ui`, `type:feature`, `priority:p0`

目的:
アクセシビリティと入力監視の System Settings 画面を GUI から直接開けるようにし、人間作業を最後の許可操作だけへ縮小する。

完了条件:

- 常駐 UI または権限確認ダイアログからアクセシビリティ設定を開ける
- 常駐 UI または権限確認ダイアログから入力監視設定を開ける
- アクセシビリティと入力監視の状態表示、許可対象、再起動が必要な旨を同じ表示モデルで説明できる
- 表示文言と System Settings URL を core test で固定する
- 方針を ADR と検証文書に残す

依存関係:
Issue 11。

並列化:
core presenter、GUI 接続、docs/ADR 更新は分担可能。

### Issue 12: キルスイッチと暴走停止を回帰テスト可能にする

Labels: `area:runtime`, `type:feature`, `priority:p0`

目的:
誤爆時に即座に停止でき、再開条件が明確な状態にする。

完了条件:

- `Control + Option + Command + G` が常駐中に認識される
- キルスイッチ自体が前面アプリへ漏れない
- 発火後はジェスチャー生成と慣性が停止する
- 再開は UI の停止/開始またはプロセス再起動に限定される
- ログまたはテストで一方向停止が確認できる

依存関係:
アクセシビリティ権限。

並列化:
Runtime 実装と検証手順整備を分担可能。

### Issue 13: スリープ復帰、デバイス抜き差し、権限変更後の復旧を実測する

Labels: `area:runtime`, `area:verification`, `type:qa`, `priority:p1`, `blocked:external`

目的:
日常利用で止まったままにならない常駐品質を確認する。

完了条件:

- スリープ復帰後に対象デバイスと権限状態を再確認する
- 対象デバイス抜去時に安全停止し、再接続後に復旧する
- 権限が失われた場合に停止し、復旧導線を出す
- 常駐 UI が自動再試行状態を表示する
- 実機操作ログと `doctor` 出力が保存されている

依存関係:
Issue 4、Issue 11。

並列化:
実機検証担当が独立して進められる。

### Issue 14: 入力遅延と CPU 使用率の測定基準を作る

Labels: `area:runtime`, `area:verification`, `type:qa`, `priority:p1`, `parallel:ready`

目的:
「体感できない水準」を、常駐アプリとして判断できる証跡にする。

完了条件:

- 純粋ロジックの `benchmark` 結果を保存する
- イベントタップから生成投稿までの測定方針がある
- 連続操作中の CPU 使用率を測定する手順がある
- 閾値を超えた場合に調整する項目が明記されている
- ベンチマーク結果を PR レビューで確認する基準がある

依存関係:
なし。

並列化:
実装作業と並列可能。

## Milestone 5: 配布と完成判定

### Issue 15: `.app` バンドル、署名、公証、ライセンス同梱を整える

Labels: `area:release`, `type:feature`, `priority:p1`

目的:
日常利用できる配布物として扱える状態にする。

完了条件:

- release build が成功する
- `.app` バンドルが生成される
- `verify-bundle` が成功する
- `.app` が Dock に表示される通常 GUI アプリとして起動し、起動時に設定ウィンドウを開く
- `CFBundleIdentifier`、`CFBundleExecutable`、`CFBundleName`、`CFBundleDisplayName`、`LSUIElement=false` の exact check が成功する
- `LICENSE` と `THIRD_PARTY_NOTICES.md` が同梱され、バンドル内ファイルと原本が `cmp` で一致する
- `sh scripts/check-provenance.sh` が成功する
- 署名と公証の方針が決まっている
- 配布前の権限付与手順が README にある

依存関係:
Issue 1、Issue 2。

並列化:
署名/公証調査とバンドル検証は分担可能。

### Issue 16: 完成判定チェックリストを実測証跡で埋める

Labels: `area:verification`, `area:docs`, `type:qa`, `priority:p0`

目的:
「動いた気がする」ではなく、完成要件を証跡で満たした状態にする。

完了条件:

- `docs/verification.md` の完成判定チェックがすべて証跡リンク付き
- 純正trackpad、Nape Pro、生成eventを3 GestureClassごとに比較したlogがある
- button 3 / 4 / 5から各class固有ProductOutputまでを同じsigned app / binaryで実測済み
- button 3 / 4 / 5未押下時の通常mouse pass-throughを実測済み
- class固有event contractとmacOS / application結果を分離して実測済み
- button 5がtype 30 `DockSwipe` motion 4を生成し、application magnificationや専用pinch modeへ置き換わっていない
- 結果別mode、方向別action、application別設定、AX、対象PID配送、shortcut fallbackが製品surfaceとruntimeにないことを検査済み
- `.app` の通常 GUI 起動、Dock 表示、起動時設定ウィンドウ、メニューバー常駐 UI の証跡がある
- 通常クリック、通常ドラッグ、通常ホイールが壊れていない確認がある
- 既知の失敗条件と回避策が README または docs に反映されている

依存関係:
この一覧は作成時点の履歴である。現在の依存関係はGitHubを正とし、撤回済みのIssue 146を完成条件にしない。

並列化:
証跡収集は複数担当で並列可能だが、最終判定はメインスレッドで行う。
