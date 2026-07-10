## 対応 Issue

- Closes #

## 変更内容

-

## 所有範囲

- 変更した主なファイル:
-

## 検証

- [ ] `swift build --scratch-path .build`
- [ ] `.build/debug/nape-gesture-core-tests`
- [ ] `swift build -c release --scratch-path .build`
- [ ] 必要な dry-run / analyzer / bundle 検証を実行した
- [ ] Safari contract / routing変更時: static checker、WebKit render checker、runtime evaluator testsを実行した
- [ ] Safari実挙動変更時: 同一候補SHAの実artifact evaluatorがexit `0` / passになった、または未実施理由とblockerを記載した

## 実機検証

- [ ] 不要。理由:
- [ ] 必要だが未実施。理由とブロッカー:
- [ ] 実施済み。ログ、対象デバイス、権限状態:

## 入力安全性

- [ ] ジェスチャーボタン未押下時の通常クリック、通常ドラッグ、通常ホイールを壊していない
- [ ] ジェスチャー成立後の元入力漏れを増やしていない
- [ ] 生成イベントの再入力ループを増やしていない
- [ ] キルスイッチまたは安全停止経路を壊していない

## ライセンス確認

- [ ] Mac Mouse Fix のコード、定数、状態遷移、係数をコピーしていない
- [ ] 新しい依存を追加した場合、ライセンスと通知を更新した
