import Foundation
#if os(Linux)
import NIOSSL
#endif

public protocol CertificateValidatorProtocol {
    var hostname: String { get }
    var port: UInt { get }

#if os(Linux)
    var trustedCertificates: [NIOSSLCertificateSource] { get }
#else
    var trustedCertificates: [SecCertificate] { get }
#endif

    func shouldTrustCertificate(withSHA1: String) -> Bool
    func didTrustCertificate(withSHA1: String)
}
