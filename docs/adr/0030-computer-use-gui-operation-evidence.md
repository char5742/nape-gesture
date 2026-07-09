# ADR-0030: Computer Use で GUI 操作と画面証跡を前進させる

- 状態: 採択
- 日付: 2026-07-09

## 背景

Nape Gesture の完成判定には、通常 GUI アプリの起動、設定ウィンドウ、メニューバー `NG`、System Settings の権限導線、TCC 反映後の再実行など、CLI だけでは確認しにくい macOS UI 操作が含まれる。
これまでは一部を `need:human` として扱っていたが、computer-use が使える環境では、画面確認、クリック、入力、スクロール、スクリーンショット取得をエージェント側で実行できる。

一方で computer-use はユーザーのローカル GUI を直接操作するため、OS セキュリティ設定、ファイル操作、第三者サービスへの送信などは安全確認が必要である。

## 決定

- 専用 CLI、GitHub / browser / app plugin、スクリプトで完結する作業はそれらを優先する。
- ローカル Mac アプリ UI の読み取り、クリック、入力、スクロール、ドラッグ、画面証跡取得が必要な場合は computer-use を積極的に使う。
- GUI アプリの起動確認、設定ウィンドウ表示、メニューバー `NG` 操作、System Settings pane の表示確認、スクリーンショット取得は computer-use の対象にする。
- TCC、アクセシビリティ、入力監視、VPN、OS セキュリティなどの local system settings を computer-use で変更する直前には、必ずユーザーへ具体的な操作内容とリスクを説明して確認を取る。
- パスワード、API key、OTP、個人情報などの sensitive data を UI へ入力または第三者へ送信する場合は、computer-use 確認ポリシーに従い、具体的なデータと送信先を確認する。
- computer-use で操作できる作業は、確認待ちや単なる目視確認として `need:human` にしない。物理デバイス操作、ユーザー本人しか通せない認証、秘密情報入力など、エージェントが代替できない作業だけを `need:human` として残す。
- computer-use の画面証跡は、ログ、`doctor --json`、runtime evidence、CI の代替にしない。完成判定では画面証跡と機械証跡を対応づける。

## 影響

- `.app` の Dock 表示、設定ウィンドウ、メニューバー操作、権限導線の確認を人間作業へ投げる前に進めやすくなる。
- `need:human` は、GUI 目視一般ではなく、物理操作や user-only 認証など最後の手段へさらに絞られる。
- System Settings の最終変更操作は、computer-use で実行可能でも直前確認を挟むため、安全境界を保てる。

## 関連

- [ADR-0002: GitHub labels / milestones / Issue close 方針](0002-github-labels-milestones-and-issue-close.md)
- [ADR-0006: Runtime event 証跡の自動収集と人間作業境界](0006-runtime-event-evidence-automation.md)
- [ADR-0024: 通常 GUI アプリとして起動する](0024-regular-gui-app-launch.md)
- [ADR-0025: GUI 権限復旧導線の表示契約](0025-gui-permission-recovery-actions.md)
- [完成判定チェックリスト](../completion-checklist.md)
- [PR レビューチェックリスト](../pr-review-checklist.md)
