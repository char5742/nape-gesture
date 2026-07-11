# ADR-0041: 物理captureのready同期と公開fixture境界を固定する

- 状態: 採択
- 日付: 2026-07-11

## 背景

Issue #125の物理収録では、次の問題が実際に発生した。

- 操作開始前に短いcapture窓が閉じ、0 eventまたは識別payload 0件になった。
- 別processの診断生成eventが同時収録され、`physicalTrackpad`証跡へ生成markerが混入した。
- 操作完了を伝えるキー入力がraw log末尾へ入り、公開fixtureに不要な入力情報を残す危険が生じた。
- raw log全体は186 MBあり、CI fixtureとして過大だった。

物理操作を再依頼する回数を最小化しながら、純正trackpadだけを正本にし、公開repositoryへ個人入力を残さない境界が必要である。

## 決定

- `trackpad-event-log --ready-file <path> --ready-token <UUID>`を提供し、呼び出し側がcaptureごとに一意なtokenを発行する。
- ready file名にrun tokenを含める。loggerは設定解析直後かつ権限確認・event tap作成前に`O_EXCL`で`ready: false`のleaseを予約し、既存file、symlink、directory、並行runを削除せず拒否する。
- ready recordはschema version、`ready`、run token、PID、lease作成wall-clock、capture開始wall-clock、有限durationのdeadline、scenario ID、repo HEAD SHAだけを持ち、output pathや入力内容を持たない。
- event受付開始時に同じleaseを`ready: true`へatomic writeする。操作側はrun token、PID、scenario ID、repo HEAD SHA、deadlineが期待値と一致し、PIDが生存するrecordだけを受理する。
- 操作案内は`wait-for-trackpad-capture-ready.rb`だけが出す。同じrecordを安定化待機後に再読込し、deadlineに十分な余裕があることまで再検証する。SIGKILLで残ったstale ready、deadline直前、ready撤回後のmanifest後処理中は案内しない。
- duration満了、SIGINT、内部errorを含む全停止経路で、loggerはevent受付をfalseへ変える前にleaseを`ready: false`へatomic writeして`unlink`する。後処理中にreadyを残さない。
- ready fileをlogまたはmanifestと同じlocationや親子pathへ書く設定を、volumeのcase sensitivityとUnicode canonical equivalenceに従ってdirectory作成や権限確認より前に拒否する。
- `physicalTrackpad` logにNape Gestureの生成markerが1件でもあれば、manifest検証を失敗にする。
- 物理capture中は生成event投稿、Computer Use入力、別agentのA/B入力試験を並行実行しない。
- raw logとmanifestはlocal artifactへ保持し、SHA-256、logger SHA、OS build、capture wall-clockで固定する。
- 公開fixtureにはsource SHA、件数、phase、raw classifier、field番号、観測範囲、確定度だけを保存する。serialized event、keycode、pointer座標、不要なdevice identifierを含めない。
- 公開fixtureの集計値は`verify-trackpad-physical-observations.rb`でlocal原本と照合し、SHA、manifest、prefix、target件数、生成marker、scroll companion対応を手入力だけに依存させない。scriptはraw event内容を出力しない。
- target gesture後のキー入力を含むraw logは削除または改変しない。公開fixture生成時だけ、scenario対象eventを選択し、source SHAと選択件数を残す。
- 取得窓不成立、terminal欠落、片方向しかないcaptureは`candidate`または`partial`として可視化し、完成fixtureへ昇格させない。

## 影響

- 人間はready成立後の物理操作だけを担当できる。
- stale /並行readyによる誤開始と、生成event混入による偽の純正証跡を機械的に防げる。
- raw bytesをgitへ追加せず、再現に必要なprovenanceとcontract値をCIへ持ち込める。
- action marker不足やcapture窓失敗を隠さず、必要な再captureだけを`need:human`として残せる。

## 関連

- [ADR-0030: Computer UseでGUI操作と画面証跡を前進させる](0030-computer-use-gui-operation-evidence.md)
- [ADR-0039: trackpad eventログを厳格解析しcapture manifestへ固定する](0039-strict-trackpad-event-analysis-and-capture-manifest.md)
- [ADR-0040: capture順とevent timestampを分離する](0040-capture-order-and-event-timestamp.md)
- [純正トラックパッド物理capture証跡](../evidence/2026-07-11-physical-trackpad-contract-capture.md)
