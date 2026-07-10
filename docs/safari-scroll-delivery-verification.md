# Safari scroll 配送比較

## 目的

Safari の top-level page、unlabeled generic `overflow:auto`、縦 scrollbar だけを持つ nested frame、通常の長い article を分けて比較する。
AX scrollbar の値設定を通常 wheel event と同一視せず、outer / inner / frame の移動と wheel count / target を別々に記録する。

## fixture と状態契約

repo root で次を実行する。

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/fixtures/safari-scroll-probe
```

- `http://127.0.0.1:8765/nested.html`: unlabeled generic overflow、縦のみ frame、通常の長い article
- `http://127.0.0.1:8765/top-level.html`: top-level の縦横 scrollbar
- `docs/fixtures/safari-scroll-probe/contract.json`: fixture、状態 path、操作別の比較条件

各ページの `#status` は JSON であり、同じ値を `window.napeGestureScrollProbe.snapshot()` から取得できる。
`reset()` 後、nested fixture は frame の初期状態を受信すると `ready=true` になる。
outer / inner / frame の座標と wheel count / target を文字列解析せず比較できる。

静的 contract は completion に含める。

```sh
python3 scripts/check-safari-scroll-probe-contract.py
```

この検査は schema version、fixture ID、初期 JSON、状態 path、pointer element、比較条件を照合する。
generic overflow の `#inner` に `role` / `aria-label` がないことも固定し、`AXDescription` がある場合だけ成立する fixture に戻さない。

## 実行条件

各試行前に `状態をリセット` を押し、JSON の `ready=true` と全座標・count が 0 であることを確認する。
実行主体は `doctor --json` で `runtimeIdentity.isAppBundle: true` と `tccStatus.accessibility.status: granted` を確認した `.build/NapeGesture.app/Contents/MacOS/nape-gesture` を使う。
Safari PID は `pgrep -x Safari`、実ポインタ位置は `swift -e 'import CoreGraphics; print(CGEvent(source: nil)?.location ?? .zero)'` で確認する。

基本コマンドは次のとおり。

```sh
.build/NapeGesture.app/Contents/MacOS/nape-gesture \
  generate-scroll --x <X> --y <Y> --steps 16 --mode free \
  --ax-delivery sync --post-to-pid <Safari PID>
```

## 機械比較 matrix

`before` と `after` の snapshot を取り、`contract.json` の comparison を適用する。
`unchanged` は完全一致、`increased` は `after > before` とする。

| 対象 | 操作 | 必須条件 |
| --- | --- | --- |
| generic overflow | `--x 1 --y 800` | outer / inner / frame は不変、wheel count も不変。曖昧な target から outer へ配送しない |
| generic overflow | Computer Use の通常 wheel | `inner.y` と `inner.wheel.count` だけが増える |
| 縦のみ frame | `--x 1 --y 800` | `frame.y` だけが増え、微小な未対応横軸は捨てる。outer へ fallback しない |
| 長い article | `--y 800` | `outer.y` だけが増える。viewport より長い content group を nested scroller と誤認しない |
| top-level | `--x 1600 --y 800` | `outer.x` / `outer.y` が増える。`AXWebArea` 自身の scrollbar 属性でも成立する |

normalized AX value と CSS pixel は同じ単位ではないため、生成量の一致は成功条件にしない。
AX scrollbar set は JavaScript `wheel` handler を発火しないため、生成操作では wheel count が不変であることを期待する。

## selector / delivery の成立条件

- application-scoped root hit-test から ancestor を上昇し、最初の `AXWebArea` に対応する最も近い明示 scroll container を選ぶ。
- `AXWebArea` 自身が scrollbar 属性を公開する場合も target 候補にする。
- generic container の判定は `AXDescription` を使わない。必要な全 direct children の frame を deadline 内で確認する。
- child clipping が要求軸にある場合だけ ambiguous とする。通常の長い article/content group の大きさだけでは ambiguous にしない。
- generic container の frame、children、いずれかの child frame を取得できない場合は情報不足として `blocked` にする。
- 最も近い container が要求軸の一部だけを公開する場合、利用可能な軸だけを同じ target へ配送する。利用可能軸が 0 の場合は `blocked` にする。
- 選択済み target の未対応軸は outer target や CGEvent へ流さず、そのイベントでは捨てる。
- `blocked`、端到達の `noChange`、AX 適用済み、部分適用済みは CGEvent fallback を抑止する。
- root hit-test の初回が `kAXErrorCannotComplete` の場合は、探索 deadline 内で1回だけ再試行する。2回とも扱えない場合、または ancestor を `AXApplication` まで完全走査して非 Web と判定した `notHandled` だけが CGEvent fallback を許可する。

## 既存の比較証跡

2026-07-10 の commit `2e66e9f9f8f732e15755632455b9cc038531812b` では、次を確認した。

| 対象 | 操作 | 結果 |
| --- | --- | --- |
| review 元ページの generic overflow | 修正前 `generate-scroll` | `outer=508 inner=0 wheel=0` |
| review 元ページの generic overflow | Computer Use | `outer=0 inner=1488 wheel=1 target=content` |
| repo generic overflow | `2e66e9f` の `generate-scroll` | `outer=0 inner=0 innerWheel=0 frame=0` |
| repo generic overflow | Computer Use 2 page | `outer=0 inner=682 innerWheel=1 innerTarget=generic-2` |
| repo AX accessible frame | `2e66e9f` の `generate-scroll` | `outer=0 inner=0 frame=367 frameWheel=0` |
| repo AX accessible frame | Computer Use 1 page | `outer=0 inner=0 frame=332 frameWheel=1 frameTarget=frame-6` |
| repo top-level | `--x 1600 --y 800` | `scrollX=679 scrollY=304 wheel=0` |

同日の今回変更後に、権限付与済み `.build/NapeGesture.app`、Safari PID 固定、sync、各1 stepで再検証した。

| 対象 | 操作 | JSON before / after |
| --- | --- | --- |
| unlabeled generic overflow | `--x 1 --y 800` | outer / inner / frame / wheel が全て 0 のまま |
| 縦のみ frame | `--x 1 --y 800` | `frame.y: 0 -> 367`、outer / inner / frame.x / wheel は 0 のまま |
| 長い article | `--y 800` | `outer.y: 0 -> 674`、inner / frame / wheel は 0 のまま |
| top-level | `--x 1600 --y 800` | `outer.x: 0 -> 1358`、`outer.y: 0 -> 608`、wheel は 0 のまま |

root hit-test の cold `kAXErrorCannotComplete` は同一プロセス内の2回目で成功することも確認した。
core regression、fixture contract、Safari runtime は別証跡として扱う。上記の値は Issue #102 統合前の比較証跡であり、ADR-0037 統合 commit での最終再取得を省略しない。

## CGEvent 限定実験

generic overflow 上で、各試行前に reset して次を使う。

```sh
swift scripts/probe-cgevent-scroll-delivery.swift <variant> <Safari PID>
```

2026-07-10 の比較では、PID 直接投稿は marker / source にかかわらず `wheel=0`、HID / session tap は `wheel=1` だが `inner=0 / outer=0`、annotated tap は `wheel=0` だった。
HID / session tap と AX set の併用は採用しない。Web 側の `preventDefault()` を外部から判定できず、handler が止めた scroll を AX set が強制する可能性があるためである。

## 最終再取得条件

Issue #102 の時刻 domain と `EventPoster` の timestamp / key API は ADR-0037 としてこの branch に統合済みである。
PR #101 の最終 Safari / runtime 証跡は、その統合 commit と TCC 許可済み `.app` identity を固定して再取得する。
`contract.json` の5 assertion、通常 async、PID 固定 sync、端到達、Computer Use の通常 wheel比較、生成 CGEvent log の `analyze-log --assert-current-uptime`、runtime performance completion を同じ commit で保存する。
