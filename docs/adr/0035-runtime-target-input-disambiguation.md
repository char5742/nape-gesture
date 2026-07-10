# ADR-0035: Runtime で対象・対象外 HID の同種入力を識別する

- 状態: 採択
- 日付: 2026-07-10

## 背景

macOS の event tap から得る `CGEvent` には、入力元 HID デバイスを直接識別できる安定した公開フィールドがない。
対象デバイスだけを IOHID 監視し、直近の対象活動が `associationWindow` 内にあるかだけを見る方式では、その直後に別マウスやトラックパッドから届いた同種の move / wheel / button を対象入力と誤認できる。
また、callback 実行時の `ProcessInfo.systemUptime` は HID レポート発生時刻ではないため、複数デバイスが近接して操作された場合の比較精度が足りない。

## 決定

- runtime の `HIDInputMonitor` は、対象デバイスに加えて他の pointing device も監視する。対象 matcher に一致する値は target、それ以外は non-target として `TargetDeviceGate` へ記録する。
- HID usage から button / pointer / wheel への変換は [ADR-0034](0034-hid-target-activity-mapper.md) の `HIDTargetActivityMapper` を共通利用する。
- HID 時刻は `IOHIDValueGetTimeStamp` の OS AbsoluteTime を `mach_timebase_info` で秒へ変換し、CGEvent timestamp と同じ単調時刻基準で比較する。`hid-log` も同じ変換を使う。
- activation button down / up、pointer、wheel は別の候補として保持する。異なる種別の HID 活動を関連付け根拠にしない。
- event tap と HID の時刻差は `0 <= eventTapTime - hidTime <= associationWindow` のときだけ関連付ける。event tap より後の HID 候補を `abs` 差だけで採用しない。
- 同じ種別で non-target HID を観測したら target 候補を破棄し、その HID timestamp から `associationWindow` 満了まで種別単位の quarantine に入る。quarantine 中は target の近さにかかわらず全入力を通常入力として通す。
- target 候補は最大 32 cohort の bounded queue で保持し、同じ HID report timestamp の X / Y を一つの cohort とする。event tap 入力へ関連付けた候補は 1 回で消費し、overflow は quarantine として fail-open にする。
- 進行中ジェスチャーで quarantine または non-target 同種入力を検出した場合は、元入力を通し、recognizer と慣性を内部 cancel する。同じ物理押下中にジェスチャーを再開しない。
- activation button release 待ちは、対象 HID button down と関連付けて実際に受理した event tap button down だけが作る。対象 HID release 候補がある event tap release だけを処理する。HID 証拠より event tap release が先に届いた場合は原入力を通常通過させ、recognizer を内部 cancel して stuck を防ぐ。
- non-target の非 activation button も進行中ジェスチャーと慣性の cancel 信号として扱う。通常 button event 自体は gate で処理せず、そのまま通過させる。
- 対象デバイス切断時は gate の候補と押下状態を消去し、進行中ジェスチャーと慣性をキャンセルする。通常の runtime stop に伴う manager close は切断処理を発火させない。

## 影響

- 対象デバイス直後の別デバイス同種入力も、non-target HID 候補が観測できれば `associationWindow` 全体を安全側に通常入力として通る。
- 入力分類はアプリ単位ではなくデバイス単位であり、アプリ別の有効・無効、感度、割り当て設定は追加しない。
- pointing device 全体の IOHID callback を受けるため、デバイス matcher 判定は IOHIDDevice 単位で cache する。event tap callback 内では IOHID inventory を再走査しない。
- target と non-target が近接した入力や候補 overflow では、ジェスチャーの一部を取りこぼす可能性がある。通常入力の誤抑制を避けることを優先する。
- IOHID へ現れない入力源、event tap が対応 HID callback より先に届く順序、複数 HID 候補が同時刻になるケースを公開 API だけで完全識別することはできない。先着した対象 release も fail-open で通常通過するため、Nape Pro と通常入力デバイスの混在実機ログで元入力漏れと誤抑制の双方を測定し、完了判定する。
- target HID 候補が残っている間に non-target CGEvent がその non-target HID callback より先着した場合、時刻候補だけでは target CGEvent と区別できない。この race は実機混在ログで再現有無を確認するまで merge gate とし、再現する場合は入力値 cohort の照合または HID callback 配送経路の分離を追加検討する。

## 関連

- [ADR-0009](0009-target-device-association-window-assertion.md)
- [ADR-0034](0034-hid-target-activity-mapper.md)
- [検証方針](../verification.md)
- [完成判定チェックリスト](../completion-checklist.md)
