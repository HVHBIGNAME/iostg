import Foundation
public struct PeerId: Hashable {
    public let namespace: Int32
    public init(namespace: Int32) { self.namespace = namespace }
}
public struct MessageId: Hashable {
    public let peerId: PeerId
    public let namespace: Int32
    public let id: Int32
    public init(peerId: PeerId, namespace: Int32, id: Int32) { self.peerId = peerId; self.namespace = namespace; self.id = id }
}
public protocol MessageAttribute {}
