import Foundation
import PackStream
import NIO

public protocol SocketProtocol {

    func connect(timeout: Int, completion: @escaping (Error?) -> ()) throws
    func send(bytes: [Byte]) -> EventLoopFuture<Void>?
    func receive(expectedNumberOfBytes: Int32) throws -> EventLoopFuture<[Byte]>?
    func disconnect()
}
