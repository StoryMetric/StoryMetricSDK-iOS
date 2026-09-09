/// Where the logging core hands finished envelopes.
protocol EventSink: AnyObject {
    func receive(_ envelope: SM.Envelope)
}

/// Drops everything.
final class NoopSink: EventSink {
    func receive(_ envelope: SM.Envelope) {}
}
