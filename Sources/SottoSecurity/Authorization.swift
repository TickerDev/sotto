import Foundation
import Security
import SottoTools

public struct Approval: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let tool: String
    public let arguments: JSONValue
    public init(tool: String, arguments: JSONValue) { id = UUID(); self.tool = tool; self.arguments = arguments }
}
public actor AuthorizationGate {
    private var pending: (Approval, CheckedContinuation<Bool, Never>)?
    public init() {}
    public func authorize(_ descriptor: ToolDescriptor, arguments: JSONValue, present: @escaping @Sendable (Approval) async -> Void) async throws {
        try Task.checkCancellation()
        try descriptor.validate(arguments)
        guard descriptor.risk == .consequential else { return }
        guard pending == nil else { throw ToolError.denied("Another action is awaiting approval") }
        let request = Approval(tool: descriptor.id, arguments: arguments)
        let allowed = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending = (request, continuation)
                Task { await present(request) }
            }
        } onCancel: { Task { await self.resolve(request.id, allowed: false) } }
        try Task.checkCancellation()
        guard allowed else { throw ToolError.denied("Action was not approved") }
    }
    public func resolve(_ id: UUID, allowed: Bool) {
        guard let (request, continuation) = pending, request.id == id else { return }
        pending = nil; continuation.resume(returning: allowed)
    }
}
public enum KeychainStore {
    static let service = "org.sotto.mac.provider"
    static let account = "openai"
    public static func read() throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            if [errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed].contains(status) { throw ToolError.denied("Keychain access was cancelled or not allowed. Use Verify connection to authorize the saved key.") }
            throw ToolError.unavailable("Keychain read failed (\(status))")
        }
        return String(data: data, encoding: .utf8)
    }
    public static func save(_ key: String) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as [CFString: Any]
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ToolError.unavailable("Keychain could not remove the saved key (\(status))") }
            return
        }
        let attributes = [kSecValueData: Data(key.utf8)] as [CFString: Any]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData] = Data(key.utf8); item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw ToolError.unavailable("Keychain save failed (\(added))") }; return
        }
        guard status == errSecSuccess else { throw ToolError.unavailable("Keychain save failed (\(status))") }
    }
}
