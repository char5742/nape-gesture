# ADR-0034: DriverKit virtual trackpadを製品出力に使わない

- 状態: 採択
- 日付: 2026-07-11
- 更新日: 2026-07-12

## 背景

通常mouse入力をtrackpad入力へ変換する方法として、HIDDriverKitでvirtual digitizer contactを生成する構成を検討できる。しかし、Nape Gestureが必要とするのは新しい物理touch surfaceの追加ではなく、対象mouseの連続イベント量を、buttonに対応するfinger countのtrackpad driver上位入力としてmacOSへ渡すことである。

DriverKit System Extensionを導入すると、`.dext`、entitlement、installation、approval、更新、uninstall、OS互換性という別の運用面が増える。現在の必要条件を満たすための最小境界ではない。

## 決定

- DriverKit System Extension、virtual digitizer、virtual trackpad descriptorを製品出力に使わない。
- `.dext`とDriverKit entitlementをbuild、release、権限導線へ追加しない。
- 対象device識別、通常入力passthrough、変換session中の元入力抑制はIOHIDとevent tap境界で扱う。
- 出力は純正trackpadの物理captureから再導出したdriver上位event contractを、最小のcompatibility adapterでsystem-wideに投稿する。
- button 3 / 4 / 5は2 / 3 / 4本指を固定し、結果別eventやvirtual touch形状を選ぶ設定を持たない。
- AX、対象PID配送、keyboard shortcutを代替経路にしない。
- 公開APIと自前計測で安全な上位event contractを確定できないOS buildでは、元入力抑制前にfail closedする。

## 影響

- 調査対象はvirtual digitizer contactではなく、2 / 3 / 4本指の純正trackpad上位eventにおけるX/Y量、finger count、phase、timestamp、session、terminalになる。
- DriverKit固有のinstaller、approval、recoveryは不要になる。
- compatibility adapterの非公開contractリスクは、fixture registry、OS build gate、strict analyzer、fail closedで管理する。

## 関連

- [ADR-0036: finger-count付きtrackpad driver上位入力を再現する](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0049: buttonを指本数へ固定しイベント量をtrackpad入力へ置換する](0049-fixed-button-to-finger-count-trackpad-input.md)
- [ゴール要件](../requirements.md)
