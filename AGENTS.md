# AGENTS.md

このリポジトリで作業するエージェントは、次の方針を守る。

## 基本姿勢

- ユーザーに見える返答、通常コメント、doc comment、Issue / PR コメントは日本語で書く。ログなど英語が自然な出力はそのまま扱ってよい。
- 問題が起きたら後回しにせず、根本原因から対応する。
- テスト失敗、CI 失敗、検証不足を見過ごさない。完了扱いにする前に再現可能な証跡を残す。
- `chmod` は使わない。読み取り専用ファイルは編集しない。
- Issue / PR コメント投稿、PR review、reply など GitHub 上の書き込みは、可能な限り `gh api` または GitHub app / MCP を使う。
- 並行作業中は着手前と編集後に `git status` と対象差分を確認する。指定された所有範囲だけを編集し、他者の変更を取り消したり上書きしたりしない。

## 製品モデルの正本

製品挙動については、この節、[README](README.md)、[ゴール要件](docs/requirements.md)、[ADR-0049](docs/adr/0049-fixed-button-to-gesture-class-input.md)が示す固定モデルを正本とする。実装、設定、テスト、ADR、検証文書をすべてこのモデルへ統一する。結果別modeやfamily別製品経路を正当化する誤ったADR、本文、図、リンクは現行treeから削除し、並存させない。

| mouse入力 | 固定GestureClass |
| --- | --- |
| button 3押下中 | 2本指scroll / swipe相当 |
| button 4押下中 | 3本指system swipe相当 |
| button 5押下中 | 4本指system pinch相当 |
| button 3 / 4 / 5のいずれも未押下 | 通常mouse入力をそのまま通過 |

- buttonとGestureClassの対応は固定であり、ユーザー設定、既定値、application、移動方向、過去の設定値によって変えない。
- 押下中の連続mouse event量をclass固有の上位event contractへ変換する。途中の方向転換を別action、別mode、別sessionとして再解釈しない。
- 有効なsource sampleは欠落、重複、coalescing、並べ替えをせず、X/Y量、符号、timestampを個別に保持する。class固有contractで実測した単位変換以外に感度、加速度、dead zone、threshold、clampを適用しない。
- 2 / 3 / 4本指はraw digitizer contact countやgeneric `fingerCount` transportではなく、上位GestureClassのユーザー向け説明である。class間でevent type、field、phase、companion、単位変換を同一にしない。
- button解放時は対応するtrackpad入力sessionを正しく終了し、通常mouse passthroughへ確実に戻す。
- button未押下時の通常クリック、移動、ドラッグ、wheel、その他の通常mouse入力を、gesture変換のために変更、抑制、再配送しない。

## レイヤー境界

- ユーザーが選ぶ結果別modeは存在しない。button 3 / 4 / 5を結果名、機能名、event family名へ割り当てる設定を追加しない。
- 上下左右などの方向別action、application別の有効・無効、感度、割り当て設定を製品surfaceへ追加しない。
- `scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`は、compatibility adapter、fixture、analyzer、runtime証跡で使う低レベルevent familyまたは観測語彙である。ユーザーmode、button割り当て、完成した結果機能として表示しない。
- 実際のscroll、navigation、system gesture、拡大縮小などの結果は、連続trackpad入力を受け取ったmacOSまたは前面applicationが解釈する。Nape Gestureが結果を選ぶ、対象applicationへ命令する、特定結果を保証する設計にしない。
- 製品配送にAX scrollbar、対象PIDへの直接投稿、keyboard shortcut代替、DriverKit virtual trackpadを使わない。
- 診断専用の単純event投稿、AX、PID、shortcut経路が残る場合は、製品moduleと到達不能な境界で分離する。診断経路を製品fallback、runtime capability、完成証跡へ使わない。

## 実装と移行

- buttonごとの結果別mode、結果別action、方向別binding、application別設定が現行実装に残っている間は、製品モデル未達と扱う。button 3 / 4 / 5へ3つの固定GestureClassから1つを割り当てる設定は、この禁止対象に含めない。
- button割り当てモデルへの変更は、入力認識、session、出力、設定schema、設定UI、migration、状態表示、diagnostics、docs、testsを一貫して更新する。名称だけの変更や、廃止対象modeを別classへ読み替える互換処理では完了にしない。
- 廃止対象の設定項目を削除する際は、結果別modeを新しい意味へ暗黙変換しない。`gesture.buttonAssignments.button3` / `button4` / `button5`をcanonical stateとして保存し、再起動後も廃止項目を復活させない。
- 現行のADR、要件、README、検証文書、Issue、テスト名はbutton割り当て→GestureClass→class固有ProductOutputモデルだけを説明する。誤った設計の説明や参照が一つでも残る状態を文書移行完了にしない。
- ユーザーが見る挙動、GUI、権限導線、検証手順、完成状態、配布手順を変える場合はREADMEを更新する。更新不要ならPR本文で理由を明記する。

## 低レベルcontractと安全性

- 通常SDKで公開されないevent contractは、最小のcompatibility adapterへ隔離する。
- 実行中macOSのversion / buildは診断と検証証跡に記録するが、ProductOutputの`supported`判定には使わない。OS更新だけを理由にruntimeを停止しない。
- `supported`は、登録済みfixture ID、SHA-256、schema、contract ID、fixture実体、収録元OS情報を含む同梱asset間の整合性、製品runtimeからの到達性がすべて一致するときだけ使う。未登録fixtureや不整合ではfail closedにし、入力抑制を始めてからfallbackへ切り替えない。
- 低レベルeventを構築できること、dry-runが成功すること、画面が動くことだけでは、GestureClass contractの再現や製品完成の証拠にしない。
- event tap、入力抑制、session終了、kill switch、通常入力復帰は一体で検証し、途中失敗でmouse操作を失わせない。

## 完成判定

- button 3 / 4 / 5から3つの固定GestureClassへの対応を、core test、product boundary test、設定UI test、migration testで固定する。
- 押下開始、連続量、方向転換、button解放、cancel、停止、復帰を同一sessionのlifecycleとして検証する。
- button未押下時とsession終了後の通常mouse passthroughを、イベント種別ごとのtarget logと実利用経路で検証する。
- 製品sourceとbundleに結果別mode、方向別action、application別設定、AX / PID / shortcut配送がないことを機械検査する。
- 純正trackpadの2 / 3 / 4本指物理capture、manifest、fixture、OS build、生成event、system-wide配送を対応付ける。
- macOS / applicationの結果確認は低レベルcontractと分け、scenarioごとに記録する。
- Nape Pro実機からの入力、TCC許可済み製品runtime、通常入力復帰までのend-to-end証跡が揃うまで完成としない。
- Developer ID署名、公証、stapler、Gatekeeper評価が必要な配布状態は、その証跡が揃うまでリリース完了としない。
- 現行実装が条件を満たさない場合、README、Issue、PR、status reportへ「未達」と残し、部分実装を完成済みと表現しない。

## Computer Useとneed:human

- 専用CLI、GitHub / browser / app plugin、スクリプトで完結する作業はそれらを優先する。
- ローカルMacアプリの読み取り、クリック、入力、スクロール、ドラッグ、画面証跡取得が必要な場合はcomputer-useを使う。
- `.app`起動、設定ウィンドウ、メニューバー、System Settings paneの表示確認はcomputer-useで前進させる。
- TCC、アクセシビリティ、入力監視、VPN、OSセキュリティなどの設定変更直前には、具体的な操作内容とリスクを説明してユーザー確認を取る。
- `need:human`は、computer-useでも代替できない物理trackpad操作、Nape Pro実機操作、本人認証、秘密情報入力、証明書操作などに限定する。レビュー待ちや判断待ちには使わない。
- 画面証跡は、ログ、`doctor --json`、runtime evidence、fixture照合、CIの代替にしない。

## 由来と独立監査

- 第三者プロジェクト由来のコード、定数、状態遷移、係数をコピーしない。実装契約とパラメータはApple公式資料、Apple OSS、このリポジトリの純正trackpad / Nape Proログから再導出する。
- 実装上必要な実依存の識別子と法定通知を除き、README、実装、コメント、テスト名、ユーザー向け文書へ不要な第三者プロジェクトの固有名、コンポーネント名、参照実装由来と読める表現を残さない。
- Grok CLIによる独立監査、補助レビュー、UI / UX発散、文言確認、PR差分レビューは行わない。
- Grokの実行結果を設計判断、Issue要件、PR review、完成判定、CI gate、runtime証跡へ使わない。
- 設計、実装、レビュー、merge判断はメインスレッドが責任を持ち、並列化には通常のCodexサブエージェントだけを使う。
- `artifacts/grok-review/`へ新しい証跡を追加しない。旧証跡が存在しても現在の判断根拠にはしない。
