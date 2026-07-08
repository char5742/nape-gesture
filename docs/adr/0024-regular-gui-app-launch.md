# ADR-0024: 通常 GUI アプリとして起動する

- 状態: 採択
- 日付: 2026-07-09

## 背景

`.app` バンドルは日常利用の入口であり、ユーザーが起動したときに GUI アプリとして見える必要がある。
従来は `LSUIElement=true` のアクセサリアプリとしてメニューバーに常駐し、Dock に表示されず、起動時にメインウィンドウを開かなかった。
この状態では、初回設定、権限確認、起動中かどうかの把握がメニューバー項目の発見に依存する。

## 決定

- `.app` の `LSUIElement` は `false` にする。
- `app` command は `NSApplication` の activation policy を `.regular` にする。
- `.app` を引数なしで起動した場合、メニューバーの状態メニューを維持しつつ、設定ウィンドウを前面に開く。
- Dock アイコンから再度開いた場合、表示中ウィンドウがなければ設定ウィンドウを再表示する。
- CLI subcommand は維持する。`nape-gesture app` は GUI アプリモードの起動コマンドとして扱う。
- bundle 検証、CI、completion evidence は `CFBundleIdentifier`、`CFBundleExecutable`、`CFBundleName`、`CFBundleDisplayName` に加えて `LSUIElement=false` を確認する。
- `need:human` は、最終的な Dock 表示、設定ウィンドウ前面表示、メニューバー `NG` 操作を実 `.app` で目視確認する場合だけに使う。Info.plist や起動コードで機械確認できる範囲には使わない。

## 影響

- 起動直後に設定画面が見えるため、`.app` が起動しているか分からない状態を避けられる。
- メニューバー常駐 UI は残るため、実行中の開始、停止、緊急停止、権限確認は従来どおり使える。
- 初回起動のウィンドウ表示そのものは機械的に Info.plist と起動コードで固定できるが、最終的な画面操作確認は macOS UI 操作として completion checklist に残す。

## 関連

- [doctor TCC 権限付与対象の構造化](0020-doctor-tcc-permission-target.md)
- [設定 UI 編集項目 catalog の機械証跡化](0021-settings-ui-field-catalog.md)
- [repo-local 由来ガード](0023-repo-local-provenance-guard.md)
- [GUI 権限復旧導線の表示契約](0025-gui-permission-recovery-actions.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [リリース手順](../release.md)
