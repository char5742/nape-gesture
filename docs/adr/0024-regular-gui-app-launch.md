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
- `gui-smoke --config <path> --json --assert` は、runtime を開始せずに `.app` 実行主体で AppKit 内の `.regular` activation policy、設定ウィンドウ、status item `NG`、通常アプリメニュー、status menu の生成契約を機械検査する。`--config` 未指定時は一時 config を使い、ユーザーの通常設定へ書き込まない。
- CI は bundle 検証と GUI smoke を分ける。active macOS console session がない runner では GUI smoke を warning 付きで skip し、completion evidence では active GUI session 上の `collect-completion-evidence.sh` を hard evidence として採用する。
- Dock 表示は computer-use と System Events の Dock process 観測で代替できる限り `need:human` にしない。Info.plist、起動コード、AppKit 内 GUI smoke、AX 観測で機械確認できる範囲には使わない。

## 影響

- 起動直後に設定画面が見えるため、`.app` が起動しているか分からない状態を避けられる。
- メニューバー常駐 UI は残るため、実行中の開始、停止、緊急停止、権限確認は従来どおり使える。
- 初回起動のウィンドウ表示と status item `NG` の AppKit 契約は Info.plist、起動コード、`gui-smoke --config <path> --json --assert` で固定する。実メニューバー上のクリック操作が必要な場合は computer-use で確認する。SystemUIServer の Accessibility name に status item が露出しない場合でも、それだけで status item 不在とは判定しない。

## 関連

- [doctor TCC 権限付与対象の構造化](0020-doctor-tcc-permission-target.md)
- [設定 UI 編集項目 catalog の機械証跡化](0021-settings-ui-field-catalog.md)
- [repo-local 由来ガード](0023-repo-local-provenance-guard.md)
- [GUI 権限復旧導線の表示契約](0025-gui-permission-recovery-actions.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [リリース手順](../release.md)
