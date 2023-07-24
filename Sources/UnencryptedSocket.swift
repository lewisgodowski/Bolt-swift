import Foundation
import PackStream
import NIO
import NIOTransportServices

internal protocol Bootstrap {
    // async/await
    func connect(host: String, port: Int) async throws -> Channel

    func connect(host: String, port: Int) -> EventLoopFuture<Channel>
}

#if os(Linux)
extension ClientBootstrap: Bootstrap {}
#else
extension NIOTSConnectionBootstrap: Bootstrap {
    func connect(host: String, port: Int) async throws -> Channel {
        try await connect(host: host, port: port).get()
    }
}
#endif

struct PromiseHolder {
    let uuid: UUID = UUID()
    let promise: EventLoopPromise<Array<UInt8>>
}

public class UnencryptedSocket {
    var cnt = 1

    let hostname: String
    let port: Int

    var group: EventLoopGroup?
    var bootstrap: Bootstrap?
    var channel: Channel?

    var activePromises: [PromiseHolder] = []

    fileprivate static let readBufferSize = 8192

    let dataHandler = ReadDataHandler()

    public init(hostname: String, port: Int) throws {
        self.hostname = hostname
        self.port = port
    }

#if os(Linux)
    func setupBootstrap(_ group: MultiThreadedEventLoopGroup, _ dataHandler: ReadDataHandler) -> (Bootstrap) {
        ClientBootstrap(group: MultiThreadedEventLoopGroup(numberOfThreads: 1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { $0.pipeline.addHandler(dataHandler) }
    }
#else
    func setupBootstrap(_ group: MultiThreadedEventLoopGroup, _ dataHandler: ReadDataHandler) -> (Bootstrap) {
        NIOTSConnectionBootstrap(group: NIOTSEventLoopGroup(loopCount: 1, defaultQoS: .utility))
            .channelInitializer { $0.pipeline.addHandlers([dataHandler], position: .last) }
    }
#endif

    public func connect(timeout: Int, completion: @escaping (Error?) -> ()) throws {

        self.dataHandler.dataReceivedBlock = { data in
            //print("Got \(data.count) bytes: ")
            //print(Data(bytes: data, count: data.count).hexEncodedString())
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
        // print("#1")
        _ = bootstrap.connectTimeout(TimeAmount.milliseconds(Int64(timeout)))
        bootstrap.connect(host: hostname, port: port).map{ theChannel -> Void in
            self.channel = theChannel
        }.whenComplete { (result) in
            
            switch result {
            case let .failure(error):
                completion(error)
            case .success(_):
                completion(nil)
            }
        }
/*
        }.whenSuccess { _ in
            completion()
        }*/
        
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
    public func connect(timeout: TimeAmount) async throws {
        dataHandler.dataReceivedBlock = { [weak self] data in
            if let promise = self?.activePromises.first?.promise {
                promise.succeed(data)
            }
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

#if os(Linux)
        let bootstrap = setupBootstrap(group, self.dataHandler) as! ClientBootstrap
#else
        let bootstrap = setupBootstrap(group, dataHandler) as! NIOTSConnectionBootstrap
#endif

        self.bootstrap = bootstrap
        _ = bootstrap.connectTimeout(timeout)
        self.channel = try await bootstrap.connect(host: hostname, port: port)
    }

    public func send(bytes: [Byte]) async throws {
        guard let channel else { throw Response.ResponseError.requestInvalid(message: "No channel") }

        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)

        try await channel.writeAndFlush(buffer)
    }

    public func send(bytes: [Byte]) -> EventLoopFuture<Void>? {

        guard let channel = channel else { return nil }

        let didSendFuture: EventLoopPromise<Void>  = channel.eventLoop.makePromise()
        
        
        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        
        // let c = cnt
        // cnt = cnt + 1
        
        // print("\nSend #\(c)")
        // print(Data(bytes: bytes, count: bytes.count).hexEncodedString())
        
        channel.writeAndFlush(buffer).whenComplete { result in
            // print("Did send #\(c)")
            switch result {
            case .failure(let error):
                print(String(describing: error))
                didSendFuture.fail(error)
            case .success(_):
                didSendFuture.succeed(())
            }
        }
        
        return didSendFuture.futureResult
    }

    public func receive(expectedNumberOfBytes: Int32) async throws -> [Byte] {
        // Using an async/await wrapper until the underlying `receive(expectedNumberOfBytes:)` method can be converted.
        guard let bytes = try await receive(expectedNumberOfBytes: expectedNumberOfBytes)?.get() else {
            throw Response.ResponseError.requestInvalid(message: "Failed to receive bytes.")
        }
        return bytes
    }

    public func receive(expectedNumberOfBytes: Int32) throws -> EventLoopFuture<[Byte]>? {

        guard let readPromise = channel?.eventLoop.makePromise(of: [Byte].self) else {
            return nil
        }
        
        // print("Made new promise")
        //self.readPromise = readPromise
        let holder = PromiseHolder(promise: readPromise)
        self.activePromises.append(holder)
        // print("now we've got active promises: \(self.activePromises.count)")

        self.channel?.read()

        readPromise.futureResult.whenComplete { (_) in
            self.activePromises = self.activePromises.filter { $0.uuid != holder.uuid }
            // print("result, active promises: \(self.activePromises.count)")
        }
        
        return readPromise.futureResult
    }

    public func disconnect() {
        try? channel?.close(mode: .all).wait()
        try? group?.syncShutdownGracefully()
    }
}

// TODO: Remove debug tool
extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let hexDigits = Array((options.contains(.upperCase) ? "0123456789ABCDEF" : "0123456789abcdef").utf16)
        var chars: [unichar] = []
        chars.reserveCapacity(2 * count)
        for byte in self {
            chars.append(hexDigits[Int(byte / 16)])
            chars.append(hexDigits[Int(byte % 16)])
            chars.append(contentsOf: ", 0x".utf16)
        }
        return String(utf16CodeUnits: chars, count: chars.count)
    }
}
