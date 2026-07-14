# ADR-0021: 設定UIの製品仕様と編集項目を機械証跡化する

- 状態: 採択
- 日付: 2026-07-09
- 更新日: 2026-07-12

## 背景

設定UIは、製品仕様として固定された値、ユーザーが編集できる安全設定、runtimeから読み取る診断状態を同じ画面で扱う。画面実装だけを正本にすると、buttonとGestureClassの固定対応が誤って編集可能になったり、結果別modeやapplication別設定が再導入されたりしてもCIで検出できない。

固定の製品仕様は次のとおりである。

- button 3 = 2本指scroll / swipe相当
- button 4 = 3本指system swipe相当
- button 5 = 4本指system pinch相当
- 上記button未押下時は通常mouse入力

## 決定

- `NapeGestureCore`に、設定UIへ表示する項目を列挙する機械可読catalogを置く。
- catalogは項目ごとに、安定ID、表示名、section、control kind、値の由来、編集可否、設定pathまたは診断keyを持つ。
- 値の由来を最低限、次の3種類に分ける。
  - `fixedProductMapping`: button 3 / 4 / 5とGestureClassの固定対応。読み取り専用。
  - `editableSafetySetting`: 対象device条件、association、証跡出力、安全停止など、入力の意味を変えない運用項目。
  - `runtimeStatus`: 権限、実行主体、対象device、OS build、contract、fail-closed理由など。読み取り専用。
- 固定button対応を保存設定の選択値にしない。既定値ではなく製品定数として扱う。
- catalogとUIに、次を含めない。
  - buttonごとの結果別modeまたは無効化selector
  - 方向別actionまたはbinding
  - application別の有効・無効、感度、割り当て
  - scroll、Space、Mission Control、ページ移動、Zoomなどの結果別action
  - AX、対象PID、keyboard shortcut配送を選ぶ項目
- 単位変換contract、感度、加速度、dead zone、threshold、momentum係数をユーザー編集項目へ追加しない。単位変換はOS buildとfixtureで固定し、runtime statusとして表示する。
- 旧mode、旧action、旧button assignmentを含む設定はmigration対象として検出し、固定対応だけを前提とするcanonical設定へ原子的に再保存する。
- core testで次を固定する。
  - 3つの固定対応が重複なく存在し、編集不能である。
  - 表示名、stable ID、設定pathが重複しない。
  - 禁止項目がcatalog、設定schema、GUI descriptorに存在しない。
  - editable項目が設定validationとround-tripに対応する。
  - runtime statusが設定値として保存されない。

## 完成判定への影響

catalog testはUI構造の機械証跡であり、実際の表示、保存、migration、TCC導線、runtime状態の正しさを単独では証明しない。bundle化したGUIのsmoke testとcomputer-use証跡を別に取得する。

## 関連

- [ADR-0049: buttonを固定GestureClassへ接続する](0049-fixed-button-to-gesture-class-input.md)
- [ゴール要件](../requirements.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [PRレビューチェックリスト](../pr-review-checklist.md)
