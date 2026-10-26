// Synchronous test transport. Does not claim real SwiftSignalKit scheduling parity.
public enum NoError: Error {}
public protocol Disposable { func dispose() }
public final class ActionDisposable: Disposable {
    private var action: (() -> Void)?
    public init(_ action: @escaping () -> Void) { self.action = action }
    public func dispose() { let action = self.action; self.action = nil; action?() }
}
public final class Subscriber<T, E: Error> {
    private let next: (T) -> Void
    public init(_ next: @escaping (T) -> Void) { self.next = next }
    public func putNext(_ value: T) { next(value) }
}
public final class Signal<T, E: Error> {
    private let generator: (Subscriber<T, E>) -> Disposable
    public init(_ generator: @escaping (Subscriber<T, E>) -> Disposable) { self.generator = generator }
    public func start(next: @escaping (T) -> Void) -> Disposable { generator(Subscriber(next)) }
    public static func single(_ value: T) -> Signal<T, E> { Signal { $0.putNext(value); return ActionDisposable {} } }
}
precedencegroup SignalPipe {
    associativity: left
    higherThan: AssignmentPrecedence
}
infix operator |> : SignalPipe
public func |> <T, U>(left: T, right: (T) -> U) -> U { right(left) }
public func map<T, U, E>(_ transform: @escaping (T) -> U) -> (Signal<T, E>) -> Signal<U, E> {
    { source in Signal { subscriber in source.start { subscriber.putNext(transform($0)) } } }
}
public func mapToSignal<T, U, E>(_ transform: @escaping (T) -> Signal<U, E>) -> (Signal<T, E>) -> Signal<U, E> {
    { source in Signal { subscriber in
        var inner: Disposable?
        let outer = source.start { value in inner?.dispose(); inner = transform(value).start { subscriber.putNext($0) } }
        return ActionDisposable { outer.dispose(); inner?.dispose() }
    } }
}
