# ADR-0044: 検証済みapp bundleを原子的に導入する

- 状態: 採択
- 日付: 2026-07-12

## 背景

`bundle-app --replace`が既存`.app`を先に削除してから新しいbundleを構築すると、resource不足、書込失敗、検証失敗の時点で利用可能な旧bundleまで失う。単に一時directoryを使うだけでも、任意の既存directory、symlink、検証後の内容差し替え、親pathの競合、未知CLI optionを安全に扱えなければ、配布物作成の境界として不十分である。

## 決定

- 出力先は親directory直下の`.app` pathに限定する。`--replace`で既存項目を置換する場合は、通常directory、非symlink、同一filesystemに加え、`Info.plist`のbundle ID、実行ファイル名、package typeがNape Gestureのidentityと一致することを必須にする。
- CLI optionは`--out <path>`と`--replace`だけを厳格に解釈し、重複、欠落値、未知optionを拒否する。`verify-bundle`もpathと`--require-signature`以外を拒否し、署名gateの誤記を成功扱いにしない。
- 同一filesystemの所有者専用一時`.app`へ、実行ファイル、Info.plist、組み込み済みの正規ライセンス / 通知、trackpad contract、output modelをすべて書き出す。作業directoryの同名fileは入力にしない。構造検証後にtree全体のpath、file種別、size、SHA-256からfingerprintを作り、導入直前と導入直後に一致を確認する。
- 一時bundleの通常fileとdirectoryを下位から`fsync`し、内容が変化していないことをfingerprintで再確認してからrenameする。rename / swap後、旧bundle cleanup後にも親directoryを`fsync`し、process実行中のentry原子性だけでなくcrash後の永続性を境界へ含める。
- 親directoryを`O_DIRECTORY | O_NOFOLLOW`で開き、そのdescriptorに対する`renameatx_np`を使う。新規導入は`RENAME_EXCL | RENAME_NOFOLLOW_ANY`、既存置換は`RENAME_SWAP | RENAME_NOFOLLOW_ANY`とし、検査済み親pathを置換時に再解決しない。
- filesystemが排他的renameまたはswap renameをサポートしない場合は、非原子的fallbackへ移らず、既存bundleを保持して明示的に失敗する。
- swap / rename後のentry identityまたはfingerprintが競合した場合は、競合後のentryへ自動rollbackを行わず、両entryを保持して失敗する。検査対象ではないentryをrollbackで移動しない。
- swap後の旧bundleは、親directory descriptorから`openat(O_NOFOLLOW)`で固定し、各階層を`fstatat`しながら`unlinkat`で再帰削除する。検査後にpathベースの再帰削除へ戻らない。cleanup失敗時は新bundleを再削除せず、隠し一時名とerrorを残して調査可能にする。
- `verify-bundle`はbundle rootから必須resourceまでの全directory component、実行ファイル、Info.plist、license、notice、contract、modelのsymlinkを受理しない。bundle ID、実行ファイル名、名称、package typeも正規identityとの完全一致を要求する。必須product resourceはrepository checkoutだけでなく、実行中`.app`自身のResourcesからも再bundleできる。

## 理由

- 構築と検証を旧bundleの外で完了すれば、失敗時に日常利用可能な成果物を維持できる。
- descriptor相対renameとnofollowを使えば、親path差し替えとdestination競合を、path文字列の事前検査だけに依存せずに拒否できる。
- 既存destinationのproduct identityを必須にすれば、`--replace`を任意directoryの破壊操作として使えない。
- 非対応filesystemで安全性を落とすより、明示失敗して旧bundleを残す方が配布操作として予測可能である。

## 検証

```sh
swift build --product nape-gesture
sh scripts/test-bundle-app-safety.sh .build/debug/nape-gesture
```

回帰テストは、新規作成、inodeが変わるswap置換、一時物なし、任意directory拒否、`--out`欠落、未知署名option、最終file / 中間directoryのsymlink拒否、作業directoryのライセンス非採用、別bundle ID拒否、別作業directoryからの再bundle、resource欠落時の旧bundle SHA保持を確認する。

## 限界

- 同一ユーザー権限の悪意あるprocessがfile内容を書き換え続ける状況を、署名・sandboxなしで暗号学的に排除するものではない。導入前後fingerprint、directory descriptor、rename identity検査を機械境界とする。
- Developer ID署名、公証、staple、Gatekeeper評価は別のrelease gateであり、本ADRの原子的導入だけでは完了しない。

## 関連

- [配布手順](../release.md)
- [検証手順](../verification.md)
- [PRレビューチェックリスト](../pr-review-checklist.md)
