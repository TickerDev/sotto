import Foundation
import LocalAuthentication
import Security
import SottoTools

public protocol CredentialStorage: Sendable {
    func containsKey() async throws -> Bool
    func read() async throws -> String?
    func save(_ key: String) async throws
}

/// Security.framework calls may wait for Keychain UI. None may run on MainActor.
public final class KeychainCredentials: CredentialStorage, Sendable {
    public static let shared = KeychainCredentials()
    private let queue = DispatchQueue(label: "org.sotto.mac.keychain", qos: .userInitiated)
    private let readOperation: @Sendable () throws -> String?
    private let saveOperation: @Sendable (String) throws -> Void
    private let containsOperation: @Sendable () throws -> Bool
    public init(account: String = "openai") {
        readOperation = { try KeychainStore.read(credentialAccount: account) }
        saveOperation = { try KeychainStore.save($0, credentialAccount: account) }
        containsOperation = { try KeychainStore.containsWithoutPrompt(credentialAccount: account) }
    }
    init(read: @escaping @Sendable () throws -> String?, save: @escaping @Sendable (String) throws -> Void, contains: @escaping @Sendable () throws -> Bool) {
        readOperation = read; saveOperation = save; containsOperation = contains
    }
    public func containsKey() async throws -> Bool { try await perform(containsOperation) }
    public func read() async throws -> String? { try await perform(readOperation) }
    public func save(_ key: String) async throws { try await perform { try self.saveOperation(key) } }
    private func perform<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let cancellation = CredentialCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        try cancellation.check()
                        let value = try operation()
                        try cancellation.check()
                        continuation.resume(returning: value)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }
}
private final class CredentialCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    func check() throws { if lock.withLock({ cancelled }) { throw CancellationError() } }
}

extension KeychainStore {
    /// Inspect metadata at launch without reading the secret or opening an authorization dialog.
    static func containsWithoutPrompt(credentialAccount: String = "openai") throws -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service, kSecAttrAccount: credentialAccount,
            kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: context
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw ToolError.unavailable("Keychain needs authorization. Click Verify connection to allow access, or unlock your login Keychain.") }
        return true
    }
}
