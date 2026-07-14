# nape-gesture リポジトリ運用記録

継続運用の正は [ADR 一覧](adr/README.md) に保存する。
この文書は、リポジトリ作成、初回 push、Issue 作成時点の実施記録として扱う。

## 現在の状態

GitHub リポジトリは作成済みで、2026-07-14時点の公開状態は次のとおり。

- Repository: <https://github.com/char5742/nape-gesture>
- Visibility: public
- Default branch: `main`
- Remote: `origin`
- Baseline commit: `0dacfc5 Initial nape-gesture baseline`
- Rename commit: `6fb14ae Rename project to nape-gesture`

## 初回 push 済みのローカル確認

初回 push 前に次を確認済み。

```sh
git status --short
swift build --scratch-path .build
.build/debug/nape-gesture-core-tests
.build/debug/nape-gesture generate-scroll --x 120 --y 0 --steps 3 --momentum-steps 2 --dry-run --log-json > /tmp/generated-scroll.jsonl
.build/debug/nape-gesture analyze-log /tmp/generated-scroll.jsonl
swift build -c release --scratch-path .build
.build/release/nape-gesture bundle-app --out .build/NapeGesture.app --replace
.build/release/nape-gesture verify-bundle .build/NapeGesture.app
```

追加で、`.app` 経由の `doctor --probe-hid --benchmark-events 10000 --json` も実行済み。
これらはrepository bootstrapと旧診断経路の確認記録であり、現在の製品モデルの完成証跡ではない。
2026-07-08時点で記録した外部ブロッカーは次。

- アクセシビリティ権限は `accessibilityTrusted: false`
- 実機 Nape Pro は未識別で `matchedTargetDeviceCount: 0`
- Spaces / Mission Control の実機挙動は未検証

## 現行の固定製品モデル

2026-07-12以降は、[ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md)に従って製品挙動を次に固定する。

- mouse button 3押下中の連続mouse event量を`twoFingerScrollSwipe` classのtype 22 scrollと必要なtype 29 companionへ変換する
- mouse button 4押下中の連続mouse event量を`threeFingerSystemSwipe` classのtype 30 `DockSwipe` motion 1 / 2へ変換する
- mouse button 5押下中の連続mouse event量を`pinch` class（4本指system pinch相当）のtype 30 `DockSwipe` motion 4へ変換する
- button 3 / 4 / 5未押下時は通常mouse入力を変更せず通す
- button 3 / 4 / 5以外のbuttonと対象外deviceも通常mouse入力として変更せず通す

「2 / 3 / 4本指」はraw contact数やgeneric `fingerCount` transportではなく、固定GestureClassの説明である。classごとにevent type、field、phase、companion、単位変換が異なる。結果別mode、方向別action、application別設定は製品モデルに含めず、最終結果はmacOSまたは前面applicationが解釈する。

baseline `55eb991` のbutton別mode選択は移行前履歴であり、現在の実装状態を示さない。旧mode test、個別familyの投稿成功、`doctor`、`.app`生成または署名済みappの試用だけを完成根拠にせず、現行の要件と完成判定は[ゴール要件](requirements.md)、[ADR-0049](adr/0049-fixed-button-to-gesture-class-input.md)、[完成判定チェックリスト](completion-checklist.md)を正本にする。

## Issue 作成

初期Issueは`docs/github-issues.md`を基準に作成済み。同文書はbootstrap時の履歴であり、現在のIssue状態、再投入、依存関係、close判定はGitHub上のIssueと証跡コメントを正とする。
この件数は bootstrap 時点の記録であり、最新の Issue 数や close 数の正は GitHub 上の Issue 一覧と証跡コメントで確認する。

- Milestone: 5件
- Issue: 16件
- 完了扱いで close 済み: 4件（Issue 1、Issue 2、Issue 3、Issue 7）
- close 済み Milestone: Milestone 1
- bootstrap 時点の運用 label: 15件
- 後続追加 label: `need:human`

`need:human` は承認待ちや確認依頼ではなく、computer-useでも代替できない純正trackpad / Nape Pro物理操作、ユーザー本人しか通せない認証、秘密情報入力などが最後の手段として必要な作業だけに使う。Issue全体ではなく代替不能な手順を明記し、それ以外の実装と検証は止めない。
GUI操作、CGEvent投稿、dry-run、fixtures、ログ解析、Reference Target App、System Behavior Test、権限済み環境での実イベント投稿で代替できる作業は先に自動化する。通常のレビュー待ち、判断待ち、computer-useで到達できるTCC画面操作には付けない。

Issue、label、milestone の作成・更新・コメント・close は、基本的に `gh api` で行う。
重複を避けるため、再投入時は既存 title / label name / milestone title を先に取得してから差分だけ作成する。
label、milestone、Issue close の継続方針は [ADR-0002](adr/0002-github-labels-milestones-and-issue-close.md) に従う。

## 完了済みとして close する Issue

完了条件を満たした Issue は、証跡コメントを付けて close する。
bootstrap 時点で close 対象にしたものは次。

- Issue 1: リポジトリ名を nape-gesture として公開できる状態にする
- Issue 2: CI で debug / release build とコアテストを必須化する
- Issue 3: PR レビュー用チェックリストを整備する
- Issue 7: スクロールと慣性フェーズの生成ログを純正入力と比較可能にする

Issue 7のcloseは移行前の診断上の狭い成果を表すだけであり、3つの固定GestureClass、未押下pass-through、class固有ProductOutput、または製品全体の完了を表さない。後続のclose済みIssueも、旧mode / familyスコープの証跡だけなら同様に現行完成判定へ流用しない。

以後の close 方針と証跡項目は [ADR-0002](adr/0002-github-labels-milestones-and-issue-close.md) と [ADR-0005](adr/0005-issue-orchestration-and-evidence-close.md) に従う。

## メインスレッドの役割

このスレッドは、Issue 整理、PR レビュー、マージ判断、完成判定の証跡確認に集中する。
実装は `docs/parallel-development.md` の所有範囲に従ってサブエージェントへ分割する。
Issue orchestration と証跡付き close の方針は [ADR-0005](adr/0005-issue-orchestration-and-evidence-close.md) に従う。
メインスレッドは、OS/Appの個別結果を製品modeへ昇格させず、固定button→GestureClass→class固有ProductOutputが設定、UI、migration、runtime、テスト、文書、物理受入で一致するまで完成判定を保留する。
