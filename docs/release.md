# リリース手順

この文書は `.app` バンドル作成、署名、公証、配布前の権限付与確認をまとめる。Apple Developer ID と App Store Connect 認証情報がない環境では、公開配布用の署名と公証は実行しない。

## ローカルで再現できる検証

release build から `.app` を作成し、バンドル構造と同梱文書を検証する。

```sh
sh scripts/check-provenance.sh
swift build -c release --scratch-path .build
.build/release/nape-gesture bundle-app --out .build/NapeGesture.app --replace
.build/release/nape-gesture verify-bundle .build/NapeGesture.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'dev.char5742.nape-gesture'
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'nape-gesture'
/usr/libexec/PlistBuddy -c 'Print :CFBundleName' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'Nape Gesture'
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' .build/NapeGesture.app/Contents/Info.plist | grep -Fx 'Nape Gesture'
cmp LICENSE .build/NapeGesture.app/Contents/Resources/LICENSE.txt
cmp THIRD_PARTY_NOTICES.md .build/NapeGesture.app/Contents/Resources/THIRD_PARTY_NOTICES.md
```

`verify-bundle` は次を確認する。

- `Contents/Info.plist`
- `Contents/MacOS/nape-gesture`
- `Contents/Resources/LICENSE.txt`
- `Contents/Resources/THIRD_PARTY_NOTICES.md`
- `codesign --verify --deep --strict --verbose=2` による署名状態

通常の `verify-bundle` は署名が未完了でも構造検証を続行し、署名状態を表示する。公開配布前のゲートでは `--require-signature` を付け、署名検証失敗をエラーにする。
`sh scripts/check-provenance.sh` は、外部ソースを読まずに tracked files だけを対象として、由来方針の削除や許可外の識別子混入を検出する。これは法的な完全証明ではなく、配布前に実施する repo-local の退行検知である。
`PlistBuddy` と `cmp` は、権限付与対象の identity と同梱文書の原本一致を機械的に固定する。

```sh
.build/release/nape-gesture verify-bundle --require-signature .build/NapeGesture.app
```

## ローカル ad-hoc 署名

Apple Developer ID 認証情報がない環境では、ローカル検証用に ad-hoc 署名を使える。

```sh
codesign --force --deep --sign - .build/NapeGesture.app
codesign --verify --deep --strict --verbose=2 .build/NapeGesture.app
.build/release/nape-gesture verify-bundle --require-signature .build/NapeGesture.app
```

ad-hoc 署名はローカルの署名整合性確認だけを目的にする。ad-hoc 署名では公証できず、公開配布の完了条件にはならない。

## 公開配布用の署名と公証

公開配布では Developer ID Application 証明書で署名し、hardened runtime と timestamp を有効にする。証明書名は環境ごとに異なるため、`security find-identity -v -p codesigning` で確認した正式名を使う。

```sh
codesign --force --deep --options runtime --timestamp --sign "Developer ID Application: <Team Name> (<Team ID>)" .build/NapeGesture.app
codesign --verify --deep --strict --verbose=2 .build/NapeGesture.app
.build/release/nape-gesture verify-bundle --require-signature .build/NapeGesture.app
```

公証へ提出する成果物は zip または dmg にする。zip を使う場合の例は次のとおり。

```sh
ditto -c -k --keepParent .build/NapeGesture.app .build/NapeGesture.zip
xcrun notarytool submit .build/NapeGesture.zip --keychain-profile <profile> --wait
xcrun stapler staple .build/NapeGesture.app
xcrun stapler validate .build/NapeGesture.app
spctl --assess --type execute --verbose=4 .build/NapeGesture.app
```

`xcrun notarytool submit --wait` は App Store Connect 認証情報または keychain profile が必要なため、このリポジトリの通常ローカル検証では実行しない。公証が成功したら stapler でチケットを `.app` へ添付し、`stapler validate` と `spctl --assess` の結果をリリース証跡に残す。

## 配布前の権限付与確認

配布前の動作確認では、権限付与対象を `.build/NapeGesture.app` に統一する。bundle ID は `dev.char5742.nape-gesture`。

システム設定の「プライバシーとセキュリティ」で、次の権限を `.build/NapeGesture.app` に付与する。

- アクセシビリティ
- 入力監視

権限付与後に反映されない場合は、`NapeGesture.app` を終了して再起動する。確認には次を使う。

```sh
.build/release/nape-gesture doctor --probe-hid
```

`doctor --json` の `runtimeIdentity` に表示される実行ファイル、bundle path、bundle ID が、権限を付与した `.app` と一致していることを確認する。
