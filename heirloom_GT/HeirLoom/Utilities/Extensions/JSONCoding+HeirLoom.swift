import Foundation

extension JSONDecoder {
    /// Decoder matching the FastAPI middleware: ISO 8601 dates, with or without fractional seconds.
    /// Models declare explicit snake_case `CodingKeys`; `convertFromSnakeCase` would turn `author_id` into `authorId`, not `authorID`.
    static func heirLoom() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle()) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized ISO 8601 date: \(string)")
        }
        return decoder
    }
}

extension JSONEncoder {
    static func heirLoom() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
