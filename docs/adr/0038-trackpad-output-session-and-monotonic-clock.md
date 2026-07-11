# ADR-0038: trackpad出力sessionとmonotonic clockを共通化する

- 状態: 採択
- 日付: 2026-07-11

## 背景

scroll、DockSwipe、NavigationSwipe、magnificationを別々の投稿処理として実装すると、input終了とmomentum開始の境界、capture順、時刻domain、terminal処理がfamilyごとにずれる。特にUnix wall clockと起動後時刻の混在、`ended`後の追加event、momentum開始待ちの放置は、入力暴走やstuckを生む。

純正trackpadのfield値とprogress範囲は物理計測前に確定できない。一方、session ID、event順、lifecycle、terminal、有限値、単調時刻は実測値に依存せず先行して固定できる。

## 決定

- 製品trackpad出力の時刻は`MonotonicEventTimestamp`で表し、macOS起動後ナノ秒だけを保持する。
- 現在時刻の取得と起動後秒への変換は`MonotonicEventClock`へ集約する。`MonotonicEventTimestamp`の生値initializerと任意reference付き検証はファイル内に限定し、外部moduleは実際の現在bootで検証するfactoryまたは共通clockからだけ生成する。live sessionへcaller指定clockを注入できない。製品出力境界でwall clock、別のuptime API、独自helperを直接使わず、秒からの変換、live session、momentum start / tickは現在bootのuptimeを超えるtimestampを拒否する。
- 診断用`generate-scroll`と`system-test`も、実投稿とdry-run JSON Linesのevent timestampに`MonotonicEventClock`を使う。`DiagnosticEventPoster`は負値、非有限値、Unix epoch、現在bootの未来時刻からCGEventを作らず、作成失敗として返す。
- `nape-gesture-diagnostic-output-tests`はCGEventを投稿せずtimestamp変換を検査し、`scripts/check-diagnostic-event-time.sh`は診断event経路へのwall clockまたは独自uptime取得の再混入をCIで拒否する。
- output sessionは`TrackpadOutputSessionID`、0始まりで欠落のない`captureOrder`、非減少timestamp、family、terminal stateを持つ。
- input lifecycleは`began / changed / ended / cancelled`、momentum lifecycleは`began / continued / ended`として別型にする。
- scroll inputの`ended`は、session完了かmomentum開始待ちかを`TrackpadOutputContinuation`で明示する。暗黙のmomentum移行は行わない。
- DockSwipeはaxis、progress、velocity、NavigationSwipeは方向、progress、velocity、magnificationはprogress、scale delta、velocityを保持し、terminal時に`commit / cancel`を必須にする。
- state machineはsession ID違い、family違い、capture順欠落、時刻逆行、現在boot外timestamp、非有限値、不正phase、二重terminalを拒否し、拒否したeventでaccepted stateを変更しない。capture orderの上限値はterminal eventにだけ使用できる。
- Codable decodeは過去ログのraw timestampをlosslessに保持するため、decode成功だけをlive capabilityにしない。session machineへの受理時に現在boot上限と順序を必ず再検証する。
- kill switch、runtime stop、sleep、device切断、権限変更、output failureはsession全体の明示cancellationとして表現し、input開始前、input active、momentum待ち、momentum activeのどこからでもterminalへ収束させる。active sessionのcancellationにはfamilyと最終payloadを必須にし、cancel event生成に必要なaxis、direction、progress、velocity、deltaを失わない。
- session終了時はterminal stateを要求する。input active、momentum待ち、momentum activeのままでは完了扱いにしない。
- progress範囲、field番号、係数、event subtypeはこのmodelで仮定しない。#125の純正trackpad logと#129のanalyzerで導出する。

## 影響

- #119、#126、#127のevent family adapterは同じsession event列を入力として実装できる。
- #130のdaemon統合ではgesture認識結果をこのsession modelへ変換し、terminal確認後にsessionを破棄する。
- wall clock metadataはevent timestampと別境界に残せるが、診断generatorを含むevent列と完成証跡のtimestamp比較には起動後時刻を使う。
- macOS更新でfield contractが変わっても、session lifecycleと時刻domainを互換adapterから分離して維持できる。

## 関連

- [trackpad driver上位出力eventを再現する](0036-emulate-trackpad-driver-output-events.md)
- [製品gesture出力と診断event出力を分離する](0037-separate-product-and-diagnostic-event-output.md)
- [検証方針](../verification.md)
- [完成判定チェックリスト](../completion-checklist.md)
