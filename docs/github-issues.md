# nape-gesture Issue 草案

この文書は `char5742/nape-gesture` に作成する Issue の初期セットである。
メインスレッドは Issue 整理、PR レビュー、マージ判断に集中し、実装はサブエージェントに分割する。

## ラベル案

- `area:core`
- `area:runtime`
- `area:hid`
- `area:verification`
- `area:ui`
- `area:release`
- `area:docs`
- `type:feature`
- `type:bug`
- `type:research`
- `type:qa`
- `priority:p0`
- `priority:p1`
- `parallel:ready`
- `blocked:external`

## Milestone 1: リポジトリ移行と品質ゲート

### Issue 1: リポジトリ名を nape-gesture として公開できる状態にする

Labels: `area:docs`, `area:release`, `priority:p0`

目的:
`nape-gesture` として始まったローカル成果を、`nape-gesture` リポジトリとして扱える状態にする。

完了条件:

- GitHub 上に `char5742/nape-gesture` が存在する
- 初回コミットが `main` に push 済み
- README の先頭でプロダクトの目的が Nape Pro 向けであることが分かる
- 旧名 `nape-gesture` が意図せずユーザー向け名称として残っていない箇所を棚卸し済み
- 旧名を残す箇所は互換性または後続 Issue として理由が明記されている

依存関係:
GitHub 認証または GitHub App で新規 repository 作成が可能であること。

並列化:
命名棚卸しと README 更新は実装作業と並列可能。

### Issue 2: CI で debug / release build とコアテストを必須化する

Labels: `area:release`, `type:feature`, `priority:p0`, `parallel:ready`

目的:
PR レビューとマージ判断を人手のローカル実行に依存しない状態にする。

完了条件:

- GitHub Actions で `swift build` が成功する
- GitHub Actions で `swift build -c release` が成功する
- `nape-gesture-core-tests` が CI で実行される
- CI 失敗時に PR をマージしない運用が文書化されている
- macOS runner 上で権限依存テストを実行しない範囲が明確

依存関係:
Issue 1。

並列化:
リポジトリ作成後すぐに着手可能。

### Issue 3: PR レビュー用チェックリストを整備する

Labels: `area:docs`, `type:qa`, `priority:p0`, `parallel:ready`

目的:
メインスレッドがレビューとマージに集中できるよう、レビュー観点を固定する。

完了条件:

- 変更種別ごとの確認項目が `docs/pr-review-checklist.md` にある
- 入力抑制、通常入力通過、生成イベント再入力防止、権限導線、実機検証の観点が含まれる
- どの変更に実機検証が必須かが明記されている
- レビューで不足証跡を要求する基準が明記されている

依存関係:
なし。

並列化:
他の実装 Issue と完全に並列可能。

## Milestone 2: Nape Pro 識別と入力安全性

### Issue 4: Nape Pro の HID 識別ログを取得し、対象 matcher を確定する

Labels: `area:hid`, `type:research`, `priority:p0`, `blocked:external`

目的:
対象デバイスを推測ではなく実機ログで識別する。

完了条件:

- `devices --all --json` の Nape Pro 候補ログが保存されている
- `hid-log` で移動、ホイール、ジェスチャーボタンの usage と値域が分かる
- `analyze-hid-log` の出力から設定例を作成済み
- `requireMatchingTargetDevice: true` で `matchedTargetDeviceCount >= 1` になる
- Nape Pro 未接続時に安全停止することを確認済み

依存関係:
実機 Nape Pro と入力監視権限。

並列化:
実機が必要なため、コード実装とは分離して進める。

### Issue 5: イベントタップ入力と HID 対象デバイスの紐づけを厳密化する

Labels: `area:runtime`, `area:hid`, `type:feature`, `priority:p0`

目的:
対象デバイスの直近入力だけをジェスチャー処理し、他のマウスやトラックパッド入力を巻き込まない。

完了条件:

- 対象 HID 入力の直近時刻とイベントタップ入力の association window が設定可能
- ジェスチャーボタン押下中は対象入力として継続処理される
- ボタン解放後は一定時間を超えると通常入力へ戻る
- 対象外デバイスのクリック、ドラッグ、ホイールを改変しないテストがある
- Nape Pro 実機ログで association window の初期値が妥当化されている

依存関係:
Issue 4。

並列化:
コア状態機械のテスト拡張は Issue 4 と一部並列可能。

### Issue 6: ジェスチャー成立後の元入力抑制を実機ログで検証する

Labels: `area:runtime`, `area:verification`, `type:qa`, `priority:p0`

目的:
ジェスチャー中の元ボタン押下、ドラッグ、ホイールが前面アプリへ漏れないことを確認する。

完了条件:

- `Reference Target App` でジェスチャー中の元入力漏れを記録できる
- ジェスチャー未成立の微小揺れでは必要な抑制だけが行われる
- ジェスチャー成立後は元イベントが AppKit に届かない
- ボタン解放直後に通常クリック、通常ドラッグ、通常ホイールへ戻る
- 失敗時のログ例と修正方針が文書化されている

依存関係:
Issue 4、Issue 5。

並列化:
検証手順の整備は実装と並列可能。

## Milestone 3: トラックパッド級ジェスチャー生成

### Issue 7: スクロールと慣性フェーズの生成ログを純正入力と比較可能にする

Labels: `area:core`, `area:verification`, `type:feature`, `priority:p0`

目的:
通常スクロールの `scrollPhase` と慣性の `momentumPhase` を混同せず、純正トラックパッドとの差分を説明できるようにする。

完了条件:

- 通常スクロールの `began` / `changed` / `ended` は `scrollPhase` にだけ出る
- 慣性中と慣性終了は `momentumPhase` に出る
- `generate-scroll --dry-run --log-json` が同じ規則で出力する
- `system-test run --dry-run --log-json` が同じ規則で出力する
- コアテストでフェーズ分離が検証されている

依存関係:
なし。

並列化:
完了済み。今後は純正ログとの差分調整に進める。

### Issue 8: 純正トラックパッドログから加速度・しきい値・慣性パラメータを再導出する

Labels: `area:core`, `area:verification`, `type:research`, `priority:p1`

目的:
Mac Mouse Fix の係数を流用せず、実機ログから初期値を説明できるようにする。

完了条件:

- 純正トラックパッドの縦スクロール、横スクロール、Spaces 操作ログがある
- Nape Pro 操作ログがある
- `analyze-log` の統計から deadZone、加速度、慣性初期値の候補が出ている
- 設定値の採用理由が `docs/verification.md` または専用文書に残っている
- 主要パラメータ変更に対する回帰テストがある

依存関係:
Issue 4。

並列化:
ログ取得と解析ロジック改善は分けて進められる。

### Issue 9: Mission Control / Spaces の実機挙動マトリクスを作る

Labels: `area:verification`, `type:research`, `priority:p0`, `blocked:external`

目的:
単なるショートカット送信を最終解にせず、生成スクロール系イベントで macOS がどこまで純正相当に扱うかを実測する。

完了条件:

- Finder と Safari を対象に `space-left` / `space-right` を実測済み
- Mission Control の純正操作ログと生成イベントログを比較済み
- `screen behavior`, `CGEvent log`, `AppKit target log`, `体感差分` が同じシナリオ名で保存されている
- 公開 API の限界がある場合、ログを根拠に説明されている
- 代替操作を使う場合のチューニング値と品質目標がある

依存関係:
アクセシビリティ権限、Issue 7、Issue 8。

並列化:
実機検証担当と生成パラメータ調整担当に分けられる。

### Issue 10: ページ戻る/進む、ズーム、横スクロールの割り当てを実機確認する

Labels: `area:runtime`, `area:verification`, `type:qa`, `priority:p1`

目的:
設定に存在する主要ジェスチャー割り当てが、Safari/Finder/Reference Target App で期待通りに動くことを確認する。

完了条件:

- `pageBack` / `pageForward` が Safari で検証されている
- `zoomIn` / `zoomOut` が対応アプリで検証されている
- `horizontalScroll` が横スクロール可能なビューで検証されている
- 離散アクションは慣性を発生させない
- 生成キーイベントのログと画面挙動が一致している

依存関係:
アクセシビリティ権限、Issue 3。

並列化:
Spaces 検証と並列可能。

## Milestone 4: 常駐アプリ品質

### Issue 11: 権限導線と runtimeIdentity 表示を `.app` 利用前提で固める

Labels: `area:runtime`, `area:ui`, `type:feature`, `priority:p0`

目的:
ユーザーがどの `.app` または実行ファイルに権限を付けるべきか迷わない状態にする。

完了条件:

- `doctor --json` に実利用対象の bundle path、bundle ID、executable path が出る
- 常駐 UI の権限確認に同じ情報が出る
- アクセシビリティ未許可、入力監視未許可の復旧導線が別々に出る
- 権限変更後の再起動または自動再試行が文書化されている
- `.app` での `doctor --probe-hid --json` 証跡がある

依存関係:
Issue 1。

並列化:
UI 表示と CLI doctor は分担可能。

### Issue 12: キルスイッチと暴走停止を回帰テスト可能にする

Labels: `area:runtime`, `type:feature`, `priority:p0`

目的:
誤爆時に即座に停止でき、再開条件が明確な状態にする。

完了条件:

- `Control + Option + Command + G` が常駐中に認識される
- キルスイッチ自体が前面アプリへ漏れない
- 発火後はジェスチャー生成と慣性が停止する
- 再開は UI の停止/開始またはプロセス再起動に限定される
- ログまたはテストで一方向停止が確認できる

依存関係:
アクセシビリティ権限。

並列化:
Runtime 実装と検証手順整備を分担可能。

### Issue 13: スリープ復帰、デバイス抜き差し、権限変更後の復旧を実測する

Labels: `area:runtime`, `area:verification`, `type:qa`, `priority:p1`, `blocked:external`

目的:
日常利用で止まったままにならない常駐品質を確認する。

完了条件:

- スリープ復帰後に対象デバイスと権限状態を再確認する
- 対象デバイス抜去時に安全停止し、再接続後に復旧する
- 権限が失われた場合に停止し、復旧導線を出す
- 常駐 UI が自動再試行状態を表示する
- 実機操作ログと `doctor` 出力が保存されている

依存関係:
Issue 4、Issue 11。

並列化:
実機検証担当が独立して進められる。

### Issue 14: 入力遅延と CPU 使用率の測定基準を作る

Labels: `area:runtime`, `area:verification`, `type:qa`, `priority:p1`, `parallel:ready`

目的:
「体感できない水準」を、常駐アプリとして判断できる証跡にする。

完了条件:

- 純粋ロジックの `benchmark` 結果を保存する
- イベントタップから生成投稿までの測定方針がある
- 連続操作中の CPU 使用率を測定する手順がある
- 閾値を超えた場合に調整する項目が明記されている
- ベンチマーク結果を PR レビューで確認する基準がある

依存関係:
なし。

並列化:
実装作業と並列可能。

## Milestone 5: 配布と完成判定

### Issue 15: `.app` バンドル、署名、公証、ライセンス同梱を整える

Labels: `area:release`, `type:feature`, `priority:p1`

目的:
日常利用できる配布物として扱える状態にする。

完了条件:

- release build が成功する
- `.app` バンドルが生成される
- `verify-bundle` が成功する
- `LICENSE` と `THIRD_PARTY_NOTICES.md` が同梱される
- 署名と公証の方針が決まっている
- 配布前の権限付与手順が README にある

依存関係:
Issue 1、Issue 2。

並列化:
署名/公証調査とバンドル検証は分担可能。

### Issue 16: 完成判定チェックリストを実測証跡で埋める

Labels: `area:verification`, `area:docs`, `type:qa`, `priority:p0`

目的:
「動いた気がする」ではなく、完成要件を証跡で満たした状態にする。

完了条件:

- `docs/verification.md` の完成判定チェックがすべて証跡リンク付き
- 純正トラックパッド、Nape Pro、生成イベントの比較ログがある
- Spaces / Mission Control の限界または成立条件が実測で明確
- 通常クリック、通常ドラッグ、通常ホイールが壊れていない確認がある
- 既知の失敗条件と回避策が README または docs に反映されている

依存関係:
Issue 4、Issue 6、Issue 9、Issue 10、Issue 13、Issue 15。

並列化:
証跡収集は複数担当で並列可能だが、最終判定はメインスレッドで行う。
