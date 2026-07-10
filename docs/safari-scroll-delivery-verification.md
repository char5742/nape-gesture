# Safari scroll 配送比較

## 目的

Safari の top-level page、generic `overflow:auto`、Accessibility が scrollbar を公開する nested frame を分けて比較する。
AX scrollbar の値設定を通常 wheel event と同一視せず、outer 誤配送、nested 選択、wheel handler、端到達を別々に記録する。

## 検証ページ

repo root で次を実行する。

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/fixtures/safari-scroll-probe
```

- `http://127.0.0.1:8765/nested.html`: generic overflow と AX scrollbar を公開する same-origin frame
- `http://127.0.0.1:8765/top-level.html`: top-level の縦横 scrollbar

各試行前に `状態をリセット` を押す。
実行主体は `doctor --json` で `runtimeIdentity.isAppBundle: true` と `tccStatus.accessibility.status: granted` を確認した `.build/NapeGesture.app/Contents/MacOS/nape-gesture` を使う。
Safari PID は `pgrep -x Safari`、実ポインタ位置は `swift -e 'import CoreGraphics; print(CGEvent(source: nil)?.location ?? .zero)'` で確認する。

## 比較手順

generic overflow または frame 内へポインタを置き、次を実行する。

```sh
.build/NapeGesture.app/Contents/MacOS/nape-gesture \
  generate-scroll --y 800 --steps 16 --mode free \
  --ax-delivery sync --post-to-pid <Safari PID>
```

同じ位置で Computer Use の通常 scroll を 1〜2 page 実行し、status と AX scrollbar value を読む。
top-level は `top-level.html` の `Top-level scroll target` 上で縦、固定 status 上で縦横を実行する。

## 2026-07-10 の結果

| 対象 | 操作 | 結果 |
| --- | --- | --- |
| review 元ページの generic overflow | 修正前 `generate-scroll` | `outer=508 inner=0 wheel=0` |
| review 元ページの generic overflow | Computer Use | `outer=0 inner=1488 wheel=1 target=content` |
| repo generic overflow | 修正後 `generate-scroll` | `outer=0 inner=0 innerWheel=0 frame=0`。outer へ誤配送せず fail closed |
| repo generic overflow | Computer Use 2 page | `outer=0 inner=682 innerWheel=1 innerTarget=generic-2` |
| repo AX accessible frame | 修正後 `generate-scroll` | `outer=0 inner=0 frame=367 frameWheel=0`。nested frame だけを更新 |
| repo AX accessible frame | Computer Use 1 page | `outer=0 inner=0 frame=332 frameWheel=1 frameTarget=frame-6` |
| repo AX accessible frame の下端 | `frame scrollbar=1` の後に正方向 `generate-scroll` | `outer=0 frame scrollbar=1` のまま。empty update で outer fallback しない |
| repo top-level | `--x 1600 --y 800 --steps 16 --mode free` | `scrollX=679 scrollY=304 wheel=0` |
| repo top-level content | `--y 800 --steps 16 --mode free` | `scrollX=0 scrollY=608 wheel=0` |
| 既存 top-level 横ページ | `--x 1600 --steps 16 --mode horizontal` | `scrollX=0 -> 1438` |

normalized AX value と CSS pixel は同じ単位ではないため、生成量の一致は成功条件にしない。
比較条件は「選択された container だけが動くこと」「outer を誤って動かさないこと」「wheel handler の有無」である。

## CGEvent 限定実験

generic overflow 上で、各試行前に reset して次を使う。

```sh
swift scripts/probe-cgevent-scroll-delivery.swift <variant> <Safari PID>
```

| variant 群 | 結果 |
| --- | --- |
| `pid-hid-full-marked` / `pid-hid-full-unmarked` / `pid-combined-full-unmarked` | `outer=0 inner=0 wheel=0` |
| `hidtap-hid-full-marked` / `hidtap-hid-full-unmarked` / `hidtap-combined-full-unmarked` | `outer=0 inner=0 wheel=1 target=content` |
| `sessiontap-combined-full-unmarked` | `outer=0 inner=0 wheel=1 target=content` |
| `annotatedtap-combined-full-unmarked` | `outer=0 inner=0 wheel=0` |
| `hidtap-hid-minimal-unmarked` / `hidtap-hid-line-unmarked` | `outer=0 inner=0 wheel=1 target=content` |

HID / session tap は JavaScript `wheel` handler まで到達したが、default scroll は全 variant で発生しなかった。
この branch では製品経路へ採用しない。tap 投稿は `--post-to-pid` の診断対象固定を保証できず、AX 値設定と重ねると Web 側の `preventDefault()` を外部から判定できないため、handler が止めた scroll を強制する可能性がある。

## 成立範囲と残り

- application-scoped hit-test から ancestor を上昇し、最も近い `AXScrollArea` と要求軸の scrollbar を選ぶ。
- 近い container が要求軸を公開しない場合は outer へ昇格しない。
- AX tree に named region の子 clipping または outer viewport より大きい内側 group が見えるが scrollbar がない場合は、outer AX set を行わず CGEvent fallback へ閉じる。
- success cache は PID / window / point に加えて、毎 step の hit-test で再解決した container identity を含む。同一点でも target identity が変われば再利用しない。
- 下端・右端で normalized value が変わらない状態は target 解決済みとして扱い、CGEvent を重ねない。lookup failure は処理済みにしない。
- AX scrollbar set は `wheel` handler を発火しない。generic overflow の container 境界と曖昧さの手掛かりが AX tree から全て省略されると、公開 AX API だけでは nested の存在自体を判定できず、outer 誤配送を完全には排除できない。現 selector は named region の子 clipping または oversized group を識別できる場合に fail closed とするが、通常 wheel と同等の nested routing / `preventDefault()` semantics は未成立の製品要件として残る。

## 最終再取得条件

Issue #102 で修正中の時刻ドメイン変更はこの branch に重複実装しない。
この文書の Safari 値は target 選択修正の比較証跡であり、PR #101 の最終 runtime / Safari 証跡は Issue #102 の変更を取り込んだ head で再取得する。
