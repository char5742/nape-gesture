# ADR-0034: DriverKit virtual trackpad案を却下する

- 状態: 却下
- 日付: 2026-07-11

## 背景

AX scrollbar、対象PIDへのevent配送、keyboard shortcutによるgesture代替を却下した後、HIDDriverKitでvirtual trackpadのdigitizer contactを生成する案を検討した。

しかし、外部 reference implementation を設計調査として再確認した結果と目標挙動を突き合わせると、必要なのは DriverKit System Extension ではなく、mouse 入力を trackpad driver の上位出力に相当する gesture event 列へ変換する構成である。Nape Gesture が必要とするのも、物理 touch surface の追加ではなく、scroll、Spaces、Mission Control、page navigation、magnification を macOS の標準 gesture 処理へ渡すことである。

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
