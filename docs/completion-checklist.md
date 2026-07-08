# 完成判定チェックリスト

この文書は Issue #16「完成判定チェックリストを実測証跡で埋める」で使う証跡台帳です。
最終完成判定では、この文書の matrix を正本として、各行に実測ログ、コマンド出力、PR、Issue コメントへのリンクを埋めます。
Issue #16 は実機作業が残るため、この台帳を作っただけでは close しません。

## 証跡保存場所

証跡ログはリポジトリへ追加せず、次のようなディレクトリ名で保存します。
`artifacts/` は `.gitignore` 対象とし、GitHub Issue / PR にはログ本体ではなく要約と保存先を残します。

```text
artifacts/completion/YYYY-MM-DD/<scenario>/
```

例:

- `artifacts/completion/2026-07-09/build-and-tests/`
- `artifacts/completion/2026-07-09/doctor-app-runtime/`
- `artifacts/completion/2026-07-09/nape-pro-hid-identification/`
- `artifacts/completion/2026-07-09/spaces-mission-control/`

各 scenario には、実行コマンドを残す `commands.txt`、標準出力または JSON を残す `*.json` / `*.jsonl`、画面操作が必要だった場合の短い観察メモ `notes.md` を置きます。
PR や Issue へは、ログ本体ではなく、保存場所、主要コマンド、判定結果、未検証事項を証跡コメントとして残します。

## 状態と分類

状態は次の値で管理します。

| 状態 | 意味 |
| --- | --- |
| `未着手` | 証跡がまだない |
| `機械証跡待ち` | 実機なしで先に埋められる証跡が残っている |
| `人間作業待ち` | 物理操作または macOS UI 操作が最後の手段として残っている |
| `一部完了` | 証跡の一部はあるが、完成判定には不足がある |
| `完了` | 必要な証跡がそろい、未検証事項がない |

`need:human` はレビュー待ち、承認待ち、確認依頼を表しません。
純正トラックパッド操作、Nape Pro 実機操作、スリープ、デバイス抜き差し、TCC 権限変更、システム設定の許可操作など、人間が物理作業または macOS UI 操作を行う必要が最後の手段として残る項目だけに使います。
人間依存は最小化し、先に dry-run、fixtures、Reference Target App、System Behavior Test、保存済みログ解析、権限済み環境での CGEvent 投稿で代替できる証跡を埋めます。
この初期台帳では証跡リンクをまだ埋めていないため、`完了` の行はありません。
`証跡リンク / 保存先` が `未設定` の行は、状態にかかわらず完成扱いにしません。

## 完成判定 matrix

| 完成要件 | 必要な証跡 | 機械で先に埋める証跡 | 最後の手段として人間が必要な証跡 | 証跡リンク / 保存先 | 関連 Issue | 現在状態 |
| --- | --- | --- | --- | --- | --- | --- |
| debug / release build | `swift build` と `swift build -c release` の成功ログ | `swift build`、`swift build -c release` の stdout/stderr と終了コード | なし | `未設定` | #2, #15, #16 | `機械証跡待ち` |
| core tests | `nape-gesture-core-tests` の成功ログ | コアテストの stdout/stderr と終了コード | なし | `未設定` | #2, #16 | `機械証跡待ち` |
| app bundle / 署名 / 公証 | `.app` 作成、`verify-bundle`、署名検証、公証、stapler / Gatekeeper 評価のログ | `swift build -c release`、`bundle-app --replace`、`verify-bundle`、ad-hoc 署名の検証、ライセンス同梱確認 | Developer ID 証明書、App Store Connect 認証情報、キーチェーン確認、公証提出が必要な場合の macOS UI または認証操作 | `未設定` | #15, #16 | `機械証跡待ち` |
| doctor 権限・runtimeIdentity | 実利用する `.app` または実行ファイルでの `doctor --probe-hid --benchmark-events ... --json` | `doctor --json` の `runtimeIdentity`、`settingsValidationIssues`、benchmark 部分 | システム設定でアクセシビリティと入力監視を実利用主体へ許可し、権限反映後に再実行する操作 | `未設定` | #11, #15, #16 | `人間作業待ち` |
| Nape Pro HID 識別 | `devices --all --json`、Nape Pro 操作中の `hid-log`、`analyze-hid-log`、確定 matcher | `devices --all --json`、既存ログの解析、`analyze-hid-log` | Nape Pro 実機を接続して操作する物理作業 | `未設定` | #4, #16 | `人間作業待ち` |
| targetDeviceAssociation 実測 | Nape Pro HID 入力と event tap 入力の時刻差分、`associationWindow` の採用根拠、巻き込みなし確認 | 保存済み HID / CGEvent / target log の時刻差分解析、設定検証、境界値テスト | Nape Pro と通常入力デバイスを同じ環境で操作し、実測分布と巻き込み有無を取る作業 | `未設定` | #5, #16 | `人間作業待ち` |
| 元入力抑制 | ジェスチャー成立後に未マークのクリック、ドラッグ、ホイール、キーが前面アプリへ漏れない target log | `target --out`、`system-test run`、`analyze-target-log --assert-no-leaks`、fixtures 回帰 | Nape Pro 実機で成立させたジェスチャー後の target log と画面挙動確認 | `未設定` | #6, #16 | `機械証跡待ち` |
| 通常クリック / ドラッグ / ホイール通過 | ジェスチャーボタン未押下時と解放後に通常入力が過剰抑制されない target log | `normal-after-release`、`analyze-target-log --json`、通常入力通過シナリオの system-test | 実デバイスで通常クリック、ドラッグ、ホイールを操作し、前面アプリで期待通り通ることを確認 | `未設定` | #6, #16 | `機械証跡待ち` |
| 純正トラックパッド比較 | 純正トラックパッド操作ログ、生成イベントログ、比較結果、差分理由 | `generate-scroll --dry-run --log-json`、`compare-log`、保存済みログ解析 | 純正トラックパッドで Spaces、スクロール、ズームなどを操作してログを取る作業 | `未設定` | #7, #8, #9, #10, #16 | `人間作業待ち` |
| Spaces / Mission Control | Finder など前面時の `system-test` 実行ログ、生成イベントログ、画面挙動メモ、公開 API の限界がある場合の根拠 | `system-test list`、`system-test run --dry-run --log-json`、Reference Target App での AppKit 受信ログ | アクセシビリティ許可済み環境で Spaces / Mission Control の画面遷移を実測する操作 | `未設定` | #9, #16 | `人間作業待ち` |
| ページ戻る / 進む / ズーム / 横スクロール | Safari または Reference Target App でのシナリオ別ログ、画面挙動メモ、割り当てとパラメータ | `system-test run --dry-run --log-json`、`target --out`、`analyze-target-log` | Safari など対象アプリでページ遷移、ズーム、横スクロールを実操作して確認 | `未設定` | #10, #16 | `人間作業待ち` |
| キルスイッチ | `Control + Option + Command + G` で生成と慣性が止まり、再有効化条件が限定される証跡 | `RuntimeSafetyState` の回帰テスト、target log、`analyze-target-log --assert-no-leaks` | 実行中アプリでショートカットを押し、暴走停止と通常入力復帰を観察する操作 | `未設定` | #12, #16 | `機械証跡待ち` |
| スリープ復帰 / 抜き差し / 権限変更後復旧 | スリープ復帰、Nape Pro 抜き差し、TCC 権限変更後の停止、再試行、復旧ログ | 既存の状態遷移テスト、`doctor --json`、設定検証、権限未許可時のエラー出力 | Mac のスリープ復帰、実デバイス抜き差し、システム設定での TCC 権限変更 | `未設定` | #13, #16 | `人間作業待ち` |
| 性能 | 純粋ロジック benchmark、doctor benchmark、常駐 CPU、tap-to-post または同等の入力遅延測定 | `benchmark --events ... --json`、`doctor --benchmark-events ... --json`、結果の基準照合 | 権限済み実行主体で常駐中の CPU と実入力遅延を測る操作 | `未設定` | #14, #16 | `機械証跡待ち` |
| ライセンス / 由来 | `LICENSE`、`THIRD_PARTY_NOTICES.md`、バンドル内同梱、Mac Mouse Fix 由来コードを含まない説明 | `verify-bundle`、ファイル存在確認、依存通知確認、README / docs の説明確認 | 公開配布物を最終成果物として目視確認する場合のみ | `未設定` | #1, #15, #16 | `機械証跡待ち` |

## 先に自動実行するコマンド束

実機や TCC 操作なしで先に埋められる証跡は、次の順に保存します。
次のコードブロックは同じ shell で順に実行します。

```sh
artifact_root="artifacts/completion/$(date +%F)"
mkdir -p "$artifact_root/build-and-tests"

swift build --scratch-path .build > "$artifact_root/build-and-tests/swift-build.log" 2>&1
swift build -c release --scratch-path .build > "$artifact_root/build-and-tests/swift-build-release.log" 2>&1
.build/debug/nape-gesture-core-tests > "$artifact_root/build-and-tests/core-tests.log" 2>&1
```

```sh
mkdir -p "$artifact_root/bundle"

.build/release/nape-gesture bundle-app --out .build/NapeGesture.app --replace > "$artifact_root/bundle/bundle-app.log" 2>&1
.build/release/nape-gesture verify-bundle .build/NapeGesture.app > "$artifact_root/bundle/verify-bundle.log" 2>&1
```

```sh
mkdir -p "$artifact_root/doctor-and-performance"
config="$artifact_root/doctor-and-performance/nape-gesture.config.json"

.build/debug/nape-gesture init-config --allow-unmatched --out "$config"
.build/debug/nape-gesture doctor --config "$config" --benchmark-events 50000 --json > "$artifact_root/doctor-and-performance/doctor-debug.json"
.build/debug/nape-gesture benchmark --events 200000 --json > "$artifact_root/doctor-and-performance/benchmark-debug.json"
```

```sh
mkdir -p "$artifact_root/system-test-dry-run"

.build/debug/nape-gesture system-test list > "$artifact_root/system-test-dry-run/system-test-list.txt"
.build/debug/nape-gesture system-test run --scenario space-left --target finder --dry-run --log-json --out "$artifact_root/system-test-dry-run/system-space-left.jsonl"
.build/debug/nape-gesture system-test run --scenario space-right --target finder --dry-run --log-json --out "$artifact_root/system-test-dry-run/system-space-right.jsonl"
.build/debug/nape-gesture system-test run --scenario mission-control --dry-run --log-json --out "$artifact_root/system-test-dry-run/system-mission-control.jsonl"
```

```sh
mkdir -p "$artifact_root/hid-inventory"

.build/debug/nape-gesture devices --all --json > "$artifact_root/hid-inventory/devices-all.json"
```

実イベント投稿や target log を使う半自動証跡は、アクセシビリティ許可済みの実行主体でのみ完成判定へ採用します。
`doctor --json` の `runtimeIdentity` が日常利用する `.app` または実行ファイルと一致しない場合、その証跡は参考扱いです。

## 最後に人間が必要な作業リスト

次の作業は、機械証跡を先に埋めても代替できない場合だけ実施します。

- システム設定で、実利用する `.app` または実行ファイルへアクセシビリティと入力監視を許可する。
- Nape Pro を接続し、`hid-log` 実行中にボタン、移動、ホイールなどを操作する。
- 純正トラックパッドで Spaces、Mission Control、ページ戻る/進む、ズーム、横スクロール相当のログを取る。
- Nape Pro 操作で同じシナリオを実行し、target log、CGEvent log、画面挙動を保存する。
- 通常クリック、通常ドラッグ、通常ホイールがジェスチャー処理後も壊れていないことを前面アプリで確認する。
- キルスイッチを実行中に押し、生成と慣性が止まり、通常入力が過剰抑制されないことを確認する。
- Mac をスリープ復帰させ、Nape Pro の抜き差しを行い、TCC 権限を一時的に変更して復旧導線を確認する。
- Developer ID 署名、公証、stapler、Gatekeeper 評価に必要な認証操作を行う。

人間作業で観察した内容は、必ず同じ scenario ディレクトリのログと対応付けます。
目視だけの「動いた」は完成証跡にせず、画面挙動メモは JSON / JSON Lines / コマンドログを補う材料として扱います。
