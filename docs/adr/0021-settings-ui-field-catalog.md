# ADR-0021: 設定UIの製品仕様と編集項目を機械証跡化する

- 状態: 採択
- 日付: 2026-07-09
- 更新日: 2026-07-14

## 背景

設定UIは、buttonごとのGestureClass割り当て、共通gesture設定と安全設定、runtimeから読み取る診断状態を同じ画面で扱う。画面実装だけを正本にすると、割り当てが保存されなかったり、結果別modeやapplication別設定が再導入されたりしてもCIで検出できない。

製品仕様は次のとおりである。

- button 3 / 4 / 5は、それぞれ2本指scroll / swipe、3本指system swipe、4本指system pinchから1つを選択する
- 既定値はbutton 3 = 2本指、button 4 = 3本指、button 5 = 4本指
- 重複割り当てを許可し、無効・未割り当ては設けない
- 上記button未押下時は通常mouse入力

## 決定

- `NapeGestureCore`に、設定UIへ表示する項目を列挙する機械可読catalogを置く。
- catalogは項目ごとに、安定ID、表示名、section、control kind、値の由来、編集可否、設定pathまたは診断keyを持つ。
- 保存対象の値の由来を次の2種類に分ける。
  - `editableGestureSetting`: 3 buttonのGestureClass割り当てと、3本指 / 4本指classに共通する`systemGestureSensitivity`。編集可能。
  - `editableSafetySetting`: 対象device条件、association、証跡出力、安全停止など、入力の意味を変えない運用項目。
- 権限、実行主体、対象device、OS build、contract、fail-closed理由などのruntime statusは保存対象catalogへ含めず、診断値として読み取り専用表示する。
- button割り当てを`gesture.buttonAssignments.button3` / `button4` / `button5`へ保存し、再起動後に復元する。
- catalogとUIに、次を含めない。
  - buttonごとの結果別modeまたは無効化selector
  - 方向別actionまたはbinding
  - application別の有効・無効、感度、割り当て
  - scroll、Space、Mission Control、ページ移動、Zoomなどの結果別action
  - AX、対象PID、keyboard shortcut配送を選ぶ項目
- gesture調整項目は「システムジェスチャー感度」だけとし、GUIでは25%から200%、既定100%のsliderとして表示する。canonical pathは`gesture.systemGestureSensitivity`、保存値は0.25から2.0、既定値1.0とする。物理button番号ではなく選択された3本指 / 4本指classへ適用し、button別、方向別、application別には分けない。
- 単位変換contractそのもの、button別感度、加速度、dead zone、threshold、momentum係数をユーザー編集項目へ追加しない。
- 旧mode、旧action、旧形式のbutton assignment、`dragSensitivity`、`wheelSensitivity`などを含む設定はmigration対象として検出する。旧modeを新割り当てへ推測変換せず、canonical割り当てがない場合は既定値を補う。旧感度を新しい共通感度へ移行せず、新しいcanonical値がない場合は1.0を補って原子的に再保存する。
- core testで次を固定する。
  - 3つの割り当てpopupが存在し、各3 classを選択でき、重複割り当てを保存できる。
  - 表示名、stable ID、設定pathが重複しない。
  - 禁止項目がcatalog、設定schema、GUI descriptorに存在しない。
  - 共通感度が編集可能なsliderとして一つだけ存在し、範囲、既定値、保存pathが一致する。
  - editable項目が設定validationとround-tripに対応する。
  - runtime statusが設定値として保存されない。

## 完成判定への影響

catalog testはUI構造の機械証跡であり、実際の表示、保存、migration、TCC導線、runtime状態の正しさを単独では証明しない。bundle化したGUIのsmoke testとcomputer-use証跡を別に取得する。

## 関連

- [ADR-0049: buttonごとにGestureClassを割り当てる](0049-fixed-button-to-gesture-class-input.md)
- [ゴール要件](../requirements.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [PRレビューチェックリスト](../pr-review-checklist.md)
