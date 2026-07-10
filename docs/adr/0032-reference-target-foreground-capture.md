# ADR-0032: Reference Target App は foreground capture 経路を証跡化する

- 状態: 採択
- 日付: 2026-07-09
- 更新: 2026-07-10

## 背景

Runtime event 証跡で Reference Target App の target log が空になった。
TCC、HID probe、daemon 起動、`system-test` の CGEvent 投稿、runtime 性能ログは成立していたため、問題は AppKit 受信側の記録経路にあった。

`postToPid` は target App の sink 診断や対応シナリオの AppKit foreground 受信確認には使えるが、本番経路の `.cghidEventTap`、前面 window、座標、daemon 抑制を迂回するため、それ単独では完成証跡にできない。
また `globalMonitor` だけで取れたイベントは、前面 AppKit window が受け取った証跡として弱い。

## 決定

- Reference Target App は `NSApplication.sendEvent`、local monitor、capture view override の経路を `captureSource` として target log に残す。
- `analyze-target-log --assert-has-foreground-capture` を追加し、`globalMonitor` だけの target log を完成証跡にしない。
- Nape Gesture 生成イベントが前面 AppKit 経路へ届いたこと自体を成功条件にする場合は、`--assert-has-generated-foreground-capture` を使う。これは `generatedByNapeGesture` と `captureSource` の両方を満たすイベントだけを見る。
- ready file には `diagnostics` として active/key/main window、first responder、focus hit-test、window/capture bounds を残す。
- `scripts/collect-runtime-event-evidence.sh` は ready diagnostics を検査し、target window が active/key/main で capture view に focus 済みでない場合は scenario を失敗にする。
- `system-test --post-to-pid <pid>` は `space-left`、`space-right`、`horizontal-scroll` など対応シナリオの無人 foreground 受信診断に使える。ただし completion evidence では `.cghidEventTap` 経由の `system-test`、target log assertion、対象アプリの画面挙動証跡と分けて採否する。
- `mission-control`、`page-back`、`page-forward`、`zoom-in`、`zoom-out` の key shortcut 系は、2026-07-10 の実験で PID 直接投稿が target log に届かなかったため PID target 証跡の対象外とする。
- `sendEvent`、`localMonitor`、`captureView` は同じ NSEvent を異なる座標系で記録するため、canonical fingerprint は location を同一性条件に含めない。timestamp、event name、delta、phase、modifier、生成マークなどのイベント固有値で capture source 間の重複を排除する。
- 生成 foreground スクロールの方向 assertion は合計値の符号だけで判定しない。正方向を期待する場合は負値を、負方向を期待する場合は正値を1件でも含めば失敗とし、phase 終了用のゼロ量だけを許容する。

## 影響

- target log 空を、権限・投稿・前面化・記録経路のどこで失敗したか切り分けやすくなる。
- runtime event 証跡では、AppKit 受信が `sendEvent` または `captureView` まで到達したことを JSON で確認できる。
- capture source ごとの座標差で同一イベントの件数と移動量が水増しされず、逆方向イベントを合計値で相殺したログも成功扱いしない。
- `postToPid` 成功だけでは Issue #6 / #9 / #10 / #12 を完了扱いにしない。

## 関連

- [ADR-0006: Runtime event 証跡の自動収集と人間作業境界](0006-runtime-event-evidence-automation.md)
- [ADR-0019: Runtime event 証跡の status JSON](0019-runtime-event-status-json.md)
- [ADR-0031: Reference Target App の無人証跡では capture view へカーソルを固定する](0031-reference-target-cursor-focus.md)
- [検証手順](../verification.md)
- [完成判定チェックリスト](../completion-checklist.md)
