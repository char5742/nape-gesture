# リリース手順

この文書は、固定されたbutton-to-GestureClass製品モデルの受入、`.app`作成、署名、公証、配布判定をまとめる。
package作成や公証が成功しても、source sample保存、固定GestureClass、session terminal、cursor固定、passthrough、実機証跡、fail closedの必須ゲートが未達ならリリースしない。
製品モデルの設計判断は[ADR-0049](adr/0049-fixed-button-to-finger-count-trackpad-input.md)を正とする。

## 現在のリリース状態

現行release候補はbutton 3 / 4 / 5を固定GestureClassへ接続し、Nape Pro実機の3 classを合計23 session受け入れている。ad-hoc署名版はローカル試用可能だが、純正trackpadとの最終比較、異常終了後の復旧、Developer ID署名、公証、stapler、Gatekeeperが未完了のため、公開配布は**リリース不可**である。

旧mode test、`supportedFamilies` / `confirmedFamilies` / `trialFamilies`、個別familyの生成成功、旧runtime evidence、画面結果、公証のいずれもこの判定を上書きしない。

## 製品モデル

release binaryは次だけを実装する。

| mouse入力 | 固定GestureClass | ProductOutput |
| --- | --- | --- |
| button 3押下中の連続event量 | 2本指scroll / swipe相当 | type 22 scroll + type 29 companion |
| button 4押下中の連続event量 | 3本指system swipe相当 | type 30 DockSwipe motion 1 / 2 |
| button 5押下中の連続event量 | 4本指system pinch相当 | type 30 DockSwipe motion 4 |
| button 3 / 4 / 5未押下 | 変換なし | 通常mouseをそのまま通す |

結果別mode、方向別action、application別設定を含めない。
`scroll`、`DockSwipe`、`NavigationSwipe`、`magnification`は低レベルcontractの観測語彙であり、ユーザーmode、独立製品機能、release capabilityではない。
OS/Appが入力結果を解釈し、製品runtimeは結果に応じてAX、対象PID、frontmost application、keyboard shortcut、別familyへ切り替えない。
同じsource event列を3 buttonへ与えた場合、変換前のX/Y量、符号、順序、timestamp、sample間隔を変えない。一方、各GestureClassは異なる上位event contractを使うため、event type、field、phase、companion、単位変換が異なることを必須とする。結果別またはユーザー調整可能な係数は持たない。

## 必須release gate

| gate | release条件 |
| --- | --- |
| source sample保存 | source eventが欠落・重複・並べ替えなく1 commandへ変換され、変換前の量、順序、timestamp、sample間隔を保持する |
| 固定GestureClass | button 3 / 4 / 5が全frameとterminalで2本指scroll / 3本指system swipe / 4本指system pinchへ固定され、進行中の追加buttonでも切り替わらない |
| session terminal | 正常終了と全異常終了がterminal 1件へ収束し、stuckとterminal後出力が0件 |
| cursor固定 | gesture session中はmouseとcursorのQuartz連動を停止し、button解放、cancel、tap中断、runtime停止、出力失敗で通常追従へ戻す |
| passthrough | 未押下、解放後、異常終了後の通常mouseが抑制・変更・再生成されない |
| 実機証跡 | 純正trackpadの3 class fixtureとNape Pro button 3 / 4 / 5を同じOS build、schema、manifestで比較済み |
| fail closed | unsupported条件で新規抑制・生成を開始せず、誤出力0件で安全停止し、fallbackを使わない |

7 gateは全て現行release binaryのrepo SHA、binary SHA-256、OS buildへ結び付ける。
1つでも未達、古いbinary、異なるrunの継ぎ合わせ、fixture不一致、未解決failureがあればreleaseを止める。

## 低レベルcontract gate

通常SDK非公開のevent contractは最小のcompatibility adapterへ隔離する。
対応対象の各macOS buildについて次を検査する。

- fixture schema、ID、SHA-256、contract ID、OS version / build、実体bytesが登録値と完全一致する
- 2本指scroll、3本指system swipe、4本指system pinchのclass固有表現を純正captureとgenerated captureで比較する
- source event量、変換model入力、generated frameの対応を検証する
- phase、terminal、補助event、順序、timestamp、session IDを検証する
- source、generated capture、direct post trace、manifest、binaryのprovenanceが一致する
- system-wide streamだけを使用する
- unknown build、symbol不在、fixture不一致で投稿前にfail closedになる

family名はreportの観測列に限る。familyごとの`supported`、`confirmed`、`trial`をrelease gateにせず、特定familyの成功を特定buttonの完成へ読み替えない。

## OS/App結果gate

OS/App結果は低レベルcontractと別report、別判定にする。

- App名 / version、macOS build、gesture設定を保存する
- button、finger count、event量、方向、速度、session IDを保存する
- 対応する低レベルcontract reportを参照する
- AppKit target logまたはsystem resultと画面観察を保存する
- 結果の成否にかかわらずterminalとstuckなしを確認する
- 実測していないApp、OS build、結果をrelease noteで主張しない

縦横scroll、application navigation、Space切替、Mission Control、App Exposé、Zoomなどは観測結果である。
低レベルcontract合格と結果不成立を同時に記録できる。画面結果が成立してもcontract不合格ならrelease gateは不合格である。

## ローカル検証

release候補と同じsourceからbuildし、全testとboundary guardを実行する。

~~~sh
sh scripts/check-provenance.sh
sh scripts/test-check-provenance.sh
ruby scripts/check-product-model-documentation.rb
ruby scripts/check-finger-count-product-model.rb
sh scripts/check-product-output-boundary.sh
swift build --scratch-path .build
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture-product-output-tests
swift build -c release --scratch-path .build
~~~

現行release候補ではCore / ProductOutput / diagnostic test、製品モデル文書guard、product-output boundary、release build、bundle verifierを成功させる。旧3 mode / 3 family routingが製品runtime、GUI、canonical設定へ到達しないことを確認する。

## release証跡

release候補ごとに次を1つのrootへ保存する。

~~~text
artifacts/release/YYYY-MM-DD/<repo-sha>/
~~~

最低限の内容:

- repo SHA、binary SHA-256、macOS version / build
- debug / release buildと全testの終了コード
- product / diagnostic boundary guard
- source sample、固定GestureClass、session、cursor固定、passthrough、fail-closed report
- 純正trackpadとNape Proのfixture / manifest / analyzer report
- 低レベルcontract report
- OS/App結果report
- runtime identity、TCC、device診断
- performance report
- bundle identity、同梱文書、署名、公証、Gatekeeper report
- 既知の未対応OS build、未検証App、未成立結果

異なるrepo SHAやbinaryの証跡をrelease packageへ混ぜない。

## app bundle作成

release buildから`.app`を作成し、構造と同梱文書を検証する。

~~~sh
.build/release/nape-gesture bundle-app --out .build/NapeGesture.app --replace
.build/release/nape-gesture verify-bundle .build/NapeGesture.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'dev.char5742.nape-gesture'
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'nape-gesture'
/usr/libexec/PlistBuddy -c 'Print :CFBundleName' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'Nape Gesture'
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'Nape Gesture'
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'false'
cmp LICENSE .build/NapeGesture.app/Contents/Resources/LICENSE.txt
cmp THIRD_PARTY_NOTICES.md .build/NapeGesture.app/Contents/Resources/THIRD_PARTY_NOTICES.md
~~~

`bundle-app --replace`は同一filesystem上の一時bundleを完成・検証・`fsync`してから原子的に置換する。
destinationがsymlink、Nape Gesture以外のdirectory、構築中にidentityまたはfingerprintが変化した場合は置換しない。
構築または検証失敗時は既存bundleを保持し、失敗した新bundleをrelease候補にしない。

通常の`verify-bundle`は未署名でも構造検証を続ける。公開配布gateでは`--require-signature`を付ける。

## 権限付き実機確認

配布する`.build/NapeGesture.app`へAccessibilityとInput Monitoringを付与し、同じbundle identityで確認する。

~~~sh
.build/NapeGesture.app/Contents/MacOS/nape-gesture doctor --probe-hid --json --assert-runtime-ready
~~~

終了コード0に加え、`runtimeIdentity`、bundle path、bundle ID、TCC permission target、対象device、OS build、contract fixtureがrelease manifestと一致することを確認する。
standalone binaryのTCC状態を配布`.app`の代用にしない。

この実行主体で次を取得する。

1. button 3 / 4 / 5のsource sample、固定GestureClass、terminal。
2. gesture中のcursor固定と、未押下、正常解放後、異常終了後のpassthrough。
3. kill switch、runtime stop、sleep、device切断、TCC喪失、unsupported contractのfail closed。
4. 純正trackpadの3 classとのcontract比較。
5. OS/App結果の独立report。
6. 常駐CPU、tap-to-post、terminal遅延。

## ローカルad-hoc署名

Apple Developer ID認証情報がない環境では、ローカル整合性確認だけにad-hoc署名を使う。

~~~sh
codesign --force --deep --sign - .build/NapeGesture.app
codesign --verify --deep --strict --verbose=2 .build/NapeGesture.app
.build/release/nape-gesture verify-bundle --require-signature .build/NapeGesture.app
~~~

ad-hoc署名は公証できず、公開配布の完了条件ではない。event contract、実機入力、OS/App結果の証明にもならない。

## 公開配布用の署名と公証

公開配布ではDeveloper ID Application証明書で署名し、hardened runtimeとtimestampを有効にする。

~~~sh
codesign --force --deep --options runtime --timestamp --sign "Developer ID Application: <Team Name> (<Team ID>)" .build/NapeGesture.app
codesign --verify --deep --strict --verbose=2 .build/NapeGesture.app
.build/release/nape-gesture verify-bundle --require-signature .build/NapeGesture.app
ditto -c -k --keepParent .build/NapeGesture.app .build/NapeGesture.zip
xcrun notarytool submit .build/NapeGesture.zip --keychain-profile <profile> --wait
xcrun stapler staple .build/NapeGesture.app
xcrun stapler validate .build/NapeGesture.app
spctl --assess --type execute --verbose=4 .build/NapeGesture.app
~~~

公証、stapler、Gatekeeper評価は配布物の信頼性gateであり、低レベルcontract互換性やfinger countの証明ではない。

## 最終判定

release ownerは次を全て確認する。

- 7つの必須gateが現行release binaryで合格
- low-level contractとOS/App結果が別々に判定済み
- 性能基準が3 GestureClass、cursor固定、passthrough、fail closedで合格
- debug / release build、全test、boundary guardが成功
- bundle、identity、同梱文書、Developer ID署名、公証、stapler、Gatekeeperが成功
- README、completion、verification、performance、release noteの主張が一致
- 未検証事項、未対応OS build、未成立OS/App結果を明記
- 旧3 mode / 3 familyの完成主張を現在のreleaseへ含めていない

1項目でも満たさない場合は`release blocked`とし、既知の問題として後回しにせず根本原因を修正して全証跡を取り直す。
