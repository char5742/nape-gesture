# Tests/AGENTS.md

`Tests/` 配下は Swift Package Manager の標準テストを追加する場合の置き場です。現状の主要ゲートは `Sources/nape-gesture-core-tests/` の executable test なので、追加時は CI と検証文書も合わせて整備します。

## 追加方針

- 新しい test target を追加する場合は `Package.swift`、CI、PR review checklist の実行コマンドを更新する。
- 実機、TCC、現在時刻、ホームディレクトリ、ローカル絶対パスへ依存しない。
- 既存の executable test と重複するだけのテストを増やさず、失敗時の診断やカバレッジが明確に増える形にする。
