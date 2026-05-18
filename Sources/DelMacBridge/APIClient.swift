import Foundation

final class APIClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func completePairing(
        apiBaseURL: URL,
        token: String,
        deviceName: String
    ) async throws -> PairingCompleteResponse {
        var request = URLRequest(url: endpoint("/api/mac-bridge/pair/complete", baseURL: apiBaseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "token": token,
            "deviceName": deviceName,
        ])

        return try await send(request)
    }

    func sync(
        apiBaseURL: URL,
        deviceToken: String,
        batch: SyncBatch
    ) async throws -> SyncResponse {
        var request = URLRequest(url: endpoint("/api/mac-bridge/sync", baseURL: apiBaseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(batch)

        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }

    private func endpoint(_ path: String, baseURL: URL) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpStatus(let status):
            return "The server returned HTTP \(status)."
        }
    }
}
