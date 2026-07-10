# ADR-0038: Safari 証跡では UI 操作、Quartz ポインタ、配送経路を分離する

- 状態: 採択
- 日付: 2026-07-10

## 背景

Safari の AX Web fallback は、現在の Quartz ポインタ直下にある layer 0 window owner を通常配送先として使い、application-scoped hit-test から scroll target を選ぶ。
一方、Computer Use の要素クリックや scroll は Accessibility 経由で対象 UI を操作できても、`CGEvent(source: nil)?.location` が示すシステムポインタを対象要素へ移動したとは限らない。

PR #101 の検証では、Safari の generic overflow を要素指定でクリックした後もポインタが iframe 上に残り、generic fail-closed の試行で frame が動いた。
また、Safari が `frontmostApplication` でも、Codex / ChatGPT window が WindowServer 上のポインタ直下先頭に残り、通常非PID配送が Safari へ届かない状態があった。

## 決定

- Computer Use はページ遷移、reset、native wheel、Accessibility tree、スクリーンショットの取得に使う。要素クリックの成功を Quartz ポインタ配置の証拠にはしない。
- 生成イベントの試行前は、検証専用に公開 API `CGWarpMouseCursorPosition` で対象点へポインタを移動する。要求座標、移動後座標、距離を保存し、2pt以内である場合だけ採用する。
- ポインタ座標は固定値だけで正当化しない。Safari window bounds、fixture screenshot、AX hit-test結果を対応づけ、target範囲を事前確認する。
- 各試行は `ready=true`、scenario一致、全座標とwheel countがreset値である before snapshotから開始する。
- 通常routingの証跡では、投稿直前の frontmost appに加えて、`swift scripts/capture-pointer-window-stack.swift` でQuartzポインタを含むlayer 0 window stackの先頭owner名、PID、window number、boundsをJSON保存する。
- `--post-to-pid <Safari PID>` はAX target選択とsync/async queueの診断に限定する。PID固定成功を、通常のpointer-window owner選択成功として扱わない。
- Codex / ChatGPTなど自動化ホスト自身のwindowが通常routingを覆い、Computer Useが安全制約上そのホストを操作できない場合、代替を記録した後に限り `need:human` とする。人間作業はホストwindowの一時退避とSafari前面化だけに絞る。
- Safari完成証跡は、contractとmanifestに配送mode、PID override有無、pointer/window事前条件、before/after/at-end、exit codeを構造化し、runtime evaluatorの終了コードで判定する。
- AX scrollbar set、実CGEvent log、Computer Use画面差分は別証跡とする。CGEvent tapが観測したキー列だけで画面成立やmodifier完全列を代替しない。

## 影響

- generic、frame、articleの取り違えを、製品不具合ではなく証跡準備不備として検出できる。
- PID overrideが通常routingの完成条件へ誤って昇格しない。
- Computer Useで完結できる操作は引き続き人間へ依頼せず、self-host制約のようにエージェントが解除できない境界だけをIssueとlabelで可視化できる。
- 検証中はポインタを移動するため、ユーザーの同時操作と並行しない。

## 関連

- [ADR-0030: Computer Use で GUI 操作と画面証跡を前進させる](0030-computer-use-gui-operation-evidence.md)
- [ADR-0031: Reference Target App の無人証跡では capture view へカーソルを固定する](0031-reference-target-cursor-focus.md)
- [ADR-0036: 通常スクロールはポインタ直下 window owner PID と AX Web fallback で配送する](0036-scroll-event-target-process-routing.md)
- [Safari scroll 配送比較](../safari-scroll-delivery-verification.md)
- [検証手順](../verification.md)
- Issue #105
- Issue #106
