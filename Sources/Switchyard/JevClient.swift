import Foundation
import RouterCore

struct JevFailure: Error {
    let reason: FallbackReason
}

/// Minimal client for TypeSafe's System One endpoint, tuned for latency:
/// one long-lived session (HTTP/2 connection reuse), a hard deadline, and pre-warming.
final class JevClient: Sendable {
    static let deadline: Duration = .milliseconds(1200)

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 5
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    /// Open (or keep open) the TLS connection so the next real request skips the handshake.
    /// Doubles as the reachability check: true if Jev's server answered at all (any HTTP status
    /// over verified HTTPS means the network gets through).
    @discardableResult
    func prewarm() async -> Bool {
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai/")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return response is HTTPURLResponse
    }

    func ask(_ body: Jev.Request, apiKey: String, deadline: Duration = JevClient.deadline) async throws -> Jev.Response {
        var request = URLRequest(url: Jev.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let session = session
        let finalRequest = request
        return try await withThrowingTaskGroup(of: Jev.Response.self) { group in
            group.addTask {
                try await Self.send(finalRequest, session: session)
            }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw JevFailure(reason: .timeout)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw JevFailure(reason: .timeout) }
            return first
        }
    }

    private static func send(_ request: URLRequest, session: URLSession) async throws -> Jev.Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw JevFailure(reason: FallbackReason(urlErrorCode: error.code))
        } catch is CancellationError {
            throw JevFailure(reason: .timeout)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            break
        case 401, 403:
            throw JevFailure(reason: .unauthorized)
        case 429:
            throw JevFailure(reason: .rateLimited)
        case 503, 529:
            throw JevFailure(reason: .overloaded)
        default:
            throw JevFailure(reason: .http(status))
        }

        do {
            return try JSONDecoder().decode(Jev.Response.self, from: data)
        } catch {
            throw JevFailure(reason: .invalidResponse)
        }
    }
}
