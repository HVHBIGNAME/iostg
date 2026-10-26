import Foundation
import CoreFoundation

public struct WhitegramPluginServiceError: Error {
    public let code: String
    public let message: String

    fileprivate init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }
}

public final class WhitegramPluginServiceRegistration {
    private let lock = NSLock()
    private var cancellation: (() -> Void)?

    fileprivate init(_ cancellation: @escaping () -> Void) { self.cancellation = cancellation }

    public func dispose() {
        self.lock.lock()
        let cancellation = self.cancellation
        self.cancellation = nil
        self.lock.unlock()
        cancellation?()
    }

    deinit { self.dispose() }
}

// Only copied JSON crosses queues. A provider's account, queue and JavaScript
// callbacks remain owned by its runtime; consumers cannot supply a provider ID.
public final class WhitegramPluginServices {
    public static let shared = WhitegramPluginServices()

    private final class Provider {
        weak var scope: AnyObject?
        let owner: String
        let name: String
        let version: String
        let id = UUID().uuidString
        let queue: DispatchQueue
        let permitted: () -> Bool
        let invoke: (String, [Any], String, String) -> Void

        init(scope: AnyObject, owner: String, name: String, version: String, queue: DispatchQueue,
             permitted: @escaping () -> Bool, invoke: @escaping (String, [Any], String, String) -> Void) {
            self.scope = scope; self.owner = owner; self.name = name; self.version = version
            self.queue = queue; self.permitted = permitted; self.invoke = invoke
        }
    }

    private struct Call {
        let provider: Provider
        let consumer: String
        let permitted: () -> Bool
        let completion: (Result<Any, WhitegramPluginServiceError>) -> Void
    }

    private let lock = NSLock()
    private var providers: [Provider] = []
    private var calls: [String: Call] = [:]

    public init() {}

    public func register(scope: AnyObject, owner: String, name: String, version: String, queue: DispatchQueue,
                         permitted: @escaping () -> Bool, invoke: @escaping (String, [Any], String, String) -> Void) throws -> WhitegramPluginServiceRegistration {
        guard !name.isEmpty, name.utf8.count <= 128, !name.unicodeScalars.contains(where: { $0.value < 32 }),
              !version.isEmpty, version.utf8.count <= 128 else {
            throw WhitegramPluginServiceError("INVALID_ARGUMENT", "Invalid service name or version")
        }
        let provider = Provider(scope: scope, owner: owner, name: name, version: version, queue: queue, permitted: permitted, invoke: invoke)
        self.lock.lock()
        self.providers.removeAll { $0.scope == nil }
        let previous = self.providers.first { $0.scope === scope && $0.name == name }
        if let previous = previous, previous.owner != owner {
            self.lock.unlock()
            throw WhitegramPluginServiceError("SERVICE_CONFLICT", "Service \(name) already belongs to another plugin")
        }
        guard previous != nil || self.providers.filter({ $0.scope === scope }).count < 128 else {
            self.lock.unlock()
            throw WhitegramPluginServiceError("QUOTA_EXCEEDED", "Account service quota exceeded")
        }
        self.providers.removeAll { $0 === previous }
        self.providers.append(provider)
        self.lock.unlock()
        if let previous = previous { self.cancelCalls(provider: previous) }
        return WhitegramPluginServiceRegistration { [weak self, weak provider] in
            guard let self = self, let provider = provider else { return }
            self.lock.lock()
            self.providers.removeAll { $0 === provider }
            self.lock.unlock()
            self.cancelCalls(provider: provider)
        }
    }

    public func list(scope: AnyObject) -> [[String: Any]] {
        self.lock.lock()
        let providers = self.providers.filter { $0.scope === scope }
        self.lock.unlock()
        return providers.filter { $0.permitted() }.sorted { $0.name < $1.name }.map {
            ["name": $0.name, "version": $0.version, "pluginId": $0.owner]
        }
    }

    public func call(scope: AnyObject, consumer: String, name: String, method: String, arguments: [Any],
                     permitted: @escaping () -> Bool, completion: @escaping (Result<Any, WhitegramPluginServiceError>) -> Void) throws -> WhitegramPluginServiceRegistration {
        guard !method.isEmpty, method.utf8.count <= 128, arguments.count <= 128,
              !["__proto__", "constructor", "prototype"].contains(method), permitted() else {
            throw WhitegramPluginServiceError("INVALID_ARGUMENT", "Invalid service method, arguments or stopped consumer")
        }
        guard let arguments = try self.copyJSON(arguments) as? [Any] else {
            throw WhitegramPluginServiceError("INVALID_ARGUMENT", "Service arguments must be a JSON array")
        }
        self.lock.lock()
        guard let provider = self.providers.first(where: { $0.scope === scope && $0.name == name }) else {
            self.lock.unlock()
            throw WhitegramPluginServiceError("SERVICE_NOT_FOUND", name)
        }
        guard self.calls.count < 512, self.calls.values.filter({ $0.provider.scope === scope && $0.consumer == consumer }).count < 128 else {
            self.lock.unlock()
            throw WhitegramPluginServiceError("QUOTA_EXCEEDED", "Too many pending service calls")
        }
        let token = UUID().uuidString
        self.calls[token] = Call(provider: provider, consumer: consumer, permitted: permitted, completion: completion)
        self.lock.unlock()
        provider.queue.async { [weak self, weak provider] in
            guard let self = self, let provider = provider else { return }
            self.lock.lock()
            let pending = self.calls[token] != nil && self.providers.contains(where: { $0 === provider })
            self.lock.unlock()
            guard pending else { return }
            guard provider.scope != nil, provider.permitted(), permitted() else {
                self.finish(token, result: .failure(WhitegramPluginServiceError("SERVICE_UNAVAILABLE", name)))
                return
            }
            provider.invoke(method, arguments, token, consumer)
        }
        return WhitegramPluginServiceRegistration { [weak self] in
            self?.finish(token, result: .failure(WhitegramPluginServiceError("SERVICE_CANCELLED", name)))
        }
    }

    public func resolve(scope: AnyObject, owner: String, token: String, response: [String: Any]) throws -> Bool {
        self.lock.lock()
        let call = self.calls[token]
        self.lock.unlock()
        guard let call = call, call.provider.scope === scope, call.provider.owner == owner else { return false }
        guard call.provider.permitted(), call.permitted() else {
            self.finish(token, result: .failure(WhitegramPluginServiceError("SERVICE_UNAVAILABLE", call.provider.name)))
            return false
        }
        guard let flag = response["ok"] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else {
            throw WhitegramPluginServiceError("INVALID_ARGUMENT", "Service response needs a boolean ok flag")
        }
        let ok = flag.boolValue
        if ok {
            self.finish(token, result: .success(try self.copyJSON(response["value"] ?? NSNull())))
        } else {
            let error = (response["error"] as? [String: Any]) ?? [:]
            self.finish(token, result: .failure(WhitegramPluginServiceError(String((error["code"] as? String ?? "SERVICE_ERROR").prefix(128)), String((error["message"] as? String ?? "Service failed").prefix(8192)))))
        }
        return true
    }

    private func copyJSON(_ value: Any) throws -> Any {
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        guard bytes.count <= 4 * 1024 * 1024 else { throw WhitegramPluginServiceError("QUOTA_EXCEEDED", "Service payload exceeds 4 MiB") }
        return try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
    }

    private func finish(_ token: String, result: Result<Any, WhitegramPluginServiceError>) {
        self.lock.lock()
        let call = self.calls.removeValue(forKey: token)
        self.lock.unlock()
        call?.completion(result)
    }

    private func cancelCalls(provider: Provider) {
        self.lock.lock()
        let pending = self.calls.filter { $0.value.provider === provider }
        for token in pending.keys { self.calls.removeValue(forKey: token) }
        self.lock.unlock()
        for call in pending.values { call.completion(.failure(WhitegramPluginServiceError("SERVICE_UNAVAILABLE", provider.name))) }
    }
}
