# ADR-0031: Reference Target App の無人証跡では capture view へカーソルを固定する

- 状態: 採択
- 日付: 2026-07-09

## 背景

Runtime event 証跡では、`run`、Reference Target App、`system-test`、`analyze-target-log` を組み合わせて、元入力漏れ、生成イベント到達、キルスイッチ、通常入力通過を機械判定する。
`system-test` の未マークマウスイベントとスクロールイベントは現在のポインタ位置へ投稿されるため、Reference Target App が前面にあっても、ポインタが capture view 外にあると target log が空になる。

この空ログは機能不具合ではなく検証ハーネスの位置合わせ不足であり、人間にポインタ配置を依頼すると runtime event 証跡が再現しにくくなる。

## 決定

- Reference Target App に `--focus-capture-point` を追加し、指定時だけ capture view 中心へカーソルを移動する。
- `--focus-capture-point` は無人の runtime event 証跡収集で使い、手動比較や純正トラックパッド観察では必須にしない。
- ready file には `focus` として AppKit screen 座標、Quartz 座標、移動後 cursor location を残し、target log が空だった場合に位置合わせの有無を追跡できるようにする。
- ready file には `diagnostics` として active/key/main window、first responder、`EventCaptureView` hit-test、要求 Quartz 座標と実 cursor location の一致も残し、無人証跡では script がこの条件を検査する。capture 中心の計算前に window layout を確定する。
- 起動直後の activation race を ready と誤記録しない。起動後単調時刻で2秒を上限に50ms間隔で active/key/main、capture first responder、実カーソル位置を再確立し、全条件成立時だけ `ready: true` を書く。期限切れは診断値つきの `ready: false` として失敗させる。
- `scripts/collect-runtime-event-evidence.sh` は Reference Target App 起動時に `--focus-capture-point` を付ける。
- `gesture-drag` の無人証跡は capture window 内で完結する `--amount 240` を使い、検証操作自身が window 外へカーソルを押し出した結果を入力漏れと混同しない。
- target log 証跡では `system-test run` に `--target finder` / `--target safari` を付けない。対象アプリ前面化の検証と Reference Target App の AppKit 受信検証を混同しない。

## 影響

- runtime event 証跡は、人間のカーソル配置に依存せず再実行できる。
- shell が ready file を観測した時点で、Reference Target の AppKit focus と実ポインタ位置が成立している。
- 空 target log は、権限不足、投稿失敗、daemon 抑制、target 位置合わせのどれかとして切り分けやすくなる。
- 検証自動化が一時的にカーソルを動かすため、実行中はユーザーの手動操作と並行しない。

## 関連

- [ADR-0006: Runtime event 証跡の自動収集と人間作業境界](0006-runtime-event-evidence-automation.md)
- [ADR-0019: Runtime event 証跡の status JSON](0019-runtime-event-status-json.md)
- [ADR-0030: Computer Use で GUI 操作と画面証跡を前進させる](0030-computer-use-gui-operation-evidence.md)
- [ADR-0032: Reference Target App は foreground capture 経路を証跡化する](0032-reference-target-foreground-capture.md)
- [検証手順](../verification.md)
- [完成判定チェックリスト](../completion-checklist.md)
