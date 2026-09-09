import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct StoryMetricMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [SMEventsMacro.self]
}
