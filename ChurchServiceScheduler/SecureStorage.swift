import CryptoKit
import Foundation
import Security

enum SecureStorageError: LocalizedError {
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case randomBytesFailed(OSStatus)
    case invalidCiphertext
    case invalidBackup
    case missingBackupPassword

    var errorDescription: String? {
        switch self {
        case .keychainReadFailed(let status):
            return "Unable to read the database key from Keychain. Status: \(status)"
        case .keychainWriteFailed(let status):
            return "Unable to save the database key in Keychain. Status: \(status)"
        case .randomBytesFailed(let status):
            return "Unable to generate secure random bytes. Status: \(status)"
        case .invalidCiphertext:
            return "The local database file could not be decrypted."
        case .invalidBackup:
            return "The backup file is invalid or the password is incorrect."
        case .missingBackupPassword:
            return "Enter a backup password before exporting or importing."
        }
    }
}

struct KeychainStore {
    private let service = "org.church.servicescheduler"

    func symmetricKey(account: String) throws -> SymmetricKey {
        if let existing = try read(account: account) {
            return SymmetricKey(data: existing)
        }

        let keyData = try Self.randomData(count: 32)
        try write(keyData, account: account)
        return SymmetricKey(data: keyData)
    }

    func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainReadFailed(status)
        }
        return item as? Data
    }

    func write(_ data: Data, account: String) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainWriteFailed(status)
        }
    }

    static func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw SecureStorageError.randomBytesFailed(status)
        }
        return Data(bytes)
    }
}

struct EncryptedDataStore {
    private let keychain = KeychainStore()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChurchServiceScheduler", isDirectory: true)
        return directory.appendingPathComponent("data.dmsdb")
    }

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .seed
        }

        let encrypted = try Data(contentsOf: fileURL)
        let box = try AES.GCM.SealedBox(combined: encrypted)

        let key = try keychain.symmetricKey(account: "databaseKey")
        let decrypted = try AES.GCM.open(box, using: key)
        return try decoder.decode(AppData.self, from: decrypted)
    }

    func save(_ data: AppData) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let key = try keychain.symmetricKey(account: "databaseKey")
        let plaintext = try encoder.encode(data)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw SecureStorageError.invalidCiphertext
        }
        try combined.write(to: fileURL, options: .atomic)
    }

    func exportBackup(data: AppData, password: String) throws -> Data {
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecureStorageError.missingBackupPassword
        }
        let plaintext = try encoder.encode(data)
        return try BackupCrypto.encrypt(plaintext, password: password)
    }

    func importBackup(_ backup: Data, password: String) throws -> AppData {
        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecureStorageError.missingBackupPassword
        }
        let plaintext = try BackupCrypto.decrypt(backup, password: password)
        return try decoder.decode(AppData.self, from: plaintext)
    }
}

enum BackupCrypto {
    private static let magic = Data("DMSBK1".utf8)
    private static let saltLength = 16

    static func encrypt(_ plaintext: Data, password: String) throws -> Data {
        let salt = try KeychainStore.randomData(count: saltLength)
        let key = keyFromPassword(password, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw SecureStorageError.invalidBackup
        }

        var output = Data()
        output.append(magic)
        output.append(salt)
        output.append(combined)
        return output
    }

    static func decrypt(_ encrypted: Data, password: String) throws -> Data {
        guard encrypted.count > magic.count + saltLength else {
            throw SecureStorageError.invalidBackup
        }
        guard encrypted.prefix(magic.count) == magic else {
            throw SecureStorageError.invalidBackup
        }

        let saltStart = magic.count
        let saltEnd = saltStart + saltLength
        let salt = encrypted.subdata(in: saltStart..<saltEnd)
        let combined = encrypted.subdata(in: saltEnd..<encrypted.count)
        let box = try AES.GCM.SealedBox(combined: combined)

        do {
            return try AES.GCM.open(box, using: keyFromPassword(password, salt: salt))
        } catch {
            throw SecureStorageError.invalidBackup
        }
    }

    private static func keyFromPassword(_ password: String, salt: Data) -> SymmetricKey {
        var material = Data("ChurchServiceSchedulerBackup".utf8)
        material.append(salt)
        material.append(Data(password.utf8))
        let digest = SHA256.hash(data: material)
        return SymmetricKey(data: Data(digest))
    }
}

enum PINHasher {
    static func makeSalt() throws -> String {
        try KeychainStore.randomData(count: 16).base64EncodedString()
    }

    static func hash(pin: String, salt: String) -> String {
        let material = Data("\(salt):\(pin)".utf8)
        let digest = SHA256.hash(data: material)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
