/// The manual declaration seam. `@SMEvents` generates a conforming `SM.allEvents`;
/// conform a type by hand to use the SDK without the macro.
public protocol SMEventSource {
    static var allEvents: [SM.Event] { get }
}
