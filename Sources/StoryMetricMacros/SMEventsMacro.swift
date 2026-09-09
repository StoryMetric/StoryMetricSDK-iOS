import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - Parsed model

private enum ParamKind: String {
    case string, int, double, bool
    case stringArray, intArray, doubleArray, boolArray

    init?(builderName: String) { self.init(rawValue: builderName) }

    var swiftType: String {
        switch self {
        case .string: return "String"
        case .int: return "Int"
        case .double: return "Double"
        case .bool: return "Bool"
        case .stringArray: return "[String]"
        case .intArray: return "[Int]"
        case .doubleArray: return "[Double]"
        case .boolArray: return "[Bool]"
        }
    }

    /// Matching `SM.ParamValue` case name.
    var valueCase: String { rawValue }
}

private struct ParamDecl {
    let id: String
    let kind: ParamKind
    let optional: Bool
}

private struct EventDecl {
    let propertyName: String  // e.g. "usedSearch"
    let eventName: String     // e.g. "used_search"
    let params: [ParamDecl]
}

private enum SMDiagnostic: String, DiagnosticMessage {
    case nonLiteralName
    case reservedName
    case reservedPurchaseName

    var message: String {
        switch self {
        case .nonLiteralName:
            return "@SMEvents event names must be string literals"
        case .reservedName:
            return "event names starting with \"$\" are reserved for StoryMetric's automatic events"
        case .reservedPurchaseName:
            return "\"purchase\" is reserved for StoryMetric's built-in StoreKit capture path; call SM.log.purchase(_:) instead"
        }
    }
    var diagnosticID: MessageID { MessageID(domain: "StoryMetric", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

// MARK: - Macro

/// Generates, as members of the attached `extension SM`: `enum Log`, `static var log`,
/// `static var allEvents`, and `static func start(apiKey:)`.
public struct SMEventsMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let events = parseEvents(from: declaration, context: context)
        let methods = events.map(makeLogMethod).joined(separator: "\n\n")
        let names = events.map(\.propertyName).joined(separator: ", ")

        let logEnum: DeclSyntax = """
            public enum Log: SMLogSurface {
            \(raw: methods)
            }
            """
        let logAccessor: DeclSyntax = "public static var log: Log.Type { Log.self }"
        let allEvents: DeclSyntax = """
            public static var allEvents: [SM.Event] {
                [\(raw: names)]
            }
            """
        let start: DeclSyntax = """
            public static func start(apiKey: String) {
                SM._start(apiKey: apiKey, events: allEvents)
            }
            """
        return [logEnum, logAccessor, allEvents, start]
    }
}

// MARK: - Parsing

private func parseEvents(
    from group: DeclGroupSyntax,
    context: (any MacroExpansionContext)? = nil
) -> [EventDecl] {
    var events: [EventDecl] = []
    for member in group.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self),
              varDecl.modifiers.contains(where: { $0.name.text == "static" }) else { continue }

        for binding in varDecl.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                  isSMEventCall(call) else { continue }

            let firstArg = call.arguments.first(where: { $0.label == nil })?.expression
            guard let eventName = stringValue(firstArg) else {
                context?.diagnose(Diagnostic(node: call, message: SMDiagnostic.nonLiteralName))
                continue
            }
            guard !eventName.hasPrefix("$") else {
                context?.diagnose(Diagnostic(node: call, message: SMDiagnostic.reservedName))
                continue
            }
            guard eventName != "purchase" else {
                context?.diagnose(Diagnostic(node: call, message: SMDiagnostic.reservedPurchaseName))
                continue
            }

            let paramsArray = call.arguments
                .first(where: { $0.label?.text == "params" })?
                .expression.as(ArrayExprSyntax.self)
            let params = paramsArray?.elements.compactMap { parseParam($0.expression) } ?? []

            events.append(EventDecl(propertyName: name, eventName: eventName, params: params))
        }
    }
    return events
}

private func isSMEventCall(_ call: FunctionCallExprSyntax) -> Bool {
    if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
        return member.declName.baseName.text == "Event"      // SM.Event(...)
    }
    if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
        return ref.baseName.text == "Event"                  // Event(...)
    }
    return false
}

private func parseParam(_ expr: ExprSyntax) -> ParamDecl? {
    guard let call = expr.as(FunctionCallExprSyntax.self),
          let member = call.calledExpression.as(MemberAccessExprSyntax.self),
          let kind = ParamKind(builderName: member.declName.baseName.text)
    else { return nil }

    guard let idArg = call.arguments.first(where: { $0.label == nil }),
          let id = stringValue(idArg.expression) else { return nil }

    let optional = call.arguments.contains {
        $0.label?.text == "optional"
            && $0.expression.as(BooleanLiteralExprSyntax.self)?.literal.text == "true"
    }
    return ParamDecl(id: id, kind: kind, optional: optional)
}

private func stringValue(_ expr: ExprSyntax?) -> String? {
    guard let lit = expr?.as(StringLiteralExprSyntax.self) else { return nil }
    let segments = lit.segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }
    guard segments.count == lit.segments.count else { return nil } // reject interpolation
    return segments.joined()
}

// MARK: - Codegen

private func makeLogMethod(_ e: EventDecl) -> String {
    let signature = e.params.map { p in
        "\(camelCase(p.id)): \(p.kind.swiftType)\(p.optional ? "? = nil" : "")"
    }.joined(separator: ", ")

    var body: [String] = []
    if e.params.isEmpty {
        body.append("        SM._record(\"\(e.eventName)\", params: [:])")
    } else {
        let required = e.params.filter { !$0.optional }
        let optional = e.params.filter { $0.optional }
        let entries = required
            .map { "\"\($0.id)\": .\($0.kind.valueCase)(\(camelCase($0.id)))" }
            .joined(separator: ", ")
        body.append("        var params: [String: SM.ParamValue] = [\(entries.isEmpty ? ":" : entries)]")
        for p in optional {
            let c = camelCase(p.id)
            body.append("        if let \(c) { params[\"\(p.id)\"] = .\(p.kind.valueCase)(\(c)) }")
        }
        body.append("        SM._record(\"\(e.eventName)\", params: params)")
    }

    return "    public static func \(e.propertyName)(\(signature)) {\n"
        + body.joined(separator: "\n") + "\n    }"
}

private func camelCase(_ id: String) -> String {
    let parts = id.split(separator: "_")
    guard let first = parts.first else { return id }
    return ([String(first)] + parts.dropFirst().map { $0.capitalized }).joined()
}
