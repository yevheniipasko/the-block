import Foundation

/// Fans values out to any number of `AsyncStream` subscribers (spec LIVE-1).
///
/// Each call to `stream(startingWith:)` creates an independent stream; a subscriber that stops
/// iterating (e.g. its SwiftUI `.task` is cancelled) is removed automatically.
final class StreamBroadcaster<Element: Sendable> {

    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    /// Number of live subscribers; useful to start/stop work only while someone listens.
    var subscriberCount: Int { continuations.count }

    /// Returns a new stream that first yields `initial` (if any) and then every broadcast value.
    func stream(startingWith initial: Element? = nil) -> AsyncStream<Element> {
        let id = UUID()
        // Unbounded: a (re)connection announces every lot at once (~200 values); dropping any of them
        // would lose state for subscribers that track lots one by one. Values are small value types.
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: .unbounded)
        if let initial {
            continuation.yield(initial)
        }
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [self] in self?.continuations[id] = nil }
        }
        return stream
    }

    /// Sends `element` to every current subscriber.
    func yield(_ element: Element) {
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }

}
