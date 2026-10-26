public enum NoError: Error {}
public struct Signal<Value, Failure: Error> {
    public let value: Value?
    public init(_ value: Value?) { self.value = value }
    public static func complete() -> Self { Self(nil) }
}
precedencegroup PipePrecedence {
    associativity: left
    higherThan: AssignmentPrecedence
}
infix operator |> : PipePrecedence
public func |> <A, B>(value: A, f: (A) -> B) -> B { f(value) }
public func mapToSignal<A, B, E>(_ f: @escaping (A) -> Signal<B, E>) -> (Signal<A, E>) -> Signal<B, E> {
    return { signal in signal.value.map(f) ?? .complete() }
}
public final class Queue { public static func mainQueue() -> Queue { Queue() } }
public func delay<T, E>(_ seconds: Double, queue: Queue) -> (Signal<T, E>) -> Signal<T, E> { { $0 } }
public func then<T, E>(_ next: Signal<T, E>) -> (Signal<T, E>) -> Signal<T, E> { { _ in next } }
