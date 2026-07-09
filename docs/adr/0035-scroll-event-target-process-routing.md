# ADR-0035: 通常スクロールはポインタ直下 window owner PID と AX horizontal fallback で配送する

## 状態

採択

## 背景

`horizontal-scroll` の Safari 実動作確認で、`CGEvent` の水平 delta、phase、precise / continuous field は生成されていたが、Safari Web content の `scrollX` は変化しなかった。
Reference Target App でも `.cghidEventTap` / `.cgSessionEventTap` へ投稿した scrollWheel は `globalMonitor` だけに現れ、前面 AppKit window の通常受信経路に入らなかった。

一方で、`postToPid` で前面またはポインタ直下のアプリへ投稿した scrollWheel は Reference Target App の `sendEvent` / `localMonitor` に入り、`analyze-target-log --assert-has-generated-event --assert-has-foreground-capture` を通過した。
Safari Web content では、document の `maxX` がある検証ページでも CGEvent 合成 scrollWheel は水平 scroll root を動かさなかったが、`AXWebArea` ancestor から horizontal scrollbar value を設定すると `scrollX` が変化した。

## 決定

- 通常アプリ内スクロールに相当する `.free` / `.horizontal` は、現在のポインタ直下にある layer 0 window を `CGWindowListCopyWindowInfo` で特定し、その window owner PID へ `postToPid` する。
- 同時に `kCGMouseEventWindowUnderMousePointer` と `kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent` を設定し、対象 window をイベントに明示する。
- `.horizontal` は、ポインタ直下の AX element から ancestor を辿り、`AXWebArea` 配下の `AXHorizontalScrollBar` が見つかる場合は CGEvent を投稿せず normalized `AXValue` を delta に応じて更新する。
- AX fallback はアプリ名で分岐しない。Safari 固有対応ではなく、Accessibility が公開する Web content の水平 scrollbar への補助経路として扱う。
- Spaces 向けの `.forcedHorizontal` は従来どおり `.cghidEventTap` を維持する。macOS のグローバル操作候補と通常アプリ内スクロールは配送経路を分ける。
- Safari Web content の完成判定では、CGEvent 合成 scrollWheel 単体ではなく、AX fallback 後の `scrollX` 変化を画面反映証跡として採用する。

## 根拠

- `nape-gesture log --only-generated` では水平 scrollWheel の `pointDeltaX` / `scrollDeltaX` / phase / continuous は生成済みだった。
- Reference Target App では `postToPid` 経路で `captureSourceCounts` に `sendEvent` と `localMonitor` が出た。
- Safari では、実カーソルを Web content 上へ移し、AX hit test が `AXWebArea` / `AXScrollArea` を返す状態でも、CGEvent 合成 scrollWheel 単体では `scrollX` / `scrollY` が変化しなかった。
- document の `maxX=3544` を確認した検証ページで、AX horizontal scrollbar value を `0.5` に設定すると `scrollX=1772` へ変化した。
- 同じ検証ページで、実装後の `system-test run --scenario horizontal-scroll --target safari --amount 1600 --steps 32` は `scrollX=0` から `scrollX=1272` へ変化した。
- 同じ検証ページで、実装後の `generate-scroll --mode horizontal --x -1600 --steps 32` は `scrollX=1272` から `scrollX=0` へ戻した。
- AX scrollbar はピクセル単位ではなく 0...1 の正規化値を公開するため、CGEvent の pixel delta と完全一致させる完了条件にはしない。Safari Web content では、動かない CGEvent よりも保守的に画面反映できることを優先する。
- computer-use のネイティブ vertical scroll は `scrollY=0` から `scrollY=816` へ変化したため、ページ自体のスクロール可否ではなく CGEvent 合成 scroll の Safari 反映差分である。
- 検証中、ポインタ直下に `UserNotificationCenter` と `universalAccessAuthWarn` が重なるケースがあり、画面挙動検証では `CGEvent(source: nil)?.location` と `AXUIElementCopyElementAtPosition` で実カーソル下の対象を確認する必要がある。

## 影響

- 通常スクロール系は、前面アプリではなくポインタ直下 window owner へ配送するため、ユーザーのマウス操作に近い対象選択になる。
- `.horizontal` の AX fallback は `AXWebArea` に限定し、処理できた場合は CGEvent を投稿しないため、CGEvent と AX の二重スクロールを避ける。
- `AXWebArea` 以外で追加補助が必要になった場合は、個別アプリ分岐ではなく、公開 AX capability や実デバイス証跡を根拠に追加方針を決める。
- Safari Web content の横スクロールは、人間のトラックパッド操作に頼らず computer-use と AX 状態読み取りで画面反映を機械確認できる。
