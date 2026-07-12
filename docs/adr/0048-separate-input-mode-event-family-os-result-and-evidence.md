# ADR-0048: 入力mode・event family・OS/App結果・証跡状態を分離する

- 状態: 採択
- 日付: 2026-07-12

## 背景

方向別bindingを廃止した後も、`Scroll & Navigate`、`Spaces & Mission Control`、`Zoom`というmode名には、Nape Gestureが選ぶ入力変換と、macOSまたは前面applicationが最終的に解釈する結果が混在していた。

この混在には次の問題がある。

- 2次元scrollのX成分で横scrollが発生することと、`NavigationSwipe`候補を生成できることと、applicationでページ戻る/進むが成立することを同じ「Navigate」として扱ってしまう。
- `DockSwipe`を投稿することと、Spaces切替、Mission Control、App Exposeのどれが発生したかを同じ製品機能として扱ってしまう。
- `magnification` eventを投稿することと、applicationがZoomとして表示を変えたことを同一視してしまう。
- candidate eventを構築できること、製品runtimeから到達できること、純正trackpad contractが確定したこと、OS/App結果を実測したこと、Nape Proで確認したことの区別が曖昧になる。

## 決定

### 1. ユーザー向け入力mode

button 3 / 4 / 5に設定するmodeは、Nape Gestureがmouse入力をどのtrackpad相当入力系列へ変換するかだけを表す。

- `none`: 通常mouse入力として通過させる。
- `2本指スクロール / スワイプ`（設定値`twoFingerSwipe`）: 押下中のmouse moveとwheelを、連続した2次元scroll系列へ渡す。
- `システムスワイプ`（設定値`systemSwipe`）: 押下中に最初に成立したmouse moveまたはwheelを、連続した`DockSwipe`系列へ渡す。
- `ピンチ`（設定値`pinch`）: 押下中に最初に成立したmouse moveまたはwheelを、連続した`magnification`系列へ渡す。

既定はbutton 3=`2本指スクロール / スワイプ`、button 4=`システムスワイプ`、button 5=`ピンチ`とする。旧設定値`scrollAndNavigate`、`spacesAndMissionControl`、`zoom`は読込時に新modeへ移行する。旧keyがなく旧mode値だけが残る設定もcanonical rewrite対象として検出し、同じ設定値を保持したまま原子的に再保存して旧結果名を永続化しない。

mode名はOS/App結果を保証しない。方向別binding、application別binding、`pageBack`、`spaceLeft`、`missionControl`、`zoomIn`のような結果別actionを製品surfaceへ置かない。

### 2. 低レベルevent familyと製品runtime capability

低レベルevent familyは互換adapterと証跡で使う技術用語であり、ユーザー向け機能名ではない。

25F80の製品runtime capabilityは次の3経路とする。

- `scroll`: `2本指スクロール / スワイプ`modeの製品経路。X / Y delta、phase、必要な場合のmomentum、companion eventを保持する。
- `DockSwipe`: `システムスワイプ`modeの製品経路。progress、phase、axis、velocity、terminalを保持する。
- `magnification`: `ピンチ`modeの製品経路。signed scale delta、phase、velocity、terminalを保持する。

`NavigationSwipe`は、純正trackpadの2本指系列で観測された低レベル候補である。fixture、analyzer、session modelに観測候補として保持するが、製品event builder、独立したユーザー向けmode、独立した製品機能、製品runtimeの必須またはsupported capabilityには数えない。ページ戻る/進むの完成根拠にも使わない。

未知OS build、登録fixture不一致、contract不一致では従来どおりfail closedにする。3経路のうち設定で有効なmodeが要求する経路を生成できない場合、event tapと入力抑制を開始しない。

### 3. macOS / applicationが解釈する結果

次はNape Gestureのmodeまたはevent familyではなく、system-wide eventを受け取ったmacOSまたは前面applicationで観測する結果である。

- 縦scroll、横scroll、nested scroll targetの選択
- applicationのページ戻る/進む、履歴移動、AppKit `swipe`受信
- Space切替、Mission Control、App Expose
- applicationのZoom、キャンバス拡縮、AppKit `magnify`受信

これらはscenario名と完成判定にだけ使う。同じ低レベルevent系列でも、OS設定、前面application、target、現在の画面状態により結果が異なり得るため、Nape Gestureが結果を選択または保証する表現を使わない。

横scrollは独立familyではなく`scroll`のX成分による観測結果である。ページ戻る/進むは`NavigationSwipe`という独立製品機能ではなく、2本指系列をapplicationが解釈した結果として検証する。Space切替、Mission Control、App Exposeは`DockSwipe`の結果、Zoomは`magnification`の結果として、event contractとは別に記録する。

### 4. 証跡状態

完成状態は少なくとも次を分けて記録する。

- `実装存在`: 型、builder、adapterまたは診断経路が存在する。
- `自動生成検証済み`: event type、field、phase、session、terminalを自動テストした。
- `純正contract確定`: 純正trackpad物理capture、manifest、登録fixture、SHA、OS buildを照合した。
- `OS/App結果確認済み`: system-wide投稿後のtarget logと画面結果をscenario単位で確認した。
- `Nape Pro実機確認済み`: Nape Pro入力から生成、OS/App結果、体感、通常入力復帰まで確認した。

`supported`は製品runtimeから到達でき、現在のOS buildで必要なadapter前提を満たす低レベル経路にだけ使用する。その内訳を`confirmedFamilies`と`trialFamilies`に分け、純正contract確定と試用経路を混同しない。低レベル候補の観測だけで`NavigationSwipe`をsupportedに数えない。

historical evidenceに残る旧mode名、旧action名、旧shortcut scenario名は当時の記録として改変しない。現行文書から参照するときは「旧称」「移行前診断scenario」「結果名」のいずれかを注記し、現在のmodeまたはruntime capabilityと混同しない。

## 影響

- README、requirements、verification、completion checklist、release条件は4層を分けて記述する。
- button modeの表示と設定値は`none`、`twoFingerSwipe`、`systemSwipe`、`pinch`へ統一する。
- runtime性能schemaは入力modeと実出力familyを別々に記録し、欠落familyをmodeから推測しない。
- `NavigationSwipe`のcandidate観測、fixture検証、session modelは保持するが、製品event builderとruntime capabilityからは除外する。製品runtime capabilityは`scroll`、`DockSwipe`、`magnification`の3経路とする。
- completion checklistは低レベル経路の契約と、OS/App結果scenarioを別行で管理する。
- 旧ADRの当時の判断とhistorical evidenceは削除せず、本ADRによる置換範囲を冒頭注記で示す。

## 関連

- [ADR-0036: trackpad driver上位出力eventを再現する](0036-emulate-trackpad-driver-output-events.md)
- [ADR-0046: 残るtrackpad familyを25F80試用出力として有効化する](0046-trial-output-for-remaining-trackpad-families.md)
- [ADR-0047: 方向別bindingを廃止しボタンごとのtrackpad modeへ接続する](0047-fixed-continuous-2d-trackpad-input.md)
- [ゴール要件](../requirements.md)
- [完成判定チェックリスト](../completion-checklist.md)
