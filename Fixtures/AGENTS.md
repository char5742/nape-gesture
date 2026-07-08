# Fixtures/AGENTS.md

`Fixtures/` 配下は analyzer、dry-run、target log、HID log の回帰証跡です。成功 fixture だけでなく、失敗すべき fixture も仕様を固定する材料として扱います。

## 取り扱い

- fixture の形式、schema、timestamp、stable id、scenario metadata を変える場合は、対応する analyzer と docs を同時に更新する。
- 失敗すべき fixture を成功 fixture に置き換えない。
- 実機ログを追加する場合は、個人情報、不要な device name、ローカルパス、秘密値が含まれないように最小化する。
- Nape Pro 実機や純正トラックパッド由来のログは、取得条件、対象デバイス、権限状態を docs または Issue コメントで追跡できるようにする。
