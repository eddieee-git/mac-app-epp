import CryptoKit
import Foundation
import Security

/// 기능이 디스크에 두는 개인 데이터(클립보드 기록 등)를 암호화한다(AES-GCM).
/// 키는 로그인 키체인에 기능마다 하나씩 둔다. 데이터 폴더만 복사되거나 백업(Time Machine 등)에서 꺼내져도 읽을 수 없다.
///
/// 한계: Epp는 임시 서명이라 빌드마다 서명이 바뀐다. 키체인 항목을 "Epp만"으로 막으면 업데이트할 때마다 키체인 암호를 물어서,
/// 이 Mac의 내 계정으로 도는 다른 앱이 묻지 않고 읽을 수 있게 만든다(스티커의 잠금 키와 같은 방식).
public struct EppCrypto: Sendable {
    /// 암호화한 파일 맨 앞 표시. 이 표시가 없으면 예전 평문 파일로 보고 그대로 읽는다.
    static let magic = Data("EPPENC1".utf8)

    public enum Failure: Error {
        case noKey, keychain(OSStatus), malformed
    }

    private let service: String
    private let account: String
    private let fixedKey: SymmetricKey?

    /// service: 키체인 서비스(보통 번들 ID — Epp와 Epp Dev가 따로), account: 기능마다 다른 이름(예: "keepy-history")
    public init(service: String = Bundle.main.bundleIdentifier ?? "com.eddieee.Epp", account: String) {
        self.service = service
        self.account = account
        fixedKey = nil
    }

    /// 점검용: 키체인을 쓰지 않고 이 키를 쓴다.
    public init(testKey: SymmetricKey) {
        service = ""
        account = ""
        fixedKey = testKey
    }

    public static func isEncrypted(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    public func encrypt(_ plain: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key(createIfMissing: true)).combined else {
            throw Failure.malformed
        }
        return Self.magic + combined
    }

    /// 암호화한 데이터면 풀고, 예전 평문이면 그대로 돌려준다.
    public func decrypt(_ data: Data) throws -> Data {
        guard Self.isEncrypted(data) else { return data }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.magic.count))
        return try AES.GCM.open(box, using: key(createIfMissing: false))
    }

    // MARK: - 키

    nonisolated(unsafe) private static var cache: [String: SymmetricKey] = [:]
    private static let lock = NSLock()

    private func key(createIfMissing: Bool) throws -> SymmetricKey {
        if let fixedKey { return fixedKey }
        let cacheKey = service + "/" + account
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let cached = Self.cache[cacheKey] { return cached }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            let key = SymmetricKey(data: data)
            Self.cache[cacheKey] = key
            return key
        }
        guard status == errSecItemNotFound else { throw Failure.keychain(status) }
        guard createIfMissing else { throw Failure.noKey }

        let key = SymmetricKey(size: .bits256)
        query.removeValue(forKey: kSecReturnData as String)
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        query[kSecAttrLabel as String] = "Epp \(account)"
        var access: SecAccess?
        // 신뢰할 앱 목록을 nil로 주면 묻지 않고 읽는다(위 "한계" 참고).
        if SecAccessCreate("Epp \(account)" as CFString, nil, &access) == errSecSuccess, let access {
            query[kSecAttrAccess as String] = access
        }
        let added = SecItemAdd(query as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.keychain(added) }
        Self.cache[cacheKey] = key
        return key
    }
}
