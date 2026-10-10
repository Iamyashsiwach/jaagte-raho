import Foundation
import Security

struct BackendClient {
    let baseURL: URL
    let token: String
    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    func status() async throws -> ServerStatus {
        try await json(request("v1/status"))
    }
    func conversation(_ transcript: String, language: VoiceLanguage) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["transcript": transcript, "language": language.rawValue])
        let response: ConversationReply = try await json(request("v1/conversation", method: "POST", body: body))
        return response.text
    }
    func speech(_ text: String, language: VoiceLanguage) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: ["text": text, "language": language.rawValue])
        let (data, response) = try await URLSession.shared.data(for: request("v1/voice", method: "POST", body: body))
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              data.count > 44, String(data: data.prefix(4), encoding: .ascii) == "RIFF" else { throw BackendError.unavailable }
        return data
    }
    func send(_ event: TripEvent) async throws -> FleetReceipt {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try await json(request("v1/events", method: "POST", body: encoder.encode(event)))
    }
    func receipt(for id: UUID) async throws -> FleetReceipt {
        try await json(request("v1/events/\(id.uuidString)"))
    }
    private func json<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BackendError.unavailable }
        guard (200..<300).contains(response.statusCode) else { throw BackendError.httpStatus(response.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    enum BackendError: Error { case unavailable, httpStatus(Int) }
    struct ConversationReply: Decodable { let text: String }
}
struct ServerStatus: Decodable {
    let conversationConfigured: Bool
    let speechConfigured: Bool
    let fleetConfigured: Bool
    let model: String
}
struct FleetReceipt: Decodable { let id: UUID; let delivery: String; let simulated: Bool }

enum KeychainToken {
    private static let service = "com.jaagteraho.backend"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "app-token",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    @discardableResult static func save(_ token: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "app-token"]
        SecItemDelete(query as CFDictionary)
        if token.isEmpty { return true }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
