import Foundation

enum Wire {

    static func authHeaders(apiKey: String) -> [String: String] {
        [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
        ]
    }

    static func eventsBody(
        installID: String,
        declarationHash: String,
        sdkVersion: String,
        events: [BufferedEvent]
    ) throws -> Data {
        let iso = ISO8601DateFormatter()
        let wireEvents: [[String: Any]] = events.map { e in
            var d: [String: Any] = [
                "event_id": e.eventID,
                "name": e.name,
                "client_ts": iso.string(from: e.clientTS),
                "event_sequence": e.eventSequence,
                "is_sandbox": e.isSandbox,
                "params": e.params.mapValues { $0.jsonObject },
            ]
            if let s = e.sessionID { d["session_id"] = s }
            if let o = e.osVersion { d["os_version"] = o }
            if let a = e.appVersion { d["app_version"] = a }
            if let p = e.platform { d["platform"] = p }
            if let dev = e.device { d["device"] = dev }
            if let l = e.locale { d["locale"] = l }
            if let c = e.country { d["country"] = c }
            return d
        }
        let body: [String: Any] = [
            "sdk_version": sdkVersion,
            "install_id": installID,
            "declaration_hash": declarationHash,
            "events": wireEvents,
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func declarationsBody(_ manifest: SM.DeclarationManifest) throws -> Data {
        let wireEvents: [[String: Any]] = manifest.events.map { e in
            [
                "name": e.name,
                "params": e.params.map { p in
                    ["id": p.id, "type": p.type.rawValue, "optional": p.optional] as [String: Any]
                },
            ]
        }
        let body: [String: Any] = [
            "declaration_hash": manifest.declarationHash,
            "events": wireEvents,
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func erasureBody(installID: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["install_id": installID])
    }

    static func parseManifestUnknown(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return (obj["manifest_unknown"] as? Bool) ?? false
    }
}
