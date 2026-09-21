# Changelog

Notable changes to the StoryMetric SDK. Versions follow [Semantic Versioning](https://semver.org), except that until `1.0` a minor bump may contain breaking changes.

## 0.3.0 — 2026-09-21

### Changed — breaking

- **Purchases are a property, not an event.** `SM.log.purchase(_:params:)`, its `product:` overload, `SMLogSurface` and `SM.purchaseParamIDs` are gone. A purchase is now something you add to a milestone you compose yourself in Studio: give the milestone a **Purchase Product** property and the generated method takes the product at the call site — `SM.log.subscribed(product: product, transaction: transaction, paywallSource: "onboarding")`. Migration: design the milestone in Studio, regenerate, and replace the `SM.log.purchase(…)` calls with it.
- **The name `purchase` is released.** Nothing reserves it any more, so a milestone may be called that — and an app that wants one gets an ordinary event with an ordinary payload.
- **The fields changed with the source.** They come from the `Product` now, not the `Transaction`: `product_id`, `product_name`, `price`, `currency`, `period`, `product_type`, `is_trial`. `transaction_id`, `original_transaction_id` and `is_renewal` are no longer recorded. `price` and `currency` are the buyer's own storefront price at the moment they paid.
- **`is_trial` means an introductory offer applied**, and is only present when a transaction was passed. A product can say it *has* an offer, never that one was used, so without a transaction the field is absent rather than `false`.

### Added

- `SM.productParamIDs` — the product's own vocabulary, which a milestone's other properties may not take.
- Deterministic event ids for any milestone given a transaction: the id is derived from the app key, the event name and the transaction, so the same purchase logged twice is one instance. The event name is part of it, so one transaction can be the moment two different milestones happened.

## 0.2.0 — 2026-09-18

### Changed — breaking

- **Events are designed in Studio, not declared in code.** `@SMEvents` is gone, and with it the whole macro target: `SM.Event`, `SM.Param`, `SMEventSource`, and `SM.start(apiKey:events:)`. Studio generates a plain Swift file — the same `SM.log.<event>(…)` surface the macro used to expand to — which you paste into your app. Migration: create the events in Studio, copy the file from Settings → Generated code, delete your `@SMEvents` extension.
- **swift-syntax is no longer a dependency.** It was the SDK's only one, and it cost every integrating app a source build of the compiler plugin. `Package.swift` now has none.
- **Declarations are no longer uploaded.** `POST /v1/declarations`, the `declaration_hash` on every batch, and the `manifest_unknown` handshake are all retired. A batch carries `vocabulary_version` instead: the version of the Studio vocabulary the build was generated from.
- **Runtime payload validation is gone.** An undeclared event or a param of the wrong type used to be reported at runtime; the generated file makes both compile errors, so the checks were re-answering a settled question. `SM.ValidationIssue` is removed.

### Added

- Custom params on the built-in purchase event: `SM.log.purchase(transaction, params: ["paywall_source": .string("onboarding")])`, and the same on the `product:` overload. A purchase is the moment worth knowing the app's state — which paywall, which experiment arm, how far into onboarding — and until now none of it could ride along.
- `SM.purchaseParamIDs` — the built-in param vocabulary (`product_id`, `transaction_id`, `original_transaction_id`, `is_renewal`, `price`, `currency`, `period`, `is_trial`). The transaction states these, so a caller's params can't: entries using these ids are dropped and logged, whether or not the transaction supplies a value.

Purchase params are unvalidated by design — `purchase` has no declaration to check them against, so a mistyped id becomes a new column rather than a compile error. Keep the set small and stable.

### Changed

- `SM.log.purchase(_:)` and `SM.log.purchase(_:product:)` gained a defaulted `params:`. Ordinary call sites are unaffected; an unapplied method reference now spells the full selector (`SM.log.purchase(_:params:)`).

## 0.1.1 — 2026-09-14

### Changed

- Event uploads coalesce. An append no longer POSTs on its own: a burst of logs lands in one request (1.5 s window), and a busy app flushes early once 20 events are waiting. The 30 s pump and the flush on backgrounding are unchanged.
- Declarations upload only when the server asks for them. The manifest hash already rides on every events batch, so the SDK waits for `manifest_unknown` instead of uploading on first launch and again every 7 days. Adding the SDK to an app with an existing user base no longer makes every install upload a manifest in the hours after the update.

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
