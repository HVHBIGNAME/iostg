import Foundation
import JavaScriptCore

// The compiler is a separately staged vendor asset. The transpile adapter is
// the exact source recovered from Beta 3.2, evaluated in a compiler-only VM.
final class WhitegramPluginTypeScript {
    private let context: JSContext

    static var isInstalled: Bool { return self.resourceURL("typescript-compiler") != nil }

    private static func resourceURL(_ name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "WhitegramPluginSDK") { return url }
        if let url = Bundle.main.url(forResource: "WhitegramPluginSDK", withExtension: "bundle"), let bundle = Bundle(url: url) {
            return bundle.url(forResource: name, withExtension: "js")
        }
        return nil
    }

    init() throws {
        guard let compilerURL = Self.resourceURL("typescript-compiler"), let adapterURL = Self.resourceURL("whitegram-typescript-transpiler") else {
            throw WhitegramPluginError("UNSUPPORTED_LANGUAGE", "A real TypeScript compiler asset is not bundled")
        }
        guard let context = JSContext(virtualMachine: JSVirtualMachine()) else { throw WhitegramPluginError("RUNTIME_UNAVAILABLE", "Cannot create TypeScript compiler context") }
        self.context = context
        let compiler = try WhitegramPluginStorage.readLimited(compilerURL, limit: 16 * 1024 * 1024)
        let adapter = try WhitegramPluginStorage.readLimited(adapterURL)
        guard let compilerSource = String(data: compiler, encoding: .utf8), let adapterSource = String(data: adapter, encoding: .utf8) else {
            throw WhitegramPluginError("INVALID_ENCODING", "TypeScript resources must be UTF-8")
        }
        context.evaluateScript("var module = {exports:{}}; var exports = module.exports;", withSourceURL: URL(string: "whitegram-compiler:///host.js"))
        context.evaluateScript(compilerSource, withSourceURL: compilerURL)
        if let exception = context.exception { throw WhitegramPluginError("COMPILER_ERROR", exception.toString() ?? "Compiler failed to initialize") }
        context.evaluateScript(adapterSource, withSourceURL: adapterURL)
        if let exception = context.exception { throw WhitegramPluginError("COMPILER_ERROR", exception.toString() ?? "Transpile adapter failed to initialize") }
        guard context.evaluateScript("typeof __wgTS === 'object' && typeof __wgTS.transpileModule === 'function' && typeof __wgTranspile === 'function'")?.toBool() == true else {
            throw WhitegramPluginError("COMPILER_ERROR", "Bundled asset does not expose the TypeScript compiler API")
        }
        _ = try self.transpile("const __wgCompilerProbe: number = 1;", filename: "compiler-probe.ts")
    }

    func transpile(_ source: String, filename: String) throws -> String {
        guard source.utf8.count <= WhitegramPluginStorage.maximumFileBytes, filename.utf8.count <= 1024 else { throw WhitegramPluginError("QUOTA_EXCEEDED", "TypeScript source is too large") }
        self.context.exception = nil
        let value = self.context.objectForKeyedSubscript("__wgTranspile")?.call(withArguments: [source, filename])
        if let exception = self.context.exception { throw WhitegramPluginError("COMPILER_ERROR", exception.toString() ?? "TypeScript transpilation failed") }
        guard let result = value?.toDictionary(), let ok = result["ok"] as? Bool else { throw WhitegramPluginError("COMPILER_ERROR", "Invalid transpile result") }
        guard ok, let code = result["code"] as? String else { throw WhitegramPluginError("TYPESCRIPT_ERROR", result["error"] as? String ?? "TypeScript compilation failed") }
        guard code.utf8.count <= 4 * 1024 * 1024 else { throw WhitegramPluginError("QUOTA_EXCEEDED", "TypeScript output exceeds 4 MiB") }
        return code
    }
}
