# ADR-0036: 通常スクロールはポインタ直下 window owner PID と AX Web fallback で配送する

## 状態

採択（公開 AX API の成立範囲に限定）

## 背景

`horizontal-scroll` の Safari 実動作確認では、`CGEvent` に水平 delta、phase、precise / continuous field があっても Web content の `scrollX` / `scrollY` は変化しなかった。
Reference Target App では `postToPid` が `sendEvent` / `localMonitor` に入る一方、`.cghidEventTap` / `.cgSessionEventTap` は foreground AppKit 受信の代替にならなかった。
Safari の top-level `AXScrollArea` scrollbar へ normalized `AXValue` を設定すると画面は動いたため、初期実装は `AXWebArea` ancestor の scrollbar を補助経路にした。

ただし、body scroll と内側 `overflow:auto` を持つ review ページでは、内側領域上の生成が `outer=508 / inner=0 / wheel=0`、Computer Use が `outer=0 / inner=1488 / wheel=1 / target=content` だった。
top-level scrollbar の set 成功だけを配送成功とすると、ポインタに近い nested target と Web の wheel semantics を迂回する。
また、AX scrollbar への連続 set は画面反映が非同期であり、各 step で実値だけを読み直すと古い値で後続 delta を失う。

## 決定

- `.free` / `.horizontal` の CGEvent fallback は、ポインタ直下の layer 0 window owner PID を `CGWindowListCopyWindowInfo` で特定して `postToPid` する。Spaces の `.forcedHorizontal` は `.cghidEventTap` を維持する。
- `kCGMouseEventWindowUnderMousePointer` と `kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent` に対象 window を設定する。
- Web fallback は `AXUIElementCreateApplication(PID)` による application-scoped hit-test の結果から ancestor を上昇し、最初の `AXWebArea` 自身、または対応する最も近い `AXScrollArea` / scrollbar 属性を持つ container を候補にする。window / app tree の descending 探索は行わない。
- nested frame の container を top-level より優先する。最も近い container が要求軸の一部だけを公開する場合は、利用可能軸だけを nested target へ配送し、未対応軸はそのイベントでは捨てる。利用可能軸が 0 の場合は outer container へ昇格しない。
- generic group の `AXDescription` は判定に使わない。必要な全 direct children の frame を deadline 内で調べ、要求軸の child clipping がある場合だけ ambiguous とする。frame / children / child frame の情報不足は `blocked` とし、通常の長い article/content group の大きさだけでは ambiguous にしない。
- container / child frame の座標・寸法が非有限、負寸法、終端座標overflowの場合も情報不足として `blocked` にする。
- 選択した対応 scrollbar の current value を解決できた場合だけ normalized `AXValue` を更新する。上下限で値が変わらない場合は target 解決済みの `noChange` とし、CGEvent を重ねない。
- 複数軸の途中 set failure は適用済み軸を rollback する。rollback 自体が失敗した場合は部分 AX 適用へ CGEvent を重ねない。
- ambiguous、情報不足、利用可能軸 0、target 解決後の値取得 / set 失敗は `blocked` として CGEvent fallback を抑止する。root hit-test 不能、または完全な ancestor 走査で非 Web と判定した `notHandled` だけが fallback を許可する。
- root hit-test が cold `kAXErrorCannotComplete` になった場合は探索 deadline 内で1回だけ再試行し、2回とも失敗した場合に限って `notHandled` とする。
- runtime の AX fallback、CGEvent fallback、離散ショートカットは serial queue に載せる。AX request がない Spaces は同期直送する。CLI / system-test は同期実行を既定にする。
- daemon 起動時と activation button 押下時に Web capability を prewarm する。window target cache は 500ms とするが、Web target は各 step で hit-test と純粋 selector により再解決する。
- normalized value cache は PID / window / pointer に加えて、解決した container identity を key に含める。同一点で nested / outer target が変われば再利用しない。250ms 経過後は新しく解決した scrollbar の実値を読む。non-Web miss cache は持たない。
- AX API の 1 call timeout は 20ms、prewarm 全体は 40ms、実配送探索は 120ms、async enqueue から配送判断までは最大 160ms とする。
- async performance log は provisional と queue 内 completion を `operationID` で解決し、schema 2 の deferred record に completion がなければ baseline を通さない。
- queue 内 completion は実際の配送結果を記録する。AX適用とrollback不能の部分適用は1件、`blocked` / `noChange` は0件とし、enqueue時の provisional 1件を最終成功として流用しない。
- `generate-scroll --post-to-pid <PID>` は自動化ホストが pointer window 判定を覆う場合の診断専用とする。`--post-to-pid` / `--ax-delivery` を含む value option は値必須とし、未知 option、重複 option、余分な positional argument を投稿前に拒否する。
- Safari の完成判定は top-level の `scrollX` / `scrollY` だけで行わない。[Safari scroll 配送比較](../safari-scroll-delivery-verification.md) の generic overflow、AX accessible frame、端到達、Computer Use、CGEvent variant を分ける。

## 根拠

- `nape-gesture log --only-generated` では scrollWheel の point / integer delta、phase、continuous field が生成されていた。
- Reference Target App の `postToPid` は `captureSourceCounts` に `sendEvent` と `localMonitor` を残した。
- document の `maxX=3544` のページで AX horizontal scrollbar value を `0.5` にすると `scrollX=1772` になった。
- 初期実装の top-level 検証では、PID override なしの async が横 `0 -> 1609`、縦 `0 -> 1675`、PID 固定 32 step が横 `0 -> 1438`、縦 `0 -> 1675`、負方向が両軸 0 へ復帰した。
- review 元ページの generic overflow は修正前生成が `outer=508 / inner=0 / wheel=0`、Computer Use が `outer=0 / inner=1488 / wheel=1 / target=content` だった。
- 修正後の repo fixture は generic overflow で全 scroll 値 0、AX accessible frame で `outer=0 / frame=367 / frameWheel=0` だった。Computer Use は generic が `outer=0 / inner=682 / innerWheel=1`、frame が `outer=0 / frame=332 / frameWheel=1` だった。
- frame scrollbar を `1` にした後の正方向生成は `outer=0 / frame=1` を維持した。empty update を outer fallback と誤認しない。
- top-level fixture は斜め生成が `scrollX=679 / scrollY=304`、通常 content 上の縦生成が `scrollY=608` で、縦横 scroll を維持した。
- 今回変更後の最終 fixture では、unlabeled generic の全値 0 維持、微小横成分を含む縦のみ frame の `frame.y 0 -> 367` / outer 0 維持、長い article の `outer.y 0 -> 674`、top-level の `outer.x 0 -> 1358 / outer.y 0 -> 608` を確認した。全生成操作で wheel count は 0 のままだった。
- `scripts/probe-cgevent-scroll-delivery.swift` では PID 直接投稿が marker / source にかかわらず `wheel=0`、HID / session tap は `wheel=1` だが `inner=0 / outer=0`、annotated tap は `wheel=0` だった。
- HID / session tap と AX set の併用は採用しない。Web 側の `preventDefault()` を外部から判定できず、handler が止めた scroll を強制し得る。また tap 投稿では `--post-to-pid` の診断対象固定を保証できない。
- `artifacts/completion/2026-07-10/pr101-ax-delivery-final6` は target log 5シナリオ、runtime performance 3シナリオ、`deferredDeliveryRecordCount=0`、p95 0.10〜1.76ms を示す。ただし AppKit 受信、nested target、Safari 画面反映、wheel handler はこの性能値に含まない。
- AX scrollbar は 0...1 の normalized value であり、CGEvent pixel delta と CSS pixel の一致は成功条件にしない。

## 影響

- 通常アプリ内スクロールは前面アプリ固定ではなく pointer window owner を対象にする。
- window list の短期 cache は維持するが、AX target は nested の変化を見落とさないよう毎 step 再解決する。
- AX tree 上で検出できた ambiguous nested や情報不足を outer page へ誤配送しないため、positive `blocked` では AX set と CGEvent の両方を行わない fail-closed を優先する。
- lookup early return は成功扱いにしない。対象 scrollbar と current value を解決済みの端到達だけを `noChange` とする。
- AX scrollbar set は JavaScript `wheel` handler を発火しない。AX tree が generic overflow の container 境界と曖昧さの手掛かりをすべて省略する場合、公開 AX API だけでは実 wheel と同じ target / `preventDefault()` semantics を保証できない。この製品要件は未完了として残す。
- この branch では Issue #102 の時刻ドメインを重複修正しない。PR #101 の最終 Safari / runtime 証跡は Issue #102 の変更を取り込んだ head で再取得する。
