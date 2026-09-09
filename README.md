# StoryMetric

Goal-oriented analytics for iOS and macOS. You declare your app's events in Swift; StoryMetric turns each user's path to a goal into a readable timeline you open in Studio.

Alpha. iOS 16+, macOS 13+, Swift 5.9+.

## Install

Add the package in Xcode (**File → Add Package Dependencies…**) or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/andgordio/StoryMetricSDK-iOS.git", from: "0.1.0"),
]
```

Then `import StoryMetric`.

## 1. Declare your events

Attach `@SMEvents` to an `extension SM`  anywhere in your app. Each `SM.Event` becomes a typed method on `SM.log`.

```swift
import StoryMetric

@SMEvents
extension SM {
    static let usedSearch = SM.Event("used_search", params: [.string("query"), .int("results")])
    static let openedPaywall = SM.Event("opened_paywall", params: [.string("source")])
    static let savedToLibrary = SM.Event("saved_to_library")
}
```

Names and param ids are snake_case — that's how they read in Studio. Params are `.string`, `.int`, `.double`, `.bool`, or an array of each, and are required unless you pass `optional: true`. Declaring is the only way in: there is no string-based `log("whatever")`, so an event that isn't declared can't be logged.

## 2. Start

Create an app in Studio, copy its ingest key, and start at launch:

```swift
@main
struct MyApp: App {
    init() {
        SM.start(apiKey: "sm_live_…")
    }
}
```

Before you call it, the SDK writes nothing to disk and every log call no-ops. If you gate analytics behind a consent prompt, just call `start` once the user agrees.

## 3. Log

```swift
SM.log.usedSearch(query: text, results: hits.count)
SM.log.openedPaywall(source: "settings")
SM.log.savedToLibrary()
```

Autocomplete off `SM.log.` is your event catalog. Events are buffered on disk and uploaded in batches — they survive being killed offline, and nothing is sent twice.

## What you get without writing anything

- **`$first_launch`** — once per install, the anchor most stories start from. On a real App Store install it carries the account's original download date, so a user who had your app before you added the SDK reads as returning rather than new.
- **`$session_start` / `$session_end`** — a session ends after 10 minutes of inactivity. Its duration counts foreground time only, so an app left open in the background doesn't inflate it.
- **Context on every event** — platform, device model, OS and app version, locale, region. No IDFA, no device identifier; the only id is a random per-install UUID the SDK mints itself.

## Purchases

```swift
SM.log.purchase(transaction)                  // StoreKit 2 Transaction
SM.log.purchase(transaction, product: product) // adds period + is_trial
```

`purchase` is built in — no declaration, and you can't shadow it with an event of your own. It captures `product_id`, `transaction_id`, `original_transaction_id`, `is_renewal`, `price`, `currency`, and with the `Product` overload the normalized subscription `period` and `is_trial`.

Logging the same transaction twice collapses to one row, so you don't have to track what you've already sent.

**Renewals are yours to decide.** The SDK stamps `is_renewal` but never filters. Renewals don't become stories, but they do cost an ingested event, and dedup can't collapse them — each renewal is a distinct transaction. Unless you want them in your data, gate your `Transaction.updates` listener on `originalID == id`, and still `finish()` every transaction.

## Deleting a user's data

```swift
SM.deleteData()
```

Stops collection, erases the local subject, and asks the server to erase what it holds. Calling `start` again afterwards begins a brand-new subject.

## Privacy

The SDK ships a privacy manifest that Xcode folds into your app's Privacy Report automatically — you don't copy anything. What you do fill in by hand is the App Store Connect nutrition label; [`PRIVACY.md`](PRIVACY.md) has the paste-ready answers and the reasoning behind each.

## Testing your integration

The SDK reports integration problems out of the box — an event you forgot to declare, a param of the wrong type, a rejected API key — under the `com.storymetric` subsystem in Xcode's console and Console.app. It stays quiet when the integration is correct, so there's nothing to turn off in production.

If events aren't arriving and nothing has been reported, turn the level up before `start` to see activation and every upload:

```swift
SM.logLevel = .debug   // .error is the default; .off silences everything
SM.start(apiKey: "sm_live_…")
```

Debug and TestFlight builds are flagged **sandbox**. Their stories still show in Studio, tagged `sandbox`, but sandbox subjects stay out of cohort comparisons unless you opt them in — so your own test runs never skew your numbers.

In `DEBUG` builds you also get identity tools, so one build can produce many distinct subjects without reinstalling:

```swift
SM.debugCurrentInstallID       // the id to search for in Studio
SM.debugResetIdentity()        // next start() = a brand-new subject
SM.debugSetInstallID(id)       // keep feeding an existing subject
```

Call `SM.start(…)` again after either mutation.

## Alpha limits

- No automatic `Transaction.updates` capture yet — log purchases at the call site.
- Uploads don't yet continue in the background after the app is suspended; they resume on next launch.
