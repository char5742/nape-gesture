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

静的 contract と実WebKit render契約は completion に含める。render検査はframeの実viewportから得た初期`maxY`をcontract値と照合し、実終端までscrollした`y == maxY` / `atEnd=true`と親iframeへの状態反映を確認する。

```sh
python3 scripts/check-safari-scroll-probe-contract.py
swift scripts/check-safari-scroll-probe-render.swift
```

この検査は schema version、fixture ID、初期 JSON、状態 path、pointer element、比較条件を照合する。
generic overflow の `#inner` に `role` / `aria-label` がないことも固定し、`AXDescription` がある場合だけ成立する fixture に戻さない。

## 実行条件

各試行前に `状態をリセット` を押し、JSON の `ready=true` と全座標・count が 0 であることを確認する。
実行主体は `doctor --json` で `runtimeIdentity.isAppBundle: true` と `tccStatus.accessibility.status: granted` を確認した `.build/NapeGesture.app/Contents/MacOS/nape-gesture` を使う。
Safari PID は `pgrep -x Safari`、実ポインタ位置は `swift -e 'import CoreGraphics; print(CGEvent(source: nil)?.location ?? .zero)'` で確認する。

操作値とrun集合は `contract.json` を正とする。生成操作は現行contractでは各1 stepであり、例は次のとおり。

```sh
.build/NapeGesture.app/Contents/MacOS/nape-gesture \
  generate-scroll --x <X> --y <Y> --steps 1 --mode free \
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
| frame端 | `--y 10000` 後に `--y 800` | fixtureが返す`frame.atEnd=true`と`frame.y >= frame.maxY`が一致し、追加操作後もframeとouterが不変 |

normalized AX value と CSS pixel は同じ単位ではないため、生成量の一致は成功条件にしない。
AX scrollbar set は JavaScript `wheel` handler を発火しないため、生成操作では wheel count が不変であることを期待する。

## runtime artifact判定

最終証跡rootには `safari-scroll-runtime-manifest.json` を置き、次で評価する。

```sh
artifact_root=<artifact-root>
candidate_commit=$(git rev-parse HEAD)
app_executable=.build/NapeGesture.app/Contents/MacOS/nape-gesture
python3 scripts/check-safari-scroll-runtime-evidence.py "$artifact_root" \
  --expected-commit "$candidate_commit" \
  --app-executable "$app_executable" \
  > "$artifact_root/evaluation.json"
```

manifest schema 2 は候補commit、`dev.char5742.nape-gesture`のexecutable SHA-256、正本contract SHA-256、Safari PID、6 assertion / 12 operation runを固定する。evaluatorは`--expected-commit`との一致と`--app-executable`の実SHA-256を再計算する。各artifact参照は`path`と`sha256`を持ち、`runs/<assertion>/<operation>/`外参照、正規化後の逸脱、run間path・file identity共有を拒否する。生成操作は指定した実行ファイルの絶対pathを含む実argv、native wheelはComputer Useの`direction=down / pages=0.2`をmanifestのinvocationへ保存する。

実行済みrunは `executionStatus: executed` とし、pointer setup、before / after / atEnd、各operation exit codeを持つ。通常routingの事前条件がhost windowで成立しない場合だけ `executionStatus: precondition-blocked`、`invocation: null` とし、pointer setupとwindow owner証跡だけを保存する。操作後snapshotや成功exit codeを捏造して`blocked`にしない。
probe schema 2はframeの`maxY`と`atEnd`を保存し、evaluatorが`atEnd == (y >= maxY)`を再計算する。固定pixel値だけで端到達を成功扱いしない。

Codex host windowを一時退避する場合は、候補`.app`と同じTCC責任主体を維持するため、別launchd jobへ移さずCodexのforeground shell内で行う。`scripts/set-codex-host-visibility.swift hide`の後にSafariを前面化し、`scripts/capture-pointer-window-stack.swift`と候補操作を実行して、終了時はtrapから`activate`する。window stackでSafariがfrontmostかつポインタを含む最上位windowであることを確認する。

- exit `0`: 全12 runが`pass`。最終証跡として採用可能
- exit `1`: contract、hash、identity、artifact、状態遷移、exit codeの不一致
- exit `2`: 通常routingの事前条件blocked。完成扱いせずIssue #105を継続

静的contract、実WebKit render、合成artifactの正負・blocked回帰は次をCIとcompletion collectorで常時実行する。

```sh
python3 scripts/check-safari-scroll-probe-contract.py
swift scripts/check-safari-scroll-probe-render.swift
python3 scripts/check-safari-scroll-runtime-evidence-tests.py
```

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

## 最終証跡

Issue #102 の時刻 domain と `EventPoster` の timestamp / key API は ADR-0037 としてこの branch に統合済みである。
PR #101 の最終 Safari 証跡は `artifacts/completion/2026-07-11/pr101-final-safari`、runtime event / performanceは`pr101-final-runtime-event`へ保存する。同じ候補commitとTCC許可済み`.app` identityを使う。
`contract.json` の6 assertion / 12 run、通常 async、PID固定 sync / async、frame端到達、Computer Use の通常 wheel比較をruntime evaluatorの`status=pass`、`failureCount=0`、`blockedCount=0`で判定する。`discrete/`にはページ戻る / 進むのURL遷移、ズーム前後のfixture幅、32 step横スクロールの画面差分と`--assert-current-uptime --assert-system-scenario`済み計画を保存する。AX fallbackはCGEvent tapにscroll eventを残さないため、横スクロールの実成立はoperation exitと画面snapshot、イベント列の時刻・構造はdry-run計画で分けて証明する。
