import Foundation
import PackStream

public struct Request {

    let command: Command
    let items: [PackProtocol]

    public enum Command: Byte {
        case initialize = 0x01
        case ack_failure = 0x0e
        case reset = 0x0f
        case run = 0x10
        // case setMode = 0x11
        case discard_all = 0x2f
        case pull_all = 0x3f
        case begin = 0x11
        case commit = 0x12
        case rollback = 0x13

        func toString() -> String {
            switch(self) {
            case .initialize:
                return "initialize"
            case .ack_failure:
                return "ack_failure"
            case .reset:
                return "reset"
            case .run:
                return "run"
            case .discard_all:
                return "discard_all"
            case .pull_all:
                return "pull_all"
            case .begin:
                return "begin"
            case .commit:
                return "commit"
            case .rollback:
                return "rollback"
//          case .setMode:
//              return "setMode"
            }
        }
    }

    enum RequestErrors: Error {
        case unchunkError
    }

    static let kMaxChunkSize = 65536

    private init(command: Command, items: [PackProtocol]) {
        self.command = command
        self.items = items
    }

    public static func initialize(settings: ConnectionSettings) -> Request {

        let agent = settings.userAgent

        
        let authMap = Map(dictionary: ["user_agent": agent, // TODO: Bolt-3 only
                                       "scheme": "basic",
                                       "principal": settings.username,
                                       "credentials": settings.password])
        
        // Bolt 1&2:
        /*
         let authMap = Map(dictionary: ["scheme": "basic",
                                       "principal": settings.username,
                                       "credentials": settings.password])

         return Request(command: .initialize, items: [agent, authMap])
         */

        return Request(command: .initialize, items: [authMap])
    }
    
    /*public static func setMode(_ mode: String) -> Request {
        let modeMap = Map(dictionary: ["mode": mode])
        return Request(command: .setMode, items: [modeMap])
    }*/
    
    public enum TransactionMode: String {
        case readonly = "r"
        case readwrite = "w"
    }
    
    public static func begin(
        mode: TransactionMode = .readonly,
        bookmarks: [String] = [],
        metadata: [String:String] = [:],
        timeoutInMs: UInt? = nil) -> Request {
        
        var dict: [String:PackProtocol] = ["mode": mode.rawValue]
        
        if bookmarks.count > 0 {
            dict["bookmarks"] = bookmarks
        }
        
        if metadata.count > 0 {
            dict["tx_metadata"] = Map(dictionary: metadata)
        }
        
        if let timeoutInMs = timeoutInMs {
            dict["tx_timeout"] = Int(timeoutInMs)
        }
        
        let modeMap = Map(dictionary: dict)
        return Request(command: .begin, items: [modeMap])
    }
    
    public static func commit() -> Request {
        return Request(command: .commit, items: [])
    }
    
    public static func rollback() -> Request {
        return Request(command: .rollback, items: [])
    }

    public static func ackFailure() -> Request {
        return Request(command: .ack_failure, items: [])
    }

    public static func reset() -> Request {
        return Request(command: .reset, items: [])
    }

    public static func run(statement: String) -> Request {
        // query, parameters and keyword parameters
        return Request(command: .run, items: [statement, Map.init(dictionary: [:]), Map.init(dictionary: [:])])
    }

    public static func run(statement: String, parameters: Map, keywordParameters: Map = Map(dictionary: [:])) -> Request {
        return Request(command: .run, items: [statement, parameters, keywordParameters])
    }

    public static func discardAll() -> Request {
        return Request(command: .discard_all, items: [])
    }

    public static func pullAll() -> Request {
        return Request(command: .pull_all, items: [])
    }

    public func chunk() throws -> [[Byte]] {

        do {
            let bytes = try self.pack()
            var chunks = [[Byte]]()
            let numChunks = ((bytes.count + 2) / Request.kMaxChunkSize) + 1
            for i in 0 ..< numChunks {

                let start = i * (Request.kMaxChunkSize - 2)
                var end = i == (numChunks - 1) ?
                    start + (Request.kMaxChunkSize - 4) :
                    start + (Request.kMaxChunkSize - 2) - 1
                if end >= bytes.count {
                    end = bytes.count - 1
                }

                let count = UInt16(end - start + 1)
                let countBytes = try count.pack()

                if i == (numChunks - 1) {
                    chunks.append(countBytes + bytes[start...end] + [ 0x00, 0x00 ])
                } else {
                    chunks.append(countBytes + bytes[start...end])
                }
            }

            return chunks

        } catch(let error) {
            throw error
        }
    }

    private func pack() throws -> [Byte] {
        let s = Structure(signature: command.rawValue, items: items)
        do {
            return try s.pack()
        } catch(let error) {
            throw error
        }
    }

    public static func unchunk(chunks: [[Byte]]) throws -> Request {

        throw RequestErrors.unchunkError
    }

}
