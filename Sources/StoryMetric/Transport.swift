import Foundation

/// The lifecycle side of transport, called by `Core` on start and erase.
protocol TransportLifecycle: AnyObject, Sendable {
    func start(apiKey: String, installID: String, manifest: SM.DeclarationManifest)
    func requestErasure(installID: String)
    func flush()
}

/// Production transport: buffers events and drives the `Uploader`.
final class Transport: EventSink, TransportLifecycle, @unchecked Sendable {
    private let buffer: EventBuffer
    let uploader: Uploader
    private let flushInterval: TimeInterval
    private let lock = NSLock()
    private var pump: Task<Void, Never>?
    private let writes = DispatchQueue(label: "com.storymetric.buffer", qos: .utility)

    init(buffer: EventBuffer, uploader: Uploader, flushInterval: TimeInterval = 30) {
        self.buffer = buffer
        self.uploader = uploader
        self.flushInterval = flushInterval
    }

    func receive(_ envelope: SM.Envelope) {
        let event = BufferedEvent(envelope)
        writes.async { [buffer, uploader] in
            buffer.append(event)
            Task { await uploader.flush() }
        }
    }

    func start(apiKey: String, installID: String, manifest: SM.DeclarationManifest) {
        Task {
            await uploader.configure(apiKey: apiKey, installID: installID, manifest: manifest)
            await uploader.uploadDeclarationsIfNeeded()
            await uploader.flush()
            await uploader.drainErasure()
        }
        startPump()
    }

    func requestErasure(installID: String) {
        Task { [buffer, uploader, writes] in
            await uploader.deactivate()
            writes.sync { buffer.removeAll() }
            await uploader.drainErasure()
        }
    }

    func flush() {
        writes.async { [uploader] in
            Task { await uploader.flush() }
        }
    }

    private func startPump() {
        lock.lock(); defer { lock.unlock() }
        guard pump == nil else { return }
        let interval = flushInterval
        pump = Task { [uploader] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await uploader.flush()
            }
        }
    }
}
