import Foundation
import CommonCrypto
import SQLite3

/// Reads and decrypts Claude desktop app cookies from the local SQLite store.
/// Verified scheme: AES-128-CBC, IV = 16 spaces, key = PBKDF2-SHA1("Claude Safe
/// Storage" passphrase, salt "saltysalt", 1003 iterations). Electron prefixes
/// each decrypted value with a 32-byte domain hash that must be stripped.
enum CookieError: Error, CustomStringConvertible {
    case keychainUnavailable
    case databaseUnreadable(String)
    case sessionKeyMissing

    var description: String {
        switch self {
        case .keychainUnavailable: return "Cannot read 'Claude Safe Storage' from Keychain"
        case .databaseUnreadable(let m): return "Cannot read Cookies DB: \(m)"
        case .sessionKeyMissing: return "sessionKey cookie not found — log in to Claude"
        }
    }
}

struct ClaudeCredentials {
    let cookieHeader: String
    let organizationId: String
}

struct CookieDecryptor {
    private static let salt = "saltysalt"
    private static let iterations: UInt32 = 1003
    private static let keyLength = 16
    private static let domainHashPrefixLength = 32

    private let dbPath: String

    init() {
        let cookies = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/Cookies")
        self.dbPath = cookies.path
    }

    func loadCredentials() throws -> ClaudeCredentials {
        let key = try deriveKey()
        let cookies = try readCookies(decryptingWith: key)

        guard cookies["sessionKey"]?.isEmpty == false else {
            throw CookieError.sessionKeyMissing
        }
        let org = cookies["lastActiveOrg"] ?? ""
        let header = cookies
            .filter { !$0.value.isEmpty }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
        return ClaudeCredentials(cookieHeader: header, organizationId: org)
    }

    // MARK: - Keychain passphrase → AES key

    private func deriveKey() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let passphrase = item as? Data else {
            throw CookieError.keychainUnavailable
        }

        var derived = Data(count: Self.keyLength)
        let saltData = Data(Self.salt.utf8)
        let result = derived.withUnsafeMutableBytes { derivedPtr in
            saltData.withUnsafeBytes { saltPtr in
                passphrase.withUnsafeBytes { passPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr.baseAddress!.assumingMemoryBound(to: Int8.self),
                        passphrase.count,
                        saltPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        Self.iterations,
                        derivedPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        Self.keyLength
                    )
                }
            }
        }
        guard result == kCCSuccess else { throw CookieError.keychainUnavailable }
        return derived
    }

    // MARK: - SQLite read + AES decrypt

    private func readCookies(decryptingWith key: Data) throws -> [String: String] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            throw CookieError.databaseUnreadable(msg)
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT name, encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CookieError.databaseUnreadable(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var result: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(stmt, 0) else { continue }
            let name = String(cString: namePtr)
            let blobLen = Int(sqlite3_column_bytes(stmt, 1))
            guard blobLen > 0, let blob = sqlite3_column_blob(stmt, 1) else { continue }
            let encrypted = Data(bytes: blob, count: blobLen)
            if let value = decrypt(encrypted, key: key) {
                result[name] = value
            }
        }
        return result
    }

    private func decrypt(_ data: Data, key: Data) -> String? {
        guard data.count > 3 else {
            return String(data: data, encoding: .utf8)
        }
        let prefix = String(data: data.prefix(3), encoding: .ascii)
        guard prefix == "v10" || prefix == "v11" else {
            return String(data: data, encoding: .utf8)
        }
        let payload = data.subdata(in: 3..<data.count)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128) // 16 spaces

        let outputCapacity = payload.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outPtr in
            payload.withUnsafeBytes { inPtr in
                iv.withUnsafeBytes { ivPtr in
                    key.withUnsafeBytes { keyPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, payload.count,
                            outPtr.baseAddress, outputCapacity,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.removeSubrange(moved..<output.count)

        // Electron prepends a 32-byte SHA-256 domain hash before the real value.
        if output.count > Self.domainHashPrefixLength {
            let stripped = output.subdata(in: Self.domainHashPrefixLength..<output.count)
            if let s = String(data: stripped, encoding: .utf8), !s.isEmpty {
                return s
            }
        }
        return String(data: output, encoding: .utf8)
    }
}
