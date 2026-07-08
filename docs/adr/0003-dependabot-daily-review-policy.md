# ADR-0003: Dependabot の対象、頻度、PR レビュー方針

- 状態: 採択
- 日付: 2026-07-08

## 背景

依存更新を手動確認に任せると、Swift Package Manager と GitHub Actions の更新漏れが起きやすい。
一方で、依存更新 PR を自動的に merge すると、macOS 権限、ビルド環境、GitHub Actions runner の差分を見落とす可能性がある。

## 決定

- Dependabot 設定は `.github/dependabot.yml` に置く。
- 更新対象は次の 2 つにする。
  - Swift Package Manager: `package-ecosystem: "swift"`、`directory: "/"`
  - GitHub Actions: `package-ecosystem: "github-actions"`、`directory: "/"`
- 更新確認は毎日 09:00 Asia/Tokyo に実行する。
- GitHub Docs の Dependabot options reference では、`schedule.interval` に `cron` を指定し、`cronjob` と `timezone` を併用できる。
- このリポジトリでは次の cron 設定を使う。

```yaml
schedule:
  interval: "cron"
  cronjob: "0 9 * * *"
  timezone: "Asia/Tokyo"
```

- Dependabot PR は自動 merge しない。
- Dependabot PR のレビューでは、少なくとも CI 結果、更新対象、破壊的変更の有無、`Package.resolved` や workflow 差分を確認する。
- GitHub Actions 更新では、runner、checkout、setup 系 action の権限や既定値の変更を確認する。
- Swift 依存更新では、ビルド結果、生成物、ライセンス通知への影響を確認する。
- セキュリティ修正であっても、CI 失敗や未説明の破壊的変更がある場合は merge しない。

## 影響

- `daily` interval ではなく cron を使うため、平日だけでなく暦日ベースで確認できる。
- 依存更新 PR は定期的に作られるが、最終判断はメインスレッドのレビューに残る。
- docs/config のみの変更 PR では、Swift build を省略して CI に委ねる場合がある。その場合も YAML parse など変更対象に合った検証を残す。

## 関連

- [`.github/dependabot.yml`](../../.github/dependabot.yml)
- [PR レビューチェックリスト](../pr-review-checklist.md)
- [Dependabot options reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)
