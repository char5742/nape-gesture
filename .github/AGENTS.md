# .github/AGENTS.md

`.github/` 配下は GitHub 上の自動ゲートと作業入力フォームを管理します。CI を弱める変更は、理由と代替検証を明記しない限り行わないでください。

## Workflow

- CI は `pull_request` と `main` push の安全網として維持する。
- 由来ガード、debug build、core tests、dry-run smoke、release build、bundle 検証を削る場合は、同等以上の検証を追加する。
- shell script は実行ビットに依存させず、`sh scripts/<name>.sh` で呼び出す。
- macOS runner や action version を変える場合は、Swift 5.10、macOS 13+、AppKit / IOKit / ApplicationServices の前提に影響がないか確認する。

## Issue / PR Template

- Issue template は目的、変更範囲、完了条件、入力安全性、検証方法が欠けない形にする。
- PR template は対応 Issue、所有範囲、検証、実機検証、入力安全性、ライセンス確認を維持する。
- 実機未検証、TCC 未許可、公証未完了などの外部ブロッカーを、完了済みのように書かせない。
