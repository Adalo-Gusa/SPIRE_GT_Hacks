import Foundation

extension URLSession {
    /// Performs the request, validates a 2xx status, and returns the raw body.
    func validatedData(for request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.data(for: request)
        } catch {
            throw NetworkError.transport(error)
        }
        try Self.validate(response, body: data)
        return data
    }

    func decoded<T: Decodable>(_ type: T.Type, for request: URLRequest, decoder: JSONDecoder = .heirLoom()) async throws -> T {
        let data = try await validatedData(for: request)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding(error)
        }
    }

    /// Streams the response body line by line, e.g. for server-sent events.
    func validatedLines(for request: URLRequest) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await self.bytes(for: request)
        } catch {
            throw NetworkError.transport(error)
        }
        try Self.validate(response, body: nil)
        return bytes.lines
    }

    static func validate(_ response: URLResponse, body: Data?) throws {
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw NetworkError.httpStatus(http.statusCode, body) }
    }
}

extension URLRequest {
    static func json(_ method: String, url: URL, bearerToken: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func json<Body: Encodable>(
        _ method: String,
        url: URL,
        body: Body,
        bearerToken: String? = nil,
        encoder: JSONEncoder = .heirLoom()
    ) throws -> URLRequest {
        var request = json(method, url: url, bearerToken: bearerToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw NetworkError.encoding(error)
        }
        return request
    }
}
