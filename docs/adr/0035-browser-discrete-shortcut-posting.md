# ADR-0035: ブラウザ離散操作はメニュー互換ショートカットを明示 modifier 列で投稿する

- 状態: 採択
- 日付: 2026-07-10

## 背景

Issue #10 のページ戻る / 進む / ズームは、dry-run の keyCode が正しくても Safari の画面挙動へ反映されない場合があった。
特に `Command + Left` / `Command + Right` は Safari の履歴移動として安定せず、`Command + =` も Safari の `拡大` メニュー項目とは一致しなかった。
また、権限付与対象は実利用する `.app` bundle であり、debug CLI や一時 Swift バイナリの成功だけを最終証跡にすると TCC 主体がずれる。

## 決定

- ページ戻る / 進むは Safari のメニュー互換ショートカットである `Command + [` / `Command + ]` を使う。
- ズームインは `Command + +` として扱い、US 物理キー上では `Command + Shift + =` を投稿する。ズームアウトは `Command + -` を使う。
- 離散ショートカット投稿は、対象キーへ modifier flags を付けるだけでなく、修飾キーの keyDown / keyUp を明示生成する。
- key event は `.cgSessionEventTap` へ投稿し、修飾キーと本キーの間に短い間隔を入れる。Safari のページズームでは、連続投稿が速すぎると片方向だけ取りこぼす場合がある。
- `system-test run --dry-run --log-json` と `analyze-log --assert-system-scenario` は、修飾キー down/up を含む実送信相当の完全列を検証する。
- 実アプリ挙動の証跡は、権限付与済みの `.build/NapeGesture.app/Contents/MacOS/nape-gesture` など実利用主体で取得する。
- `system-test --target safari` は対象アプリを開くだけでなく、`frontmostApplication` が Safari になるまで待ってから投稿する。

## 実測メモ

2026-07-10 の権限付与済み環境で、`.build/NapeGesture.app/Contents/MacOS/nape-gesture` から Safari へ投稿して次を確認した。

- `page-back`: `auto2.html?token=1783625923` / `auto-page-2` から `auto1.html?token=1783625923` / `auto-page-1` へ遷移。
- `page-forward`: `auto1.html?token=1783625923` / `auto-page-1` から `auto2.html?token=1783625923` / `auto-page-2` へ遷移。
- `zoom-out`: `inner-width: 655 dpr: 3` から `inner-width: 786 dpr: 2.5` へ変化。
- `zoom-in`: `inner-width: 786 dpr: 2.5` から `inner-width: 655 dpr: 3` へ変化。

横スクロールは同じ Safari Web content で CGEvent 合成 scrollWheel 単体では `scrollX` が変化しなかったため、離散ショートカットとは別論点として切り出した。後続の [ADR-0036](0036-scroll-event-target-process-routing.md) で `AXWebArea` scrollbar 経路を補助実装として採用し、初期確認では `scrollX=0 -> 1272 -> 0`、最終確認では通常経路 `0 -> 1609` と診断 override `0 -> 1438` の画面反映を確認した。

## 影響

- `page-back` / `page-forward` / `zoom-in` / `zoom-out` の dry-run 証跡は、実送信の modifier key event 数と一致する。
- Safari などブラウザ向けの離散操作は、矢印キー由来の履歴移動ではなくメニュー互換ショートカットを基準にする。
- TCC 主体の取り違えを避けるため、実アプリ証跡では debug CLI の成功だけで完了扱いにしない。
- 横スクロールの画面反映は、ページ戻る / 進む / ズームの離散ショートカット方針とは分離し、ADR-0036 の通常スクロール配送方針で扱う。

## 関連

- [ADR-0010: 離散割り当ての System Behavior Test dry-run 証跡](0010-system-test-discrete-assignment-dry-run-evidence.md)
- [ADR-0017: System Behavior Test dry-run のシナリオ別機械判定](0017-system-test-scenario-assertion.md)
- [ADR-0020: doctor TCC 権限付与対象の構造化](0020-doctor-tcc-permission-target.md)
- [検証方針](../verification.md)
- [完成判定チェックリスト](../completion-checklist.md)
