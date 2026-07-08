# ADR-0020: doctor TCC 権限付与対象の構造化

- 状態: 採択
- 日付: 2026-07-09

## 背景

`doctor --json` は `runtimeIdentity` と `tccStatus` を出力している。
しかし、TCC 権限が未許可のとき、後続の証跡スクリプトや Issue コメントは `runtimeIdentity` と日本語の `remediation` を読み合わせて、どの `.app` または実行ファイルへ許可を付けるべきか判断していた。
この状態では、権限導線が人間向け文章に寄り、`need:human` の作業依頼を最小化するための機械判定が弱い。

## 決定

- `doctor --json` の `tccStatus` に `permissionTarget` を追加する。
- `permissionTarget` は `description`、`preferredGrantTarget`、`processName`、`executablePath`、`bundleIdentifier`、`bundlePath`、`isAppBundle`、`restartRequiredAfterGrant` を持つ。
- `preferredGrantTarget` は `.app` 実行時に `appBundle`、SwiftPM / debug 実行ファイルでは `executable` とする。
- `tccStatus.accessibility` と `tccStatus.inputMonitoring` に `grantRequired` を追加する。
- `inputMonitoring.status == "notProbed"` は未判定なので `grantRequired` を出さない。
- HID 入力監視プローブが失敗した場合は `hidProbe.failureCode` を出し、`notPermitted` のときだけ `tccStatus.inputMonitoring.grantRequired` を `true` にする。
- `failureCode` は `notPermitted`、`notPrivileged`、`noDevice`、`exclusiveAccess`、`ioReturn.<code>` の安定コードにする。

## 影響

- TCC 未許可時に、人間へ依頼する対象を `tccStatus.permissionTarget` から機械的に引用できる。
- `runtimeIdentity` と `permissionTarget` の一致を確認し、日常利用する `.app` と違う実行主体へ権限を付ける取り違えを減らせる。
- `grantRequired` は完成を意味しない。`true` の場合は macOS UI 操作が最後の手段として必要であり、権限付与後に `doctor --probe-hid --json --assert-runtime-ready` を再実行して採否する。

## 関連

- [doctor runtime ready の機械判定](0011-doctor-runtime-ready-assertion.md)
- [Runtime event 証跡の status JSON](0019-runtime-event-status-json.md)
- [GUI 権限復旧導線の表示契約](0025-gui-permission-recovery-actions.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
