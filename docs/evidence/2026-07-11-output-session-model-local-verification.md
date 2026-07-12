# Trackpad output session model local verification

> 非規範証跡: この文書のfamily別session表現と当時のIssue境界は現在の製品モデルではない。再利用できるのはmonotonic clock、capture order、terminalなど検証済みの限定原則だけであり、固定button / finger-count完成判定には[証跡文書の扱い](README.md)を適用する。

- 日付: 2026-07-11
- branch: `codex/output-session-model`
- base: `a7318eb310fd8512ebdae81e06adda3829017cca`
- 対象Issue: #128

## 実装境界

- 生値initializerを外部公開しない`MonotonicEventTimestamp`と、現在bootで検証する`MonotonicEventClock`による起動後ナノ秒domain
- scroll / DockSwipe / NavigationSwipe / magnificationの共通session event
- input lifecycleとmomentum lifecycleの型分離
- session ID、capture order、terminal、progress、velocity、commit / cancel
- kill switch、runtime stop、sleep、device切断、権限変更、output failureの明示cancellation
- active cancellationのfamilyと最終payload保持
- session ID / family混入、順序欠落、時刻逆行、現在boot外timestamp、非有限値、二重terminal、stuckの拒否
- momentum start / tickへのUnix epoch混入拒否と、異常時のterminal生成
- 製品出力境界での直接wall clock利用を禁止するsource guard

## 実行結果

| 検証 | 結果 |
| --- | --- |
| `swift build` | 成功 |
| `swift run nape-gesture-core-tests` | 成功 |
| `swift build -c release -Xswiftc -warnings-as-errors` | 成功 |
| `.build/release/nape-gesture-core-tests` | 成功 |
| `sh scripts/check-product-output-boundary.sh` | 成功 |
| `sh scripts/check-provenance.sh` | 成功 |
| `sh -n scripts/check-product-output-boundary.sh` | 成功 |
| `git diff --check` | 成功 |
| `NAPE_COMPLETION_ARTIFACT_ROOT=/tmp/nape-output-session-completion-evidence-verified sh scripts/collect-completion-evidence.sh` | 成功 |

completion evidenceはdebug / release build、core tests、app bundle、bundle identity、GUI smoke、ad-hoc署名、doctor schema、benchmark、既存diagnostic scenario、fixture解析を含めて成功した。

## Review fixes

通常のCodex subagent reviewで、初版には次の不足があった。

- session-level cancellationがfamilyと最終payloadを保持しない
- 秒からの変換とlive sessionがUnix epoch相当の未来timestampを拒否しない
- capture order上限値をnonterminal eventが消費するとterminal不能になる
- product time source guardの検出対象が狭い

これらを根本から修正し、active cancellation payload必須、現在boot uptime上限、terminal専用最終order、拡張source guardとnegative testsを追加した。Grokは使用していない。

## 未完了境界

この証跡はpure session modelと既存機能の退行なしを示す。次は別Issueで扱うため、次の完成は示さない。

- #129のraw event専用analyzerと純正contract fixture
- #125の純正trackpad物理収録
- #119のscroll / companion gesture / momentum adapter
- #126のDockSwipe adapter
- #127のNavigationSwipe / magnification adapter
- #130のdaemon統合とsystem-wide runtime evidence
- Nape Pro実機体感、Developer ID署名、公証
