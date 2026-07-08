# ADR-0025: GUI 権限復旧導線の表示契約

- 状態: 採択
- 日付: 2026-07-09

## 背景

`doctor --json` は `runtimeIdentity` と `tccStatus.permissionTarget` で、どの `.app` または実行ファイルへ TCC 権限を付与すべきかを構造化している。
一方で、常駐 GUI の「権限とデバイス」確認は状態表示と Accessibility prompt に寄っており、macOS の System Settings でユーザーが開くべき画面を明示的に分けて開く導線が弱かった。

人間作業は最後の手段に限定する。
TCC の許可操作そのものは macOS UI 操作として残るが、設定画面を探す作業はアプリ側で減らす必要がある。

## 決定

- 権限復旧 UI の文言、状態、ボタン名、System Settings URL は `NapeGestureCore` の `PermissionRecoveryPresenter` で生成する。
- アクセシビリティと入力監視は別々の `PermissionRecoveryAction` として扱い、状態表示と CTA を混ぜない。
- アクセシビリティ未許可時は `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` を開く導線を出す。
- 入力監視未許可または未判定時は `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` を開く導線を出す。
- 権限確認ダイアログは、許可対象、実行ファイル、bundle ID、権限状態、再起動が必要な旨を同じ画面で表示する。
- 常駐メニューとアプリメニューにも、アクセシビリティ設定と入力監視設定を直接開く項目を置く。
- 権限変更後は Nape Gesture を再起動してから `doctor --probe-hid --json --assert-runtime-ready` または runtime event 証跡を再実行して採否する。

## 影響

- `need:human` の対象は、System Settings 画面で実際に許可を付ける操作へ狭まる。
- 「設定画面を探す」「アクセシビリティと入力監視のどちらを開くべきか判断する」作業は GUI から代替できる。
- GUI 導線を追加しても、TCC blocker が解消したことにはならない。完成判定では、権限付与後の `doctor` と runtime event の成功証跡を必要とする。
- System Settings URL は macOS の公開 URL scheme であり、macOS 更新で挙動が変わる可能性がある。開けない場合は手動で同じ pane を開く回復手順を docs に残す。

## 関連

- [doctor TCC 権限付与対象の構造化](0020-doctor-tcc-permission-target.md)
- [Runtime recovery 境界条件の機械証跡化](0008-runtime-recovery-boundary-evidence.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証方針](../verification.md)
