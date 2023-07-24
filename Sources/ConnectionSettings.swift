import Foundation

public struct ConnectionSettings {
    let password: String
    let userAgent: String
    let username: String

    public init(
        username: String = "neo4j",
        password: String = "neo4j",
        userAgent: String = "Bolt-Swift/0.9.5"
    ) {
        self.password = password
        self.userAgent = userAgent
        self.username = username
    }
}
