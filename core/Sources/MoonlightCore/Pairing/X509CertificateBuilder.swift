import Foundation
import Security

struct X509CertificateBuildResult {
    let certificateDER: Data
    let certificatePEM: Data
    let signature: Data
}

enum X509CertificateBuilder {
    static func buildSelfSignedCertificate(publicKeyDER: Data, privateKey: SecKey, commonName: String, now: Date = Date()) throws -> X509CertificateBuildResult {
        let signatureAlgorithm = ASN1DERWriter.sequence([
            ASN1DERWriter.objectIdentifier([1, 2, 840, 113549, 1, 1, 11]),
            ASN1DERWriter.null()
        ])

        let name = ASN1DERWriter.sequence([
            ASN1DERWriter.set([
                ASN1DERWriter.sequence([
                    ASN1DERWriter.objectIdentifier([2, 5, 4, 3]),
                    ASN1DERWriter.utf8String(commonName)
                ])
            ])
        ])

        let validity = ASN1DERWriter.sequence([
            ASN1DERWriter.utcTime(now.addingTimeInterval(-60)),
            ASN1DERWriter.utcTime(now.addingTimeInterval(60 * 60 * 24 * 365 * 20))
        ])

        let subjectPublicKeyInfo = ASN1DERWriter.sequence([
            ASN1DERWriter.sequence([
                ASN1DERWriter.objectIdentifier([1, 2, 840, 113549, 1, 1, 1]),
                ASN1DERWriter.null()
            ]),
            ASN1DERWriter.bitString(publicKeyDER)
        ])

        let serialNumber = try PairingCrypto.randomBytes(count: 16)

        let tbsCertificate = ASN1DERWriter.sequence([
            ASN1DERWriter.contextSpecificConstructed(tagNumber: 0, value: ASN1DERWriter.integer(2)),
            ASN1DERWriter.integer(serialNumber),
            signatureAlgorithm,
            name,
            validity,
            name,
            subjectPublicKeyInfo
        ])

        let signature = try PairingCrypto.sign(privateKey: privateKey, message: tbsCertificate)
        let certificateDER = ASN1DERWriter.sequence([
            tbsCertificate,
            signatureAlgorithm,
            ASN1DERWriter.bitString(signature)
        ])

        return X509CertificateBuildResult(
            certificateDER: certificateDER,
            certificatePEM: PairingCrypto.pemEncode(certificateDER, header: "CERTIFICATE"),
            signature: signature
        )
    }
}
