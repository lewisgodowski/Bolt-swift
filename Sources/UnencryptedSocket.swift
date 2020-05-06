import Foundation
import PackStream
import NIO
import NIOTransportServices

internal protocol Bootstrap {
    func connect(host: String, port: Int) -> EventLoopFuture<Channel>
}

#if os(Linux)
extension ClientBootstrap: Bootstrap {}
#else
extension NIOTSConnectionBootstrap: Bootstrap {}
#endif

struct PromiseHolder {
    let uuid: UUID = UUID()
    let promise: EventLoopPromise<Array<UInt8>>
}

public class UnencryptedSocket {

    let hostname: String
    let port: Int

    var group: EventLoopGroup?
    var bootstrap: Bootstrap?
    var channel: Channel?

    //var readGroup: DispatchGroup?
    // var readPromise: EventLoopPromise<[Byte]>?
    var activePromises: [PromiseHolder] = []
    //var receivedData: [UInt8] = []

    fileprivate static let readBufferSize = 8192

    let dataHandler = ReadDataHandler()

    public init(hostname: String, port: Int) throws {
        self.hostname = hostname
        self.port = port
    }

    #if os(Linux)

    // Linux version
    func setupBootstrap(_ group: MultiThreadedEventLoopGroup, _ dataHandler: ReadDataHandler) -> (Bootstrap) {

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        return ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                return channel.pipeline.addHandler(dataHandler)
            }
    }

    #else

    // Apple version
    func setupBootstrap(_ group: MultiThreadedEventLoopGroup, _ dataHandler: ReadDataHandler) -> (Bootstrap) {

        let overrideGroup = NIOTSEventLoopGroup(loopCount: 1, defaultQoS: .utility)

        return NIOTSConnectionBootstrap(group: overrideGroup)
            .channelInitializer { channel in
                print("#2")
                return channel.pipeline.addHandlers([dataHandler], position: .last)
        }
    }

    #endif

    public func connect(timeout: Int, completion: @escaping () -> ()) throws {

        self.dataHandler.dataReceivedBlock = { data in
            print("Got \(data.count) bytes")
            if let promise = self.activePromises.first?.promise {
                promise.succeed(data)
            }
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        #if os(Linux)
        let bootstrap = setupBootstrap(group, self.dataHandler) as! ClientBootstrap
        #else
        let bootstrap = setupBootstrap(group, self.dataHandler) as! NIOTSConnectionBootstrap
        #endif

        self.bootstrap = bootstrap
        print("#1")
        bootstrap.connect(host: hostname, port: port).map{ theChannel -> Void in
            self.channel = theChannel

        }.whenSuccess { _ in
            completion()
        }
        
    }
}

extension Array where Element == Byte {
    func toString() -> String {
        return self.reduce("", { (oldResult, i) -> String in
            return oldResult + (oldResult == "" ? "" : ":") + String(format: "%02x", i)
        })
    }
}

extension UnencryptedSocket: SocketProtocol {

    public func disconnect() {
        try? channel?.close(mode: .all).wait()
        try? group?.syncShutdownGracefully()
    }

    public func send(bytes: [Byte]) -> EventLoopFuture<Void>? {

        print("\nSend")
        guard let channel = channel else { return nil }

        let didSendFuture: EventLoopPromise<Void>  = channel.eventLoop.makePromise()
        
        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        channel.writeAndFlush(buffer).whenSuccess { _ in
            didSendFuture.succeed(())
        }
        
        return didSendFuture.futureResult
    }
    

    public func receive(expectedNumberOfBytes: Int32) throws -> EventLoopFuture<[Byte]>? {

        guard let readPromise = channel?.eventLoop.makePromise(of: [Byte].self) else {
            return nil
        }
        
        print("Made new promise")
        //self.readPromise = readPromise
        let holder = PromiseHolder(promise: readPromise)
        self.activePromises.append(holder)
        print("now we've got active promises: \(self.activePromises.count)")

        self.channel?.read()

        readPromise.futureResult.whenComplete { (_) in
            self.activePromises = self.activePromises.filter { $0.uuid != holder.uuid }
            print("result, active promises: \(self.activePromises.count)")
        }
        
        return readPromise.futureResult
    }
}
