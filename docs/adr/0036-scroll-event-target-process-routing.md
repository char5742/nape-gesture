# ADR-0036: 通常スクロールはポインタ直下 window owner PID と AX Web fallback で配送する

## 状態

採択

## 背景

`horizontal-scroll` の Safari 実動作確認で、`CGEvent` の水平 delta、phase、precise / continuous field は生成されていたが、Safari Web content の `scrollX` は変化しなかった。
Reference Target App でも `.cghidEventTap` / `.cgSessionEventTap` へ投稿した scrollWheel は `globalMonitor` だけに現れ、前面 AppKit window の通常受信経路に入らなかった。

一方で、`postToPid` で前面またはポインタ直下のアプリへ投稿した scrollWheel は Reference Target App の `sendEvent` / `localMonitor` に入り、`analyze-target-log --assert-has-generated-event --assert-has-foreground-capture` を通過した。
Safari Web content では、document の `maxX` がある検証ページでも CGEvent 合成 scrollWheel は水平 scroll root を動かさなかったが、`AXWebArea` ancestor から horizontal scrollbar value を設定すると `scrollX` が変化した。
同じく CGEvent 合成 scrollWheel 単体では縦スクロールの `scrollY` も安定した完成証跡にできないため、通常の `.free` スクロールでも `AXWebArea` が公開する vertical scrollbar を補助経路にする。
検証中、UserNotificationCenter の権限通知 overlay が `AXUIElementCopyElementAtPosition` の hit-test を奪い、画面上は Safari Web content に見える位置でも `AXSystemDialog` が返るケースがあった。
また、AX scrollbar への連続 set は画面側への反映が非同期であり、各 step で直前の `AXValue` を読み直すと古い値を基準に後続 delta を上書きすることが分かった。

## 決定

- 通常アプリ内スクロールに相当する `.free` / `.horizontal` は、現在のポインタ直下にある layer 0 window を `CGWindowListCopyWindowInfo` で特定し、その window owner PID へ内部 API の `CGEvent.postToPid` で配送する。CLI の `--post-to-pid` override とは区別する。
- 同時に `kCGMouseEventWindowUnderMousePointer` と `kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent` を設定し、対象 window をイベントに明示する。
- `.horizontal` は、ポインタ直下の AX element から ancestor を辿り、`AXWebArea` 配下の `AXHorizontalScrollBar` が見つかる場合は CGEvent を投稿せず normalized `AXValue` を delta に応じて更新する。
- `.free` は、ポインタ直下の `AXWebArea` 配下に horizontal / vertical scrollbar が見つかる場合、対応する delta だけ normalized `AXValue` を更新する。要求された AX 対象軸を事前に全て解決できた場合だけ AX 成功扱いにし、片軸だけ見つかった斜め入力で残りの delta を捨てない。上下限で値が変わらない軸は解決済みとして扱い、動ける他軸だけを更新する。
- AX fallback はアプリ名で分岐しない。Safari 固有対応ではなく、Accessibility が公開する Web content の scrollbar への補助経路として扱う。
- AX hit-test が通知や権限ダイアログなど別 PID の overlay を返しても、`CGWindowListCopyWindowInfo` で得たポインタ直下の通常 window owner PID を正とする。`AXUIElementCreateApplication(PID)` を渡した application 固定 `AXUIElementCopyElementAtPosition` を第一経路にし、対象 AXWindow / app tree の探索は fallback にする。
- runtime の event tap 経路では AX fallback、同じ入力の CGEvent fallback、離散ショートカットを serial queue に載せ、tap callback 自体を AX tree 探索で止めず、同経路内の生成順序も維持する。AX request がない Spaces `.forcedHorizontal` は queue 待ちを作らず従来どおり同期投稿する。CLI / system-test は実動作証跡を取りやすいよう同期実行を既定にする。
- daemon 起動時と activation button 押下時にポインタ直下 target の水平 / 垂直 Web capability を prewarm する。override PID が同じでポインタが直近 window bounds 内にある成功 target は 500ms、成功した target PID / window / pointer の scrollbar と最後に設定した normalized value は 250ms、探索を完了して非 Web と判定した結果は軸別に 500ms cache する。window target 不在や AX timeout / unavailable は miss cache せず、期限切れの non-Web entry は次の AX 処理時に破棄する。value cache 期限後は要素を捨てず実値だけ再取得し、非同期反映前の古い値で delta を失わない。
- AX API の 1 call timeout は 20ms、prewarm 全体は 40ms、実配送の探索全体は 120ms、async enqueue から fallback までの最大待ち時間は 160ms とする。application 固定 hit-test が成功した場合は ancestor だけを確認し、ポインタ下が非 Web 要素なら window 全体を探索せず CGEvent fallback へ進む。
- async 実配送の performance log は enqueue 時の provisional record と serial queue 内の実配送 completion record を同じ command 単位の `operationID` で結ぶ。解析時は completion の `postStartedAtNanoseconds` / `postFinishedAtNanoseconds` を使い、completion がなく schema 2 の `deliveryDeferred=true` のまま残った配送は baseline を通さない。
- `generate-scroll --post-to-pid <PID>` は自動化ホストの window がポインタ位置を覆う検証環境だけで使う診断用 override とする。通常 runtime のポインタ直下 window owner 選択は変更しない。
- Spaces 向けの `.forcedHorizontal` は従来どおり `.cghidEventTap` を維持する。macOS のグローバル操作候補と通常アプリ内スクロールは配送経路を分ける。
- Safari Web content の完成判定では、CGEvent 合成 scrollWheel 単体ではなく、AX fallback 後の `scrollX` 変化を画面反映証跡として採用する。

## 根拠

- `nape-gesture log --only-generated` では水平 scrollWheel の `pointDeltaX` / `scrollDeltaX` / phase / continuous は生成済みだった。
- Reference Target App では `postToPid` 経路で `captureSourceCounts` に `sendEvent` と `localMonitor` が出た。
- Safari では、実カーソルを Web content 上へ移し、AX hit test が `AXWebArea` / `AXScrollArea` を返す状態でも、CGEvent 合成 scrollWheel 単体では `scrollX` / `scrollY` が変化しなかった。
- document の `maxX=3544` を確認した検証ページで、AX horizontal scrollbar value を `0.5` に設定すると `scrollX=1772` へ変化した。
- 同じ検証ページで、実装後の `system-test run --scenario horizontal-scroll --target safari --amount 1600 --steps 32` は `scrollX=0` から `scrollX=1272` へ変化した。
- 同じ検証ページで、実装後の `generate-scroll --mode horizontal --x -1600 --steps 32` は `scrollX=1272` から `scrollX=0` へ戻した。
- 2026-07-10 の追加検証で、実カーソルが Web content 上にあり通常 window owner が Safari になる状態では、PID override なしの async 経路で横 `scrollX=0 -> 1609`、縦 `scrollY=0 -> 1675`、斜め負方向で `scrollX=0 / scrollY=0` への復帰を確認した。
- Codex window が通常 window target を覆う状態では、対象を `--post-to-pid <Safari PID>` で固定して同じ async AX 配送を再検証した。Safari サイドバーを閉じて実カーソル下を Web content にした `maxX=2876 / maxY=3350` のページで、横 32 step は `scrollX=0 -> 1438`、縦 32 step は `scrollY=0 -> 1675`、斜め負方向 32 step は `scrollX=0 / scrollY=0` へ復帰した。final6 `.app` の各 process の wall time は 0.37〜0.38 秒で、31 step の interval 約 0.25 秒と起動時間を含む。
- window target 最適化前の `artifacts/completion/2026-07-10/pr101-ax-delivery-final3` は、Spaces p95 8.04ms、gesture-wheel p95 8.37ms で 8ms 基準を超えた。生ログから、Spaces でも不要な window list 探索を行い、通常スクロールも同じ座標で step ごとに window list を再取得していたことを特定したため、基準を緩めず配送先探索を修正した。
- 最終修正後の `artifacts/completion/2026-07-10/pr101-ax-delivery-final6` では target log 5シナリオと runtime performance 3シナリオが全件成功した。schema 2 の provisional / completion 解決後の `deferredDeliveryRecordCount` は全て 0、tap-to-delivery-finished p95 は Spaces 0.10ms、gesture-wheel 1.76ms、gesture-wheel-then-kill-switch 1.73ms だった。この値は AppKit 受信、Safari 画面反映、32 step の wall time を含まない。
- AX scrollbar はピクセル単位ではなく 0...1 の正規化値を公開するため、CGEvent の pixel delta と完全一致させる完了条件にはしない。Safari / WebView 系 Web content では、動かない CGEvent よりも保守的に画面反映できることを優先する。
- computer-use のネイティブ vertical scroll は `scrollY=0` から `scrollY=816` へ変化したため、ページ自体のスクロール可否ではなく CGEvent 合成 scroll の Safari 反映差分である。
- 検証中、ポインタ直下に `UserNotificationCenter` と `universalAccessAuthWarn` が重なるケースがあり、画面挙動検証では `CGEvent(source: nil)?.location` と `AXUIElementCopyElementAtPosition` で実カーソル下の対象を確認する必要がある。

## 影響

- 通常スクロール系は、前面アプリではなくポインタ直下 window owner へ配送するため、ユーザーのマウス操作に近い対象選択になる。
- Spaces の `.forcedHorizontal` は pointer window を配送先に使わないため、不要な window list 探索を行わない。通常スクロールは同じ座標の短期 target cache により、連続 step ごとの window list 再取得を避ける。
- AX fallback は `AXWebArea` に限定し、要求軸を処理できた場合は CGEvent を投稿しないため、CGEvent と AX の二重スクロールを避ける。
- 複数軸の途中 set 失敗では適用済み軸を rollback する。rollback 自体が失敗した場合は部分 AX 適用へ CGEvent を重ねず、target cache を破棄して次の入力で再解決する。
- AX fallback が全体 timeout、対象 scrollbar 不在、権限不足、set 失敗で成立しない場合は既存の CGEvent 投稿経路へ戻る。対象 scrollbar を解決済みで上下限に達した軸は handled とし、CGEvent を重ねない。
- 通知や権限 overlay が存在しても、通常 window owner PID と異なる AX hit-test 結果は補助経路の探索起点にしない。
- 自動化ホスト自身が最前面 window になる場合は、診断用 PID override で対象 Web content を固定し、runtime の通常対象選択と AX 配送自体の証跡を分ける。
- `AXWebArea` 以外で追加補助が必要になった場合は、個別アプリ分岐ではなく、公開 AX capability や実デバイス証跡を根拠に追加方針を決める。
- Safari Web content の縦横スクロールは、人間のトラックパッド操作に頼らず computer-use と AX 状態読み取りで画面反映を機械確認できる。
