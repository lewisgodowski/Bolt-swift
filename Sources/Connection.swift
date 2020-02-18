import Foundation
import PackStream
import NIO

#if os(Linux)
import Dispatch
#endif

public class Connection: NSObject {

    private let settings: ConnectionSettings

    private var socket: SocketProtocol
    public var currentTransactionBookmark: String?
    
    public init(socket: SocketProtocol,
                settings: ConnectionSettings = ConnectionSettings() ) {

        self.socket = socket
        self.settings = settings

        super.init()
    }

    public func connect(completion: @escaping (_ success: Bool) throws -> Void) throws {
        try socket.connect(timeout: 2500 /* in ms */) {
            
            var eventLoop: EventLoop? = MultiThreadedEventLoopGroup.currentEventLoop
            if eventLoop == nil {
                let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
                eventLoop = eventLoopGroup.next()
            }
            guard let currentEventLoop = eventLoop else {
                print("Error getting current eventloop")
                return
            }
            
            self.initBolt(on: currentEventLoop).whenSuccess { wasSuccess in
                
                if wasSuccess == false {
                    print("Hmm, this was no success")
                    try? completion(false)
                    return
                }
            
                let initFuture = self.initialize(on: currentEventLoop)
                initFuture.map { (response) in
                    try? completion(true)
                }.whenFailure { error in
                    try? completion(false)
                }
            }
        }
    }

    public func disconnect() {
        socket.disconnect()
    }

    private func initBolt(on eventLoop: EventLoop) -> EventLoopFuture<Bool> {
        
        let initPromise = eventLoop.makePromise(of: Bool.self)
        
        self.socket.send(bytes: [0x60, 0x60, 0xB0, 0x17, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])?.whenSuccess { promise in

            var version: UInt32 = 0
            _ = try? self.socket.receive(expectedNumberOfBytes: 4).map { response -> (Bool) in
                let result = response.map { bytes -> Void in
                    do {
                        version = try UInt32.unpack(bytes[0..<bytes.count])
                        initPromise.succeed(version == 1)
                    } catch {
                        version = 0
                        initPromise.succeed(false)
                    }
                }
                
                return version == 1
            }
        }
        
        return initPromise.futureResult
        
    }
    
    private func initialize(on eventLoop: EventLoop) -> EventLoopFuture<Response> {
        let message = Request.initialize(settings: settings)
        let chunks = try? message.chunk()
        let sendFutures = chunks?.compactMap({ (chunk) -> EventLoopFuture<Void>? in
            socket.send(bytes: chunk)
        })
        
        let maxChunkSize = Int32(Request.kMaxChunkSize)
        
        let promise = eventLoop.makePromise(of: Response.self)
        var accumulatedData: [Byte] = []
        
        func loop() {
            // First, we call `read` to read in the next chunk and hop
            // over to `eventLoop` so we can safely write to `accumulatedChunks`
            // without a lock.
            do {
                try socket.receive(expectedNumberOfBytes: maxChunkSize)?.hop(to: eventLoop).map { responseData in
                    // Next, we just append the chunk to the accumulation
                    accumulatedData.append(contentsOf: responseData)
                    
                    // chunk terminated by 0x00 0x00
                    if (responseData[responseData.count - 1] == 0 && responseData[responseData.count - 2] == 0) == false {
                        loop()
                    } else {
                        
                        let unchunkedResponseDatas = try? Response.unchunk(accumulatedData)
                        for unchunkedResponseData in unchunkedResponseDatas ?? [] {
                            if let unpackedResponse = try? Response.unpack(unchunkedResponseData) {
                                if unpackedResponse.category != .success {
                                    promise.fail(ConnectionError.authenticationError)
                                    return
                                }
                                promise.succeed(unpackedResponse)
                            }
                        }
                    }
                }.cascadeFailure(to: promise) // if anything goes wrong, we fail the whole thing.

            } catch {
                promise.fail(error)
            }
            
        }

        loop()

        return promise.futureResult
    }

    public enum ConnectionError: Error {
        case unknownVersion
        case authenticationError
        case requestError
    }

    public enum CommandResponse: Byte {
        case success = 0x70
        case record = 0x71
        case ignored = 0x7e
        case failure = 0x7f
    }

    private func chunkAndSend(request: Request) throws {

        let chunks = try request.chunk()

        for chunk in chunks {
            try socket.send(bytes: chunk)
        }

    }

    private func parseMeta(_ meta: [PackProtocol]) {
        for item in meta {
            if let map = item as? Map {
                for (key, value) in map.dictionary {
                    switch key {
                    case "bookmark":
                        self.currentTransactionBookmark = value as? String
                    case "stats":
                        break
                    case "result_available_after":
                        break
                    case "result_consumed_after":
                        break
                    case "type":
                        break
                    case "fields":
                        break
                    default:
                        print("Couldn't parse metadata \(key): \(value)")
                    }
                }
            }
        }
    }

    public func request(_ request: Request) throws -> EventLoopFuture<[Response]>? {

        guard let eventLoop = MultiThreadedEventLoopGroup.currentEventLoop else {
            print("Error, could not get current eventloop")
            return nil
        }
        
        try chunkAndSend(request: request)

        let maxChunkSize = Int32(Request.kMaxChunkSize)
        
        let promise = eventLoop.makePromise(of: [Response].self)
        var accumulatedData: [Byte] = []
        
        func loop() {
            // First, we call `read` to read in the next chunk and hop
            // over to `eventLoop` so we can safely write to `accumulatedChunks`
            // without a lock.
            do {
                try socket.receive(expectedNumberOfBytes: maxChunkSize)?.hop(to: eventLoop).map { responseData in
                    // Next, we just append the chunk to the accumulation
                    
                    accumulatedData.append(contentsOf: responseData)

                    if responseData.count < 2 {
                        print("Error, got too little data back")
                        print(request)
                        print(request.command)
                        print(request.items)
                        loop()
                        return
                    }

                    // chunk terminated by 0x00 0x00
                    if (responseData[responseData.count - 1] == 0 && responseData[responseData.count - 2] == 0) == false {
                        loop()
                        return
                    }
                    
                    let unchunkedResponsesAsBytes = try? Response.unchunk(accumulatedData)

                    var responses = [Response]()
                    var success = true

                    for responseBytes in unchunkedResponsesAsBytes ?? [] {
                        if let response = try? Response.unpack(responseBytes) {
                            responses.append(response)

                            if let error = response.asError() {
                                print("Error! \(error)")
                                promise.fail(error)
                                return
                            }

                            if response.category != .record {
                                self.parseMeta(response.items)
                            }

                            success = success && response.category != .failure
                        } else {
                            print("Error: failed to parse response")
                            return
                        }
                    }

                    // Get more if not ending in a summary
                    if success == true && responses.count > 1 && responses.last!.category == .record {
                        loop()
                        return
                    }

                    promise.succeed(responses)
                        
                }.cascadeFailure(to: promise) // if anything goes wrong, we fail the whole thing.

            } catch {
                promise.fail(error)
            }
            
        }

        loop()
        
        return promise.futureResult
    }

}
