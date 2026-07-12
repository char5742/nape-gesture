# PR レビューチェックリスト

PRは実装量ではなく、固定製品モデルと実測証跡で判定する。
button 3 / 4 / 5押下中の連続mouse event量を2 / 3 / 4本指trackpad入力へ変換し、未押下時は通常mouseをそのまま通すことが唯一の製品モデルである。
設計判断は[ADR-0049](adr/0049-fixed-button-to-finger-count-trackpad-input.md)を正とする。

改訂基準commit`55eb991`は旧3 mode / 3 family routingを保持しており未達である。旧testが成功した、個別familyを投稿できた、画面結果が得られた、という理由だけで完成またはmerge可能と判定しない。

## 共通ゲート

- 対応Issueと変更ファイルの所有範囲が明記されている
- 並行作業者の差分をrevert、上書き、無関係に整形していない
- code / Package / workflow変更ではdebug build、全test target、必要なrelease buildが成功している
- docs / configだけの変更では、実施した検証とbuild省略理由がPR本文にある
- ユーザー挙動、GUI、権限、検証、完成状態、配布を変えた場合はREADMEを更新し、更新不要なら理由を記載している
- 未検証、candidate、履歴証跡を`完了`、`supported`、`release ready`と表現していない
- field、状態遷移、係数、許容差がApple資料、Apple OSS、純正trackpad / Nape Pro自前logへ追跡できる
- 不要な第三者固有名や参照実装由来の表現がproduct code、test、docsへない
- 実装上必要な実依存の識別子と法定通知を除き、README、実装、コメント、テスト名、ユーザー向け文書に不要な第三者プロジェクトの固有名、コンポーネント名、参照実装由来と読める表現がない
- 由来に影響する変更では`check-provenance.sh`と回帰testが成功している
- Grok CLIや外部モデルの結果を設計判断、review、完成判定、CI gate、runtime証跡へ使っていない
- computer-useで代替できるGUI操作を`need:human`にせず、TCC変更直前にはユーザー確認を取る

## 固定製品モデル

- `ruby scripts/check-product-model-documentation.rb`と`ruby scripts/check-finger-count-product-model.rb`が成功している
- button 3が2本指、button 4が3本指、button 5が4本指へ固定されている
- buttonごとの結果選択modeがproduct model、設定、GUI、CLI、doctorにない
- 方向別actionとOS/App結果別actionがない
- application別の有効・無効、感度、割り当てがない
- finger countを方向、速度、App、低レベルfamily、OS/App結果で変更しない
- 同一source fixtureでは、3 buttonが同じ正規化入力の量、順序、時間間隔を使い、finger count固有の物理encoding差だけが登録contractと一致する
- `scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`を観測語彙として扱い、ユーザーmodeや製品capabilityにしていない
- 旧設定migrationが旧modeを別の結果actionへ流用せず、固定button-to-finger-count modelへ安全に廃止または正規化する
- 進行中sessionへの追加buttonでfinger count、family、session IDを切り替えない
- unknown button、session開始時の曖昧な複数activation button、順序欠落からfinger countを推測しない

## event量保存

- 各source eventのsequence、timestamp、`deltaX`、`deltaY`を変換前に保存する
- 受理eventと変換器入力が件数・順序・値のbit単位で一致する
- 複数source sampleをcoalesceせず、各sampleのdeltaとtimestampを個別に対応付けている
- X / Y、正負、斜め、停止、方向反転のtestがある
- 最終delta合計だけで保存を判定していない
- terminal用zero frameや補助eventをsource event量へ加算していない
- 純正fixture由来の単一versioned単位変換contractについて、係数、clamp、許容差が登録fixtureへ追跡でき、結果別またはfinger count別の係数がない
- queue drop、重複、並べ替え、整数飽和、非有限値を成功扱いにしない
- source-to-output対応reportを同じrun UUIDで保存している

## finger count

- button downでfinger countを確定し、terminalまで変更しない
- 全generated frameとterminalが期待finger countを持つ
- 2 / 3 / 4本指の正常、方向反転、cancel testがある
- event typeやclassifierだけからfinger countを推測していない
- 純正2 / 3 / 4本指captureでfinger count表現を固定している
- Nape Pro button 3 / 4 / 5のgenerated captureを同じschemaで比較している
- contractがfinger countを表現できない場合はunsupportedとしてfail closedにする

## session terminal

- button downから対応button upまでが1 sessionである
- session ID、0始まりの欠落なしcapture order、source timestamp、sample間隔、登録contractのtimestamp関係を保持する
- 正常終了、cancel、kill switch、runtime stop、sleep、device切断、TCC喪失、output failureをtestしている
- 開始した全sessionがterminal 1件へ収束する
- terminal重複、terminal後event、stuck sessionが0件である
- active session中に別sessionを開始しない
- 部分投稿時にtrace順と実投稿順が一致し、再送またはcancelで予約eventを解消する
- terminal生成失敗を成功扱いにせず、安全停止と物理解放待ちを報告する

## passthrough

- button 3 / 4 / 5未押下時のmove、click、double-click、drag、wheelを変更しない
- button 1 / 2、対象外button、対象外deviceを変更しない
- 未押下時のgenerated、suppressed、mutated eventが全て0件である
- activation session中の漏れ防止と未押下passthroughを別scenario、別countで判定する
- 正常解放、kill switch、output failure、sleep復帰、device再接続、TCC復旧後をtestしている
- 異常終了時にactivation buttonの物理解放前のdown/upを誤clickとして漏らさない
- 物理解放後は通常passthroughへ戻る
- 前面App target logで実機確認している

## 実機証跡

- 純正trackpadの2 / 3 / 4本指captureが同じ対象OS buildでそろっている
- 各finger countに正負X/Y、斜め、停止、方向反転、正常terminal、cancelがある
- Nape Pro button 3 / 4 / 5のsource、HID、generated、post traceがそろっている
- 未押下passthroughと異常終了を実機で取得している
- logger ready token、deadline、PID、scenario、repo SHAを操作前後に検証している
- 0 event、drop、ready期限切れ、manifest不成立を採用していない
- manifestがrepo SHA、binary SHA-256、OS build、fixture ID / SHA-256、log SHAを固定する
- physical captureへgenerated marker、不要なdevice ID、keycode、pointer座標を混入させていない
- dry-run、合成input、画面移動、computer-use画像だけで実機証跡を代用していない

## fail closed

- unsupported OS/build、symbol不在、fixture不一致でevent tapと抑制を開始しない
- fixture ID、SHA-256、schema、contract ID、OS build、実体bytesを全て検証する
- 明示contract pathが空、読取不能、空file、不正bytesなら他pathへfallbackしない
- finger count不明、device不一致、TCC不足、現在boot外timestamp、source / contractにないtimestamp変換、session不整合を拒否する
- event作成・投稿失敗のfailure injectionがある
- active sessionの失敗はterminalまたは構造化された安全停止へ収束する
- rejection後のgenerated eventが0件である
- 物理解放後にpassthroughへ戻る
- AX scrollbar、対象PID、frontmost App分岐、keyboard shortcut、別family、旧単純scrollへfallbackしない
- `doctor`がfailure code、実行主体、TCC、device、contract provenanceを構造化して返す

## 低レベルcontract

- contract比較をfinger count、event量、session、terminal、provenanceで行う
- raw event type、subtype、field、serialized data、phase、補助eventを純正captureと比較する
- generated capture、direct post trace、manifest、binaryが同じrun UUIDで結合する
- system-wide streamだけを製品配送に使う
- family別の`supportedFamilies` / `confirmedFamilies` / `trialFamilies`を製品完成度として残していない
- 旧3 familyの成功をbutton 3 / 4 / 5の完成へ読み替えていない
- 候補fieldやcandidate fixtureを確定contractにしていない

## OS/App結果

- 低レベルcontract reportとOS/App結果reportを分離している
- OS/App結果reportにApp version、OS build、gesture設定、button、finger count、event量、session IDがある
- 縦横scroll、navigation、Space、Mission Control、App Exposé、Zoomを観測結果として記録している
- 画面が動いても低レベルcontract不合格なら製品合格にしていない
- 低レベルcontract合格でも結果不成立なら、その結果を未成立として明記している
- 未測定AppやOS buildの結果を製品機能として主張していない
- 結果を得るためのmode、方向別action、application別設定、配送fallbackを追加していない

## 性能

- event量、finger count、terminal、passthrough、fail closedの正確性gateをpercentileより先に判定している
- 純粋ロジックとevent tap / posting実測を別measurement kindにしている
- finger count 2 / 3 / 4と未押下passthroughを別bucketで測っている
- source受理から最初のpost、frame完了、terminal完了のp95 / p99を保存している
- passthrough追加遅延、logger queue depth、drop countを保存している
- idle、各finger count連続入力、terminal後、fail-closed待機のCPUを実機で測っている
- AppKit受信と画面反映時間を低レベル投稿時間へ混ぜていない
- [性能測定基準](performance-baseline.md)を全項目満たしている

## UI / 権限

- GUIはbutton 3 / 4 / 5と固定finger countを説明し、結果別mode selectorを表示しない
- 不正または旧設定を保存前・起動前に拒否または安全にmigrationする
- `runtimeIdentity`とTCC permission targetが実利用`.app`を指す
- AccessibilityとInput Monitoringの不足を区別する
- readiness成立前に入力抑制を開始しない
- sleep、device切断、TCC変更後の状態と復旧導線を説明できる
- GUI証跡をdoctor、runtime log、実機証跡の代用にしていない

## Release

- 6つの必須ゲートが全て現行binaryで合格している
- debug / release buildと全test targetが成功している
- product / diagnostic境界guardが成功している
- `.app` bundle、identity、同梱文書、署名検証が成功している
- 公開配布ではDeveloper ID署名、公証、stapler、Gatekeeper評価が成功している
- 署名・公証をevent contract互換性の証明にしていない
- README、完成判定、検証、性能、release docsの主張が一致する
- 未完了の実機scenarioやOS/App結果をrelease noteで明示している

## 差し戻し基準

次のいずれかがあれば差し戻す。

- 第三者プロジェクト由来のコード、field番号、定数、状態遷移、係数、調整値を持ち込んでいる
- 旧3 mode / 3 family modelを製品surfaceまたはroutingへ残す
- `check-finger-count-product-model.rb`が失敗する
- event量保存、finger count、terminal、passthroughのいずれかに機械testがない
- 純正trackpadまたはNape Pro実機証跡をdry-runで代用する
- family単体や画面結果を製品完成とする
- fail closedより先にevent tapまたは抑制を開始する
- AX、PID、shortcut、application分岐へfallbackする
- fixture hash、run identity、binary identityを検証しない
- terminal欠落、logger drop、test / CI失敗、未検証事項を後回しにする
