# Changelog

Notable changes to the StoryMetric SDK. Versions follow [Semantic Versioning](https://semver.org), except that until `1.0` a minor bump may contain breaking changes.

## Unreleased

## 0.1.0

First alpha.

### Added

- `@SMEvents` — attach to an `extension SM` to turn `SM.Event` declarations into typed `SM.log.<event>(…)` methods, `SM.allEvents`, and `SM.start(apiKey:)`. Undeclared events are unreachable.
- `SM.start(apiKey:)` — activates collection. Nothing is written to disk and every log call no-ops until it's called.
- `SM.deleteData()` — stops collection, erases the local subject, and requests server-side erasure.
- Automatic events: `$first_launch` (carrying the App Store original download date when available), `$session_start` and `$session_end` (10-minute inactivity timeout, foreground-time duration).
- Environment context on every event: platform, device model, OS and app version, locale, region. No IDFA and no device identifier — the only id is a random per-install UUID.
- Built-in StoreKit 2 purchase capture via `SM.log.purchase(_:)` and `SM.log.purchase(_:product:)`, deduplicated on transaction id.
- Durable on-disk event buffer with batched upload, retry with exponential backoff, and declaration-manifest sync.
- Privacy manifest (`PrivacyInfo.xcprivacy`) bundled as a target resource, so it folds into the host app's Privacy Report automatically. See [`PRIVACY.md`](PRIVACY.md).
- `SM.logLevel` — diagnostics over the unified log. Defaults to `.error`, which reports integration problems (undeclared events, invalid payloads, rejected API keys) and stays silent otherwise; `.debug` adds activation and upload activity, `.off` silences everything.
- Identity tools for manual testing (`DEBUG` only): `SM.debugCurrentInstallID`, `SM.debugResetIdentity()`, `SM.debugSetInstallID(_:)`.
