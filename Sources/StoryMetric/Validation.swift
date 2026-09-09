extension SM {

    /// A problem found in a declaration or a logged payload. Payload issues flag
    /// the event; they never drop it.
    enum ValidationIssue: Sendable, Hashable {
        // Manifest-structural
        case emptyEventName
        case reservedEventName(name: String)
        case duplicateEvent(name: String)
        case emptyParamId(event: String)
        case duplicateParam(event: String, param: String)

        // Payload
        case undeclaredEvent(name: String)
        case missingRequiredParam(event: String, param: String)
        case undeclaredParam(event: String, param: String)
        case typeMismatch(event: String, param: String, expected: ParamType, actual: ParamType)
    }

    enum Validate {

        /// Structural checks: empty or reserved names, and duplicate events or params.
        static func manifest(_ manifest: DeclarationManifest) -> [ValidationIssue] {
            var issues: [ValidationIssue] = []
            var seenEvents = Set<String>()

            for event in manifest.events {
                if event.name.isEmpty {
                    issues.append(.emptyEventName)
                } else if event.name.hasPrefix(AutoEvent.prefix) || event.name == ReservedEvent.purchase {
                    issues.append(.reservedEventName(name: event.name))
                } else if !seenEvents.insert(event.name).inserted {
                    issues.append(.duplicateEvent(name: event.name))
                }

                var seenParams = Set<String>()
                for param in event.params {
                    if param.id.isEmpty {
                        issues.append(.emptyParamId(event: event.name))
                    } else if !seenParams.insert(param.id).inserted {
                        issues.append(.duplicateParam(event: event.name, param: param.id))
                    }
                }
            }
            return issues
        }

        /// Checks a payload against its declaration: required params present, types
        /// matched, undeclared params flagged.
        static func payload(
            _ params: [String: ParamValue],
            against event: Event
        ) -> [ValidationIssue] {
            var issues: [ValidationIssue] = []
            let declared = Dictionary(uniqueKeysWithValues: event.params.map { ($0.id, $0) })

            for param in event.params where !param.optional {
                if params[param.id] == nil {
                    issues.append(.missingRequiredParam(event: event.name, param: param.id))
                }
            }

            for (id, value) in params {
                guard let decl = declared[id] else {
                    issues.append(.undeclaredParam(event: event.name, param: id))
                    continue
                }
                if value.type != decl.type {
                    issues.append(.typeMismatch(
                        event: event.name, param: id,
                        expected: decl.type, actual: value.type
                    ))
                }
            }
            return issues
        }
    }
}
