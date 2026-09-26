import Foundation

enum NetworkError: Error, LocalizedError {
    case httpStatus(Int, Data?)
    case decoding(any Error)
    case encoding(any Error)
    case transport(any Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let data):
            "Server returned HTTP \(code)" + (Self.serverDetail(from: data).map { ": \($0)" } ?? "")
        case .decoding(let error):
            "Failed to decode response: \(error.localizedDescription)"
        case .encoding(let error):
            "Failed to encode request: \(error.localizedDescription)"
        case .transport(let error):
            "Network request failed: \(error.localizedDescription)"
        case .invalidResponse:
            "The server response was not HTTP."
        }
    }

    /// The middleware's short `{"detail": "..."}` message. Raw bodies are never shown to the user.
    static func serverDetail(from data: Data?) -> String? {
        guard let data,
              let body = try? JSONDecoder().decode(ErrorBody.self, from: data),
              case .message(let text) = body.detail,
              !text.isEmpty else { return nil }
        return String(text.prefix(200))
    }
}

private struct ErrorBody: Decodable {
    enum Detail: Decodable {
        case message(String)
        case other

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .message(text)
            } else {
                // FastAPI validation errors put a list here; don't surface it verbatim.
                self = .other
            }
        }
    }

    let detail: Detail
}
