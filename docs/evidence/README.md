# 証跡文書の扱い

このdirectoryは、実行日時点のcommand、binary、fixture、物理capture、観測結果を再現するための記録である。製品要件、現在の設計、完成状態の正本ではない。

現行の製品モデルは[ゴール要件](../requirements.md)と[ADR-0049](../adr/0049-fixed-button-to-finger-count-trackpad-input.md)だけを正とする。

証跡を現在の完成判定へ使うには、次をすべて満たす。

- button 3 / 4 / 5 = 2 / 3 / 4本指の固定対応で取得した証跡である。
- source button、finger count、変換前後のX/Y量、順序、timestamp、phase、session、terminalを対応付けられる。
- 低レベルevent family名をユーザーmode、button assignment、独立製品機能として扱っていない。
- OS / App結果、低レベルcontract、Nape Pro体感を別々に判定している。
- 証跡のrepo SHA、binary identity、fixture、OS buildが検証対象と一致する。

これらを満たさない既存文書は、logger、analyzer、timestamp、raw fieldなど限定された観測事実にだけ利用できる。文書内の当時のIssue境界、family別完成表現、試用判断を現在へ引き継がない。
