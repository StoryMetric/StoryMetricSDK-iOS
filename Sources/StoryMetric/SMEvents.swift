/// Attach to `extension SM` where your events are declared. Generates a typed
/// `SM.log.<event>(…)` method per declaration, plus `SM.allEvents` and
/// `SM.start(apiKey:)`.
@attached(member, names: arbitrary)
public macro SMEvents() = #externalMacro(module: "StoryMetricMacros", type: "SMEventsMacro")
