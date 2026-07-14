# ADR-0034: DriverKit virtual trackpadを製品出力に使わない

- 状態: 採択
- 日付: 2026-07-11
- 更新日: 2026-07-14

## 背景

mouse入力を「2 / 3 / 4本指gesture」へ変換する要件を、raw digitizer contact数の生成と解釈すると、DriverKit System Extensionまたはvirtual HID deviceが必要に見える。

しかし、Nape Gestureが再現するのはraw touch surfaceではない。物理trackpad driverがgestureを認識した後に上位へ生成するtype 22 scroll + type 29 companionと、認識済みtype 30 / IOHID `DockSwipe`のevent contractである。「2 / 3 / 4本指」は固定GestureClassをユーザーへ説明する意味であり、transport上のcontact countやgeneric `fingerCount` fieldではない。

DriverKitを導入すると、`.dext`、entitlement、installation approval、更新、uninstall、OS互換性という別の運用面が増える一方、必要な上位event contractを直接表現する製品境界にはならない。

## 決定

- DriverKit System Extension、virtual trackpad descriptor、virtual HID、raw digitizer contactを製品出力に使わない。
- `.dext`とDriverKit entitlementをbuild、release、権限導線へ追加しない。
- 対象device識別、通常mouse passthrough、active sessionの元入力抑制はIOHIDとevent tap境界で扱う。
- button 3 / 4 / 5は、それぞれ2本指scroll / swipe、3本指system swipe、4本指system pinchの上位GestureClassへ固定する。
- 出力は2本指をtype 22 scroll + type 29 companion、3本指をtype 30 DockSwipe motion 1 / 2、4本指をtype 30 DockSwipe motion 4として最小compatibility adapterで構成し、system-wideへ投稿する。button 5はapplication magnification eventではない。
- AX、対象PID配送、keyboard shortcut、application別分岐を代替経路にしない。
- 25F80で収録した認識済みDockSwipe templateのfixture ID、SHA-256、schema、contract ID、収録元OS情報、fixture実体を検証してIOHID値を更新する。収録元OS情報は同梱asset間で照合し、実行中macOS buildとは比較しない。scroll contract、model、templateのどれかを安全に構成できない場合は、全ProductOutputを無効にして元入力抑制前にruntime全体をfail closedする。

## 影響

- 調査と検証の対象はraw contact形状ではなく、class別のevent type、subtype、field、phase、companion lifecycle、単位変換、timestamp、session、terminalとなる。
- DriverKit固有のinstaller、approval、recoveryは不要になる。
- 通常SDK非公開のcontract riskは、fixture registry、asset provenance、strict analyzer、source boundary、event構築可否、fail closedで管理する。
- 将来OSでevent構築または投稿前検証が成立しない場合もvirtual deviceへfallbackせず、ProductOutputをunsupportedとして通常mouse入力を保持する。build番号だけでは判定しない。

## 関連

- [ADR-0036: trackpad driver上位eventを安全に再現する](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0049: buttonを固定GestureClassへ接続する](0049-fixed-button-to-gesture-class-input.md)
- [ゴール要件](../requirements.md)
