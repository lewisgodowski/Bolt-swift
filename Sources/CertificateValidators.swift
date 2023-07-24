import Foundation
#if os(Linux)
import NIOSSL
#endif

public class UnsecureCertificateValidator: CertificateValidatorProtocol {
    public let hostname: String
    public let port: UInt

#if os(Linux)
    public let trustedCertificates: [NIOSSLCertificateSource]
#else
    public let trustedCertificates: [SecCertificate]
#endif

    public init(hostname: String, port: UInt) {
        self.hostname = hostname
        self.port = port
        self.trustedCertificates = []
    }

    public func shouldTrustCertificate(withSHA1: String) -> Bool {
        true
    }

    public func didTrustCertificate(withSHA1: String) { }
}

#if os(Linux)
#else

public class TrustRootOnlyCertificateValidator: CertificateValidatorProtocol {
    public let hostname: String
    public let port: UInt
    public let trustedCertificates: [SecCertificate]

    public init(hostname: String, port: UInt) {
        self.hostname = hostname
        self.port = port
        self.trustedCertificates = []
    }

    public func shouldTrustCertificate(withSHA1: String) -> Bool {
        false
    }

    public func didTrustCertificate(withSHA1: String) { }
}

public class TrustSpecificOrRootCertificateValidator: CertificateValidatorProtocol {
    public let hostname: String
    public let port: UInt
    public let trustedCertificates: [SecCertificate]

    public init(hostname: String, port: UInt, trustedCertificate: SecCertificate) {
        self.hostname = hostname
        self.port = port
        self.trustedCertificates = [trustedCertificate]
    }

    public init(hostname: String, port: UInt, trustedCertificates: [SecCertificate]) {
        self.hostname = hostname
        self.port = port
        self.trustedCertificates = trustedCertificates
    }

    public init(hostname: String, port: UInt, trustedCertificateAtPath path: String) {
        self.hostname = hostname
        self.port = port

        if let cert = SecCertificateCreateWithData(
            nil,
            try! Data(contentsOf: URL(fileURLWithPath: path)) as CFData
        ) {
            self.trustedCertificates = [cert]
        } else {
            print("Bolt: Path '\(path)' did not contain a valid certificate, continuing without")
            self.trustedCertificates = []
        }
    }

    public func shouldTrustCertificate(withSHA1: String) -> Bool {
        false
    }

    public func didTrustCertificate(withSHA1: String) { }
}

public class StoreCertSignaturesInFileCertificateValidator: CertificateValidatorProtocol {
    public let filePath: String
    public let hostname: String
    public let port: UInt
    public let trustedCertificates: [SecCertificate]

    lazy var fileManager = FileManager.default

    public init(hostname: String, port: UInt, filePath path: String) {
        self.filePath = path
        self.hostname = hostname
        self.port = port
        self.trustedCertificates = []
    }

    public func shouldTrustCertificate(withSHA1 testSHA1: String) -> Bool {
        let keysForHosts = readKeysForHosts()
        let key = "\(hostname):\(port)"

        if let trueSHA1 = keysForHosts[key] {
            return trueSHA1 == testSHA1
        }

        trustSHA1(key: key, testSHA1)

        return true
    }

    public func didTrustCertificate(withSHA1 testSHA1: String) {
        let keysForHosts = readKeysForHosts()
        let key = "\(hostname):\(port)"

        guard keysForHosts[key] == nil else { return }

        trustSHA1(key: key, testSHA1)
    }

    private func readKeysForHosts() -> [String: String] {
        var propertyListFormat =  PropertyListSerialization.PropertyListFormat.xml
        var keysForHosts = [String: String]()

        if let plistXML = FileManager.default.contents(atPath: filePath) {
            do {
                keysForHosts = try PropertyListSerialization.propertyList(
                    from: plistXML,
                    options: .mutableContainersAndLeaves,
                    format: &propertyListFormat
                ) as? [String: String] ?? [:]
            } catch {
                print("Error reading plist: \(error), format: \(propertyListFormat)")
            }
        }

        return keysForHosts
    }

    private func trustSHA1(key: String, _ SHA1: String) {
        var propertyListFormat =  PropertyListSerialization.PropertyListFormat.xml
        var keysForHosts = readKeysForHosts()

        if fileManager.fileExists(atPath: filePath) {
            let plistXML = fileManager.contents(atPath: filePath)!
            do {
                keysForHosts = try PropertyListSerialization.propertyList(
                    from: plistXML,
                    options: .mutableContainersAndLeaves,
                    format: &propertyListFormat
                ) as! [String: String]
            } catch {
                print("Error reading plist: \(error), format: \(propertyListFormat)")
            }
        }

        keysForHosts[key] = SHA1

        if let data = try? PropertyListSerialization.data(
            fromPropertyList: keysForHosts,
            format: propertyListFormat,
            options: 0
        ) {
            let url = URL(fileURLWithPath: filePath)
            try? data.write(to: url)
        }
    }
}
#endif
