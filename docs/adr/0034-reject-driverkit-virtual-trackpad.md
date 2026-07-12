# ADR-0034: DriverKit virtual trackpad案を却下する

- 状態: 却下
- 日付: 2026-07-11

## 背景

AX scrollbar、対象PIDへのevent配送、keyboard shortcutによるgesture代替を却下した後、HIDDriverKitでvirtual trackpadのdigitizer contactを生成する案を検討した。

しかし、Nape Gestureの入力境界と目標挙動を整理すると、DriverKit System Extensionで物理touch surfaceを追加する必要はない。必要なのは、mouse入力をtrackpad driverの上位出力に相当するgesture event列へ変換し、scroll、Spaces、Mission Control、page navigation、magnificationをmacOSの標準gesture処理へ渡す構成である。

## 決定

- DriverKit System Extensionとvirtual digitizer contactを製品出力の前提にしない。
- `.dext`、DriverKit entitlement、virtual trackpad descriptorを完成要件へ追加しない。
- Nape Pro入力の識別、通常入力通過、gesture button中の抑制は既存のIOHID / event tap境界を基礎にする。
- 出力はtrackpad driverが上位へ出すgesture event contractを自前ログから再導出する。
- AX、対象PID配送、keyboard shortcutによるgesture代替へ戻さない。

## 影響

- DriverKit toolchain、entitlement申請、System Extension lifecycleは不要になる。
- 調査対象はdigitizer contactではなく、純正trackpad操作時のscroll / gesture event type、subtype、phase、momentum、field、event順序になる。
- DriverKit案として作成したIssue #107から#116は、新しいevent contract方針へ置き換える。

## 関連

- [ゴール要件](../requirements.md)
- [検証手順](../verification.md)
- [repo-local由来ガード](0023-repo-local-provenance-guard.md)
