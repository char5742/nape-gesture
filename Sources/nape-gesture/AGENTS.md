# Sources/nape-gesture/AGENTS.md

この階層は実行ファイル、CLI、常駐 UI、CGEvent、IOKit、bundle、doctor を担当します。実環境依存の境界なので、安全停止と証跡を常に優先してください。

## Runtime / Event Tap

- 自前生成イベントを再解釈しない。
- 対象外デバイスの通常クリック、通常ドラッグ、通常ホイールを改変しない。
- 元入力抑制、生成イベント投稿、キルスイッチ、復旧処理は、失敗時に安全停止する。
- アクセシビリティ、入力監視、HID probe、対象デバイス不一致は doctor JSON で構造化して説明できる状態を保つ。
- TCC 未許可時は実イベント投稿へ進まず、復旧導線と blocker code を出す。

## CLI / JSON 契約

- `--json`、JSON Lines、schemaVersion、終了コードを変える場合は docs、fixtures、analyzer、CI smoke を同時に更新する。
- `system-test` の dry-run は、実機検証の代替ではなく前段証跡として扱う。
- `analyze-*` は成功すべき fixture と失敗すべき fixture の両方を検証対象にする。

## UI / Bundle

- `.app` は通常 GUI アプリとして起動し、Dock 表示、設定ウィンドウ、メニューバー `NG` 常駐 UI の方針と矛盾させない。
- 権限付与対象は `.app` または実行ファイルとして、doctor / README / Info.plist で矛盾させない。
- 署名、公証、Gatekeeper 評価は、認証操作が残る場合に完了扱いにしない。
