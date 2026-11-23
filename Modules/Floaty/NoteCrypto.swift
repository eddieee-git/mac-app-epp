import CryptoKit
import EppKit
import Foundation
import Security

/// 잠긴 메모의 본문 파일을 암호화한다. Epp 공통 암호화(`EppCrypto`, 키체인 "floaty-locked-notes")를 쓴다.
///
/// 예전 Floaty 방식(맨 앞 "FLTYENC1", 키체인 서비스 com.eddieee.Floaty)으로 잠근 메모도 읽을 수 있게 그 키는 읽기만 한다.
/// 그런 메모는 다음에 저장할 때 새 방식으로 바뀐다.
enum NoteCrypto {
    /// 점검할 때 넣으면 키체인을 쓰지 않고 이 키를 쓴다.
    static var testKey: SymmetricKey? {
        didSet { crypto = testKey.map { EppCrypto(testKey: $0) } ?? defaultCrypto }
    }
    private static let defaultCrypto = EppCrypto(account: "floaty-locked-notes")
    nonisolated(unsafe) private static var crypto = defaultCrypto

    private static let legacyMagic = Data("FLTYENC1".utf8)

    enum Failure: Error {
        case noKey, keychain(OSStatus), malformed
    }

    static func isEncrypted(_ data: Data) -> Bool {
        EppCrypto.isEncrypted(data) || data.starts(with: legacyMagic)
    }

    static func encrypt(_ plain: Data) throws -> Data {
        try crypto.encrypt(plain)
    }

    static func decrypt(_ data: Data) throws -> Data {
        if data.starts(with: legacyMagic) {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(legacyMagic.count))
            return try AES.GCM.open(box, using: legacyKey())
        }
        guard EppCrypto.isEncrypted(data) else { throw Failure.malformed }
        return try crypto.decrypt(data)
    }

    /// 예전 Floaty의 키. 없으면 만들지 않는다.
    private static func legacyKey() throws -> SymmetricKey {
        if let testKey { return testKey }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.eddieee.Floaty",
            kSecAttrAccount as String: "locked-notes-key",
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw status == errSecItemNotFound ? Failure.noKey : Failure.keychain(status)
        }
        return SymmetricKey(data: data)
    }
}
