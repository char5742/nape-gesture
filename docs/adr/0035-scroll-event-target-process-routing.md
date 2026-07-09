# ADR-0035: 通常スクロールはポインタ直下 window owner PID へ投稿する

## 状態

採択

## 背景

`horizontal-scroll` の Safari 実動作確認で、`CGEvent` の水平 delta、phase、precise / continuous field は生成されていたが、Safari Web content の `scrollX` は変化しなかった。
Reference Target App でも `.cghidEventTap` / `.cgSessionEventTap` へ投稿した scrollWheel は `globalMonitor` だけに現れ、前面 AppKit window の通常受信経路に入らなかった。

一方で、`postToPid` で前面またはポインタ直下のアプリへ投稿した scrollWheel は Reference Target App の `sendEvent` / `localMonitor` に入り、`analyze-target-log --assert-has-generated-event --assert-has-foreground-capture` を通過した。

## 決定

- 通常アプリ内スクロールに相当する `.free` / `.horizontal` は、現在のポインタ直下にある layer 0 window を `CGWindowListCopyWindowInfo` で特定し、その window owner PID へ `postToPid` する。
- 同時に `kCGMouseEventWindowUnderMousePointer` と `kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent` を設定し、対象 window をイベントに明示する。
- Spaces 向けの `.forcedHorizontal` は従来どおり `.cghidEventTap` を維持する。macOS のグローバル操作候補と通常アプリ内スクロールは配送経路を分ける。
- Safari Web content は、この経路でも `scrollX` / `scrollY` が変化しないため、CGEvent 合成 scrollWheel の完了条件として扱わない。Safari で完成判定するには別経路または実デバイス操作の証跡が必要である。

## 根拠

- `nape-gesture log --only-generated` では水平 scrollWheel の `pointDeltaX` / `scrollDeltaX` / phase / continuous は生成済みだった。
- Reference Target App では `postToPid` 経路で `captureSourceCounts` に `sendEvent` と `localMonitor` が出た。
- Safari では、実カーソルを Web content 上へ移し、AX hit test が Safari の main content を返す状態でも、`.app` bundle からの `generate-scroll --x ...` / `generate-scroll --y ...` は `scrollX` / `scrollY` を変化させなかった。
- 同じページで computer-use のネイティブ scroll は `scrollY=0` から `scrollY=816` へ変化したため、ページ自体のスクロール可否ではなく CGEvent 合成 scroll の Safari 反映差分である。
- 検証中、ポインタ直下に `UserNotificationCenter` と `universalAccessAuthWarn` が重なるケースがあり、画面挙動検証では `CGEvent(source: nil)?.location` と `AXUIElementCopyElementAtPosition` で実カーソル下の対象を確認する必要がある。

## 影響

- 通常スクロール系は、前面アプリではなくポインタ直下 window owner へ配送するため、ユーザーのマウス操作に近い対象選択になる。
- Safari Web content の横スクロール完了判定は、現時点では `need:human` または別実装の課題として残す。
- 今後 Safari 対応を完了させる場合は、AX scroll、Web content への別プロセス配送、または実デバイス入力に近い HID 経路を別 ADR で採択する。
