# ADR-0014: キルスイッチ dry-run のショートカット機械判定

- 状態: 採択
- 日付: 2026-07-09

## 背景

キルスイッチは、誤爆や暴走時に即座にジェスチャー生成と慣性を止める最後の安全弁である。
`system-test run --scenario kill-switch --dry-run --log-json` は未生成のキーイベント列を保存できるが、単に key event が存在するだけでは `Control + Option + Command + G` が生成されている証跡として弱い。

## 決定

- `analyze-log` に `--assert-kill-switch-shortcut` を追加する。
- この assertion は、未生成の `keyDown` と `keyUp` があり、どちらも keyCode 5、かつ Control / Option / Command の modifier を含む場合だけ成功する。
- `scripts/collect-completion-evidence.sh` と CI は、kill-switch dry-run 後に `analyze-log --json --assert-kill-switch-shortcut` を実行する。
- daemon の emergency stop は、進行中ジェスチャーを `.cancelled` コマンドとして処理し、action executor と慣性停止経路を通す。

## 影響

- キルスイッチ dry-run が exact shortcut かどうかを CI と completion evidence の終了コードで確認できる。
- キルスイッチ発火時に recognizer の cancel decision を破棄せず、進行中ジェスチャーへキャンセルフェーズを流せる。
- 実イベント投稿と物理キー操作は引き続き最終証跡として残るが、その前段で計画イベントの取り違えを検出できる。

## 関連

- [Runtime event 証跡の自動化境界](0006-runtime-event-evidence-automation.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [検証手順](../verification.md)
