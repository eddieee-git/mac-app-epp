import CryptoKit
import Foundation
import Security

/// 기능이 디스크에 두는 개인 데이터(클립보드 기록 등)를 암호화한다(AES-GCM).
/// 키는 로그인 키체인에 기능마다 하나씩 둔다. 데이터 폴더만 복사되거나 백업(Time Machine 등)에서 꺼내져도 읽을 수 없다.
///
/// 새로 만드는 키는 Epp가 인증서("Epp Local Signing")로 서명돼 있으면 **Epp만** 묻지 않고 읽게 한다
/// (키체인이 앱의 서명 조건 = 번들 ID + 인증서를 기억하므로 다시 빌드·업데이트해도 그대로 읽는다).
/// 임시 서명이면 빌드마다 서명이 바뀌어 매번 키체인 암호를 묻게 되므로, 이 Mac의 내 계정으로 도는 모든 앱이 읽게 둔다.
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
        if let access = Self.makeAccess(label: "Epp \(account)") {
            query[kSecAttrAccess as String] = access
        }
        let added = SecItemAdd(query as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.keychain(added) }
        Self.cache[cacheKey] = key
        return key
    }

    /// 인증서로 서명돼 있으면 이 앱만, 임시 서명이면 모든 앱(nil 목록)이 묻지 않고 읽는 접근 권한.
    private static func makeAccess(label: String) -> SecAccess? {
        var trusted: CFArray?
        if isCertificateSigned {
            var me: SecTrustedApplication?
            if SecTrustedApplicationCreateFromPath(nil, &me) == errSecSuccess, let me {
                trusted = [me] as CFArray
            }
        }
        var access: SecAccess?
        guard SecAccessCreate(label as CFString, trusted, &access) == errSecSuccess else { return nil }
        return access
    }

    /// 지금 도는 Epp가 임시 서명이 아니라 인증서로 서명됐는지
    public static var isCertificateSigned: Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return false }
        let certificates = dict[kSecCodeInfoCertificates as String] as? [Any] ?? []
        return !certificates.isEmpty
    }
}
