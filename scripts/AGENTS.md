# scripts/AGENTS.md

`scripts/` 配下は、CI と完成判定で再実行できる証跡収集・ガードを置く場所です。ローカル環境だけで動く一時スクリプトを正本にしないでください。

## 実装ルール

- POSIX `sh` で動く範囲を基本にする。
- 実行ビットに依存しない。呼び出しは `sh scripts/<name>.sh` に統一する。
- `chmod` を使わない。
- repo root 検出、失敗時の非ゼロ終了、確認すべきログの表示を維持する。
- artifact は `artifacts/` など Git 管理外へ出力し、PR / Issue には要約と保存先を残す。
- 失敗を握りつぶさず、期待失敗と想定外失敗を明確に分ける。

## 変更時の確認

- `sh -n scripts/<name>.sh` で構文確認する。
- 完成証跡スクリプトを変えたら [docs/completion-checklist.md](../docs/completion-checklist.md) と CI の呼び出しを確認する。
- 由来ガードを変えたら README、`THIRD_PARTY_NOTICES.md`、PR template、review checklist との整合性を確認する。
