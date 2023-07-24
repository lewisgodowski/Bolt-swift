import Foundation
import PackStream
import NIO

public protocol SocketProtocol {
    // async/await
    func connect(timeout: TimeAmount) async throws
    func send(bytes: [Byte]) async throws
    func receive(expectedNumberOfBytes: Int32) async throws -> [Byte]

    func connect(timeout: Int, completion: @escaping (Error?) -> ()) throws
    func send(bytes: [Byte]) -> EventLoopFuture<Void>?
    func receive(expectedNumberOfBytes: Int32) throws -> EventLoopFuture<[Byte]>?
    func disconnect()
}
